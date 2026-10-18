import Carbon

/// Global ⌃⌥⌘B through Carbon, which needs no Accessibility permission. Calls back on the main thread.
/// Nil when another app already owns the shortcut.
// ponytail: fixed shortcut, make it configurable when users ask
final class HotKey {
    private let action: () -> Void
    private var ref: EventHotKeyRef?

    init?(action: @escaping () -> Void) {
        self.action = action
        guard RegisterEventHotKey(
            UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey | cmdKey),
            EventHotKeyID(signature: OSType(0x5357_4244), id: 1), // 'SWBD'
            GetApplicationEventTarget(), 0, &ref
        ) == noErr else { return nil }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(data).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
}
