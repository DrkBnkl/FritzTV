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
                switch direction {
                case .up: model.handle(.up)
                case .down: model.handle(.down)
                case .left: model.handle(.left)
                case .right: model.handle(.right)
                @unknown default: break
                }
            }
            .onPlayPauseCommand { model.handle(.playPause) }
            .onExitCommand { model.handle(.back) }
            .onTapGesture { model.handle(.select) }
            .onAppear { focused = true }
            .onChange(of: model.showSettings) { _, showing in
                if !showing { focused = true }
            }
            .onChange(of: model.showMediathek) { _, showing in
                if !showing { focused = true }
            }
    }
}
