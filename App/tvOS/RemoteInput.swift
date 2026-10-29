import SwiftUI
import UIKit

/// Siri Remote: Touchpad-Rand bzw. Pfeile, Klick, Play/Pause, Zurück.
struct RemoteInputModifier: ViewModifier {
    @ObservedObject var model: AppModel
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .background(RemotePressBridge(model: model))
            .onMoveCommand { direction in
                RemoteInputArbiter.shared.handleMoveCommand(direction, model: model)
            }
            .onPlayPauseCommand {
                if model.activeHLSReplay != nil {
                    NotificationCenter.default.post(name: .hlsReplayTogglePause, object: nil)
                    return
                }
                if model.activeMediathekURL != nil {
                    NotificationCenter.default.post(name: .mediathekTogglePause, object: nil)
                    return
                }
                model.handle(.playPause)
            }
            .onExitCommand {
                if model.searchResultDialog != nil {
                    model.searchResultDialog = nil
                } else if model.activeHLSReplay != nil {
                    model.hlsReplayClosed()
                } else if model.activeMediathekURL != nil {
                    model.mediathekPlayClosed()
                } else {
                    model.handle(.back)
                }
            }
            .onAppear { focused = true }
            .onChange(of: model.showSettings) { _, showing in
                if !showing { focused = true }
            }
            .onChange(of: model.showEPGOverview) { _, _ in
                // Die Programmübersicht hat keine eigene Fokussteuerung mehr: Alle Tasten kommen
                // hier an und laufen über `model.handle`.
                focused = true
            }
            .onChange(of: model.activeHLSReplay != nil) { _, showing in
                if !showing { focused = true }
            }
            .onChange(of: model.activeMediathekURL != nil) { _, showing in
                if !showing { focused = true }
            }
            .onChange(of: model.searchResultDialog != nil) { _, showing in
                if !showing { focused = true }
            }
    }
}

