import Carbon

/// Global ⌃⌥⌘B through Carbon, which needs no Accessibility permission. Calls back on the main thread.
/// Nil when another app holds the shortcut exclusively, or the handler could not be installed. Carbon
/// does not report an app that registered it without the exclusive option. Keep it for the app's life:
/// Carbon holds an unretained pointer to it.
// ponytail: fixed shortcut, make it configurable when users ask
@MainActor
final class HotKey {
    private let action: @MainActor () -> Void
    private var ref: EventHotKeyRef?

    init?(action: @escaping @MainActor () -> Void) {
        self.action = action
        // Exclusive: fails with eventHotKeyExistsErr when another app holds it exclusively, and no app
        // can take it exclusively after.
        guard RegisterEventHotKey(
            UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey | cmdKey),
            EventHotKeyID(signature: OSType(0x5357_4244), id: 1), // 'SWBD'
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref
        ) == noErr else { return nil }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // The application event target delivers on the main thread.
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { Unmanaged<HotKey>.fromOpaque(data).takeUnretainedValue().action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        guard installed == noErr else {
            UnregisterEventHotKey(ref)
            return nil
        }
    }
}
