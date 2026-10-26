import SwiftUI

/// Siri Remote: Touchpad-Rand bzw. Pfeile, Klick, Play/Pause, Zurück.
struct RemoteInputModifier: ViewModifier {
    @ObservedObject var model: AppModel
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onMoveCommand { direction in
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
