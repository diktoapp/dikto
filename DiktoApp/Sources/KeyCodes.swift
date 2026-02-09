import Carbon

/// Single source of truth for Carbon virtual key code ↔ name mapping.
enum KeyCodes {
    /// All known key code entries: (keyCode, lowercaseName, displayName)
    static let entries: [(code: UInt16, name: String, display: String)] = [
        // Letters
        (0x00, "a", "A"), (0x01, "s", "S"), (0x02, "d", "D"), (0x03, "f", "F"),
        (0x04, "h", "H"), (0x05, "g", "G"), (0x06, "z", "Z"), (0x07, "x", "X"),
        (0x08, "c", "C"), (0x09, "v", "V"), (0x0B, "b", "B"), (0x0C, "q", "Q"),
        (0x0D, "w", "W"), (0x0E, "e", "E"), (0x0F, "r", "R"), (0x10, "y", "Y"),
        (0x11, "t", "T"), (0x1F, "o", "O"), (0x20, "u", "U"), (0x22, "i", "I"),
        (0x23, "p", "P"), (0x25, "l", "L"), (0x26, "j", "J"), (0x28, "k", "K"),
        (0x2D, "n", "N"), (0x2E, "m", "M"),
        // Numbers
        (0x1D, "0", "0"), (0x12, "1", "1"), (0x13, "2", "2"), (0x14, "3", "3"),
        (0x15, "4", "4"), (0x17, "5", "5"), (0x16, "6", "6"), (0x1A, "7", "7"),
        (0x1C, "8", "8"), (0x19, "9", "9"),
        // Special keys
        (0x31, "space", "Space"), (0x24, "return", "Return"), (0x30, "tab", "Tab"),
        (0x35, "escape", "Escape"), (0x33, "delete", "Delete"),
        (0x75, "forwarddelete", "Forward Delete"),
        (0x7B, "leftarrow", "Left Arrow"), (0x7C, "rightarrow", "Right Arrow"),
        (0x7D, "downarrow", "Down Arrow"), (0x7E, "uparrow", "Up Arrow"),
        (0x73, "home", "Home"), (0x77, "end", "End"),
        (0x74, "pageup", "Page Up"), (0x79, "pagedown", "Page Down"),
        // Punctuation
        (0x1B, "-", "-"), (0x18, "=", "="), (0x21, "[", "["), (0x1E, "]", "]"),
        (0x2A, "\\", "\\"), (0x29, ";", ";"), (0x27, "'", "'"), (0x2B, ",", ","),
        (0x2F, ".", "."), (0x2C, "/", "/"), (0x32, "`", "`"),
        // Function keys
        (0x7A, "f1", "F1"), (0x78, "f2", "F2"), (0x63, "f3", "F3"), (0x76, "f4", "F4"),
        (0x60, "f5", "F5"), (0x61, "f6", "F6"), (0x62, "f7", "F7"), (0x64, "f8", "F8"),
        (0x65, "f9", "F9"), (0x6D, "f10", "F10"), (0x67, "f11", "F11"), (0x6F, "f12", "F12"),
    ]

    /// Map lowercase key name → Carbon key code.
    static let nameToCode: [String: UInt16] = {
        Dictionary(entries.map { ($0.name, $0.code) }, uniquingKeysWith: { first, _ in first })
    }()

    /// Map Carbon key code → display name.
    static let codeToDisplay: [UInt16: String] = {
        Dictionary(entries.map { ($0.code, $0.display) }, uniquingKeysWith: { first, _ in first })
    }()
}
