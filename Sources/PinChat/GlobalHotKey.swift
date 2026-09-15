import Carbon
import Foundation

final class GlobalHotKey: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: @MainActor @Sendable () -> Void

    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    deinit {
        unregister()
    }

    @discardableResult
    func registerOptionSpace() -> Bool {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                DispatchQueue.main.async { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandlerRef
        )
        guard installStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: OSType(0x50434854), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return registerStatus == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
