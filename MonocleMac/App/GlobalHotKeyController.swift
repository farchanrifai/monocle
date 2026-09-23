import AppKit
import Carbon

enum GlobalHotKeyError: LocalizedError {
    case unsupported, unavailable
    var errorDescription: String? {
        switch self {
        case .unsupported: "This key cannot be used as a global shortcut."
        case .unavailable: "That global shortcut is already used by another app or macOS."
        }
    }
}

@MainActor
final class GlobalHotKeyController {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    func register(_ chord: KeyChord, action: @escaping () -> Void) throws {
        guard let keyCode = Self.keyCodes[chord.key] else { throw GlobalHotKeyError.unsupported }
        let oldHotKey = hotKey
        if let oldHotKey { UnregisterEventHotKey(oldHotKey); hotKey = nil }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
                guard let data else { return noErr }
                let owner = Unmanaged<GlobalHotKeyController>.fromOpaque(data).takeUnretainedValue()
                Task { @MainActor in owner.action?() }
                return noErr
            }, 1, &spec, pointer, &handler)
            guard status == noErr else { throw GlobalHotKeyError.unavailable }
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, Self.carbonModifiers(chord.modifiers), EventHotKeyID(signature: 0x4D4F4E4F, id: 1), GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            if let oldHotKey { self.hotKey = oldHotKey }
            throw GlobalHotKeyError.unavailable
        }
        hotKey = ref
        self.action = action
    }

    private static func carbonModifiers(_ value: KeyModifiers) -> UInt32 {
        var result: UInt32 = 0
        if value.contains(.command) { result |= UInt32(cmdKey) }
        if value.contains(.option) { result |= UInt32(optionKey) }
        if value.contains(.control) { result |= UInt32(controlKey) }
        if value.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45,
        "m": 46, ".": 47, "space": 49, "escape": 53, "left": 123, "right": 124, "down": 125, "up": 126
    ]
}
