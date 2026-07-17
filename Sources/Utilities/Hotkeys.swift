import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Translate the current selection and show it in the floating panel.
    static let translateRead = Self("translateRead", initial: .init(.t, modifiers: [.control, .command]))
    /// Translate the focused field (or selection) and replace it in place.
    static let translateReplace = Self("translateReplace", initial: .init(.r, modifiers: [.control, .command]))
}
