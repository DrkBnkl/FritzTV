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
                // Live-Bild: oben/unten kurz zurückhalten. Erkennt `RemotePressBridge` in dieser
                // Zeit ein Wischen, öffnet das die Senderleiste bzw. Info; sonst wird gezappt
                // (Klick auf den Ring). Wischen löst ebenfalls einen Move-Befehl aus.
                if model.isPlainLiveView, direction == .up || direction == .down {
                    RemoteSwipeArbiter.shared.deferMove(direction == .up ? .up : .down, model: model)
                    return
                }
                if model.searchResultDialog != nil {
                    switch direction {
                    case .up: NotificationCenter.default.post(name: .searchResultMove, object: -1)
                    case .down: NotificationCenter.default.post(name: .searchResultMove, object: 1)
                    default: break
                    }
                    return
                }
                if model.activeHLSReplay != nil {
                    switch direction {
                    case .left:
                        NotificationCenter.default.post(name: .hlsReplayJump, object: false)
                    case .right:
                        NotificationCenter.default.post(name: .hlsReplayJump, object: true)
                    default:
                        break
                    }
                    return
                }
                if model.activeMediathekURL != nil {
                    switch direction {
                    case .left:
                        NotificationCenter.default.post(name: .mediathekJump, object: false)
                    case .right:
                        NotificationCenter.default.post(name: .mediathekJump, object: true)
                    default:
                        break
                    }
                    return
                }
                switch direction {
                case .up: model.handle(.up)
                case .down: model.handle(.down)
                case .left: model.handle(.left)
                case .right: model.handle(.right)
                @unknown default: break
                }
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
            .onTapGesture {
                if model.searchResultDialog != nil {
                    NotificationCenter.default.post(name: .searchResultSelect, object: nil)
                    return
                }
                guard model.activeHLSReplay == nil, model.activeMediathekURL == nil else { return }
                model.handle(.select)
            }
            .onAppear { focused = true }
            .onChange(of: model.showSettings) { _, showing in
                if !showing { focused = true }
            }
            .onChange(of: model.showMediathek) { _, showing in
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
    final class Coordinator: NSObject {
        var model: AppModel
        private weak var installedWindow: UIWindow?

        init(model: AppModel) { self.model = model }

        func install(on window: UIWindow) {
            guard installedWindow !== window else { return }
            installedWindow = window
            add(press: .pageUp, to: window, action: #selector(pageUp))
            add(press: .pageDown, to: window, action: #selector(pageDown))
            add(swipe: .up, to: window, action: #selector(swipeUp))
            add(swipe: .down, to: window, action: #selector(swipeDown))
        }

        private func add(press: UIPress.PressType, to view: UIView, action: Selector) {
            let tap = UITapGestureRecognizer(target: self, action: action)
            tap.allowedPressTypes = [NSNumber(value: press.rawValue)]
            tap.allowedTouchTypes = []
            tap.cancelsTouchesInView = false
            view.addGestureRecognizer(tap)
        }

        private func add(swipe direction: UISwipeGestureRecognizer.Direction, to view: UIView, action: Selector) {
            let swipe = UISwipeGestureRecognizer(target: self, action: action)
            swipe.direction = direction
            swipe.cancelsTouchesInView = false
            view.addGestureRecognizer(swipe)
        }

        @objc private func swipeUp() { RemoteSwipeArbiter.shared.swiped(.swipeUp, model: model) }
        @objc private func swipeDown() { RemoteSwipeArbiter.shared.swiped(.swipeDown, model: model) }
        @objc private func pageUp() { model.handle(.pageUp) }
        @objc private func pageDown() { model.handle(.pageDown) }
    }
}

/// Trennt im Live-Bild Klick (zappen) und Wischen (Senderleiste/Info): Ein Wischen erzeugt
/// zuerst einen Move-Befehl und wird erst am Ende der Bewegung als Wischen erkannt. Deshalb wird
/// der Move-Befehl kurz zurückgehalten und verworfen, wenn in dieser Zeit ein Wischen kommt.
@MainActor
final class RemoteSwipeArbiter {
    static let shared = RemoteSwipeArbiter()
    private var pending: DispatchWorkItem?
    private var lastSwipe = Date.distantPast

    func deferMove(_ command: RemoteCommand, model: AppModel) {
        // Gerade gewischt (Erkennung kam vor dem Move-Befehl): nicht zusätzlich zappen.
        if Date().timeIntervalSince(lastSwipe) < 0.4 { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak model] in
            guard let model, model.isPlainLiveView else { return }
            model.handle(command)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func swiped(_ command: RemoteCommand, model: AppModel) {
        guard model.isPlainLiveView else { return }
        lastSwipe = Date()
        pending?.cancel()
        pending = nil
        withAnimation(.easeOut(duration: 0.25)) { model.handle(command) }
    }
}