/// Hängt Gestenerkenner an das Fenster, um auf dem Apple TV zu unterscheiden, was SwiftUI nicht
/// trennt: Klick auf den Ring oben/unten (zappen) und Wischen auf der Touch-Fläche (Senderleiste
/// bzw. Info, wie bei Apple). Dazu die Seitentasten kompatibler Fernbedienungen.
/// Die Erkenner fangen nichts ab (`cancelsTouchesInView = false`); außerhalb des reinen
/// Live-Bilds lassen sie Klick und Wischen unverändert an SwiftUI weiter.
private struct RemotePressBridge: UIViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: BridgeView, context: Context) {
        context.coordinator.model = model
    }

    final class BridgeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { coordinator?.install(on: window) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var model: AppModel
        private weak var installedWindow: UIWindow?

        init(model: AppModel) { self.model = model }

        func install(on window: UIWindow) {
            guard installedWindow !== window else { return }
            installedWindow = window

            add(press: .select, to: window, action: #selector(selectPress))
            add(press: .pageUp, to: window, action: #selector(pageUp))
            add(press: .pageDown, to: window, action: #selector(pageDown))
            add(swipe: .up, to: window, action: #selector(swipeUp))
            add(swipe: .down, to: window, action: #selector(swipeDown))
            add(hold: .upArrow, to: window, action: #selector(holdUp(_:)))
            add(hold: .downArrow, to: window, action: #selector(holdDown(_:)))
        }

        /// Gedrückt halten (Ring oben/unten): nach kurzer Zeit wiederholt weiterblättern.
        private func add(hold press: UIPress.PressType, to view: UIView, action: Selector) {
            let hold = UILongPressGestureRecognizer(target: self, action: action)
            hold.allowedPressTypes = [NSNumber(value: press.rawValue)]
            hold.allowedTouchTypes = []
            hold.minimumPressDuration = 0.4
            hold.allowableMovement = .greatestFiniteMagnitude
            hold.cancelsTouchesInView = false
            hold.delaysTouchesBegan = false
            hold.delaysTouchesEnded = false
            hold.delegate = self
            view.addGestureRecognizer(hold)
        }

        @objc private func holdUp(_ recognizer: UILongPressGestureRecognizer) {
            RemoteHoldRepeater.shared.update(recognizer.state, command: .up, model: model)
        }
        @objc private func holdDown(_ recognizer: UILongPressGestureRecognizer) {
            RemoteHoldRepeater.shared.update(recognizer.state, command: .down, model: model)
        }

        private func add(press: UIPress.PressType, to view: UIView, action: Selector) {
            let tap = UITapGestureRecognizer(target: self, action: action)
            tap.allowedPressTypes = [NSNumber(value: press.rawValue)]
            tap.allowedTouchTypes = []
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            view.addGestureRecognizer(tap)
        }

        private func add(swipe direction: UISwipeGestureRecognizer.Direction, to view: UIView, action: Selector) {
            let swipe = UISwipeGestureRecognizer(target: self, action: action)
            swipe.direction = direction
            swipe.cancelsTouchesInView = false
            swipe.delaysTouchesBegan = false
            swipe.delaysTouchesEnded = false
            swipe.delegate = self
            view.addGestureRecognizer(swipe)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc private func selectPress() { RemoteInputArbiter.shared.handle(.select, model: model) }
        @objc private func swipeUp() { RemoteSwipeArbiter.shared.swiped(.swipeUp, model: model) }
        @objc private func swipeDown() { RemoteSwipeArbiter.shared.swiped(.swipeDown, model: model) }
        @objc private func pageUp() {
            guard !model.showSettings else { return }
            model.handle(.pageUp)
        }
        @objc private func pageDown() {
            guard !model.showSettings else { return }
            model.handle(.pageDown)
        }
    }
}

/// Schnelle, verzögerungsfreie Eingabeverarbeitung für die Siri Remote auf dem Apple TV.
/// Verarbeitet Auswahl-Klicks direkt auf UIKit-Ebene und Richtungsbefehle ohne Zwischenschritte.
@MainActor
final class RemoteInputArbiter {
    static let shared = RemoteInputArbiter()

    /// Verarbeitet die Richtungsbefehle von SwiftUIs `onMoveCommand` (sowohl Klicks auf den Ring als auch Wischen).
    func handleMoveCommand(_ direction: MoveCommandDirection, model: AppModel) {
        // Bei gehaltenem Blättern verwerfen
        if (direction == .up || direction == .down), RemoteHoldRepeater.shared.swallowReleaseMove() {
            return
        }

        let cmd: RemoteCommand
        switch direction {
        case .up: cmd = .up
        case .down: cmd = .down
        case .left: cmd = .left
        case .right: cmd = .right
        @unknown default: return
        }

        handle(cmd, model: model)
    }

    /// Führt den Befehl direkt aus.
    func handle(_ command: RemoteCommand, model: AppModel) {
        guard !model.showSettings else { return }

        if command == .select {
            if model.searchResultDialog != nil {
                NotificationCenter.default.post(name: .searchResultSelect, object: nil)
                return
            }
            guard model.activeHLSReplay == nil, model.activeMediathekURL == nil else { return }
            model.handle(.select)
            return
        }

        if model.searchResultDialog != nil {
            switch command {
            case .up: NotificationCenter.default.post(name: .searchResultMove, object: -1)
            case .down: NotificationCenter.default.post(name: .searchResultMove, object: 1)
            default: break
            }
            return
        }

        if model.activeHLSReplay != nil {
            switch command {
            case .left: NotificationCenter.default.post(name: .hlsReplayJump, object: false)
            case .right: NotificationCenter.default.post(name: .hlsReplayJump, object: true)
            default: break
            }
            return
        }

        if model.activeMediathekURL != nil {
            switch command {
            case .left: NotificationCenter.default.post(name: .mediathekJump, object: false)
            case .right: NotificationCenter.default.post(name: .mediathekJump, object: true)
            default: break
            }
            return
        }

        model.handle(command)
    }
}

/// Verarbeitet Wischgesten auf der Touchfläche im Live-Bild (Öffnen der Senderleiste bzw. Sendungsinfo).
@MainActor
final class RemoteSwipeArbiter {
    static let shared = RemoteSwipeArbiter()

    func swiped(_ command: RemoteCommand, model: AppModel) {
        guard model.isPlainLiveView else { return }
        withAnimation(.easeOut(duration: 0.22)) { model.handle(command) }
    }
}

/// Wiederholt oben/unten, solange die Taste gehalten wird – in der Programmübersicht und in der
/// Senderliste, nicht im Live-Bild (dort würde Halten durch alle Sender zappen). Erst ruhig
/// (8 Schritte/s), nach gut einer Sekunde schneller (15/s).
@MainActor
final class RemoteHoldRepeater {
    static let shared = RemoteHoldRepeater()
    fileprivate var task: Task<Void, Never>?
    private var repeatEndedAt = Date.distantPast

    /// Wahr während und direkt nach einem gehaltenen Blättern (die Reihenfolge von Loslassen und
    /// Ende der Geste ist nicht festgelegt).
    func swallowReleaseMove() -> Bool {
        if task != nil { return true }
        guard Date().timeIntervalSince(repeatEndedAt) < 0.3 else { return false }
        repeatEndedAt = .distantPast
        return true
    }

    func update(_ state: UIGestureRecognizer.State, command: RemoteCommand, model: AppModel) {
        switch state {
        case .began:
            guard Self.allowsRepeat(model) else { return }
            task?.cancel()
            DebugLog.log("Halten: \(command) – blättern")
            task = Task { @MainActor [weak model] in
                var steps = 0
                while !Task.isCancelled {
                    guard let model, Self.allowsRepeat(model) else {
                        // Übersicht/Liste zu: nicht weiter Schritte schlucken.
                        RemoteHoldRepeater.shared.task = nil
                        return
                    }
                    model.handle(command)
                    steps += 1
                    try? await Task.sleep(for: .milliseconds(steps < 10 ? 125 : 65))
                }
            }
        case .ended, .cancelled, .failed:
            if task != nil { repeatEndedAt = Date() }
            task?.cancel()
            task = nil
        default:
            break
        }
    }

    private static func allowsRepeat(_ model: AppModel) -> Bool {
        if model.showEPGOverview { return model.epgNav.detail == nil }
        if case .channelList = model.overlay { return true }
        return false
    }
}
