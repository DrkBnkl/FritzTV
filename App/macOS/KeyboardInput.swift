import SwiftUI

/// Mac-Tastatur statt Siri Remote:
/// ↑/↓ = Sender, Return = Klick, Esc = Zurück, Leertaste = Play/Pause, ←/→ = 10 s, Ziffern = Direktwahl.
struct RemoteInputModifier: ViewModifier {
    @ObservedObject var model: AppModel
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .escape, .space]) { press in
                switch press.key {
                case .upArrow: model.handle(.up)
                case .downArrow: model.handle(.down)
                case .leftArrow: model.handle(.left)
                case .rightArrow: model.handle(.right)
                case .return: model.handle(.select)
                case .escape: model.handle(.back)
                case .space: model.handle(.playPause)
                default: return .ignored
                }
                return .handled
            }
            .onKeyPress(characters: .decimalDigits) { press in
                guard let digit = Int(press.characters) else { return .ignored }
                model.handle(.digit(digit))
                return .handled
            }
            .onAppear { focused = true }
            .onChange(of: model.showSettings) { _, showing in
                if !showing { focused = true }
            }
            .onChange(of: model.showMediathek) { _, showing in
                if !showing { focused = true }
            }
    }
}
