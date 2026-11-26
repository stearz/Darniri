import AppKit
import Darwin

/// Private MultitouchSupport ABI, isolated here so an unavailable framework only disables gestures.
/// Contact records have a 96-byte stride; identity/state and normalized x/y live at 16/20 and 32/36.
@MainActor
final class TrackpadGestureMonitor {
    private typealias FrameCallback = @convention(c) (
        UnsafeRawPointer?, UnsafeRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Register = @convention(c) (UnsafeRawPointer, FrameCallback) -> Void
    private typealias Start = @convention(c) (UnsafeRawPointer, Int32) -> Void
    private typealias Stop = @convention(c) (UnsafeRawPointer) -> Void
    private typealias ReadDeviceID = @convention(c) (UnsafeRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias SensorDimensions = @convention(c) (
        UnsafeRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>
    ) -> Int32

    private struct API {
        let handle: UnsafeMutableRawPointer
        let createList: CreateList
        let register: Register
        let unregister: Register
        let start: Start
        let stop: Stop
        let deviceID: ReadDeviceID
        let sensorDimensions: SensorDimensions

        init?() {
            let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
            guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { return nil }
            func symbol<T>(_ name: String, as type: T.Type) -> T? {
                dlsym(handle, name).map { unsafeBitCast($0, to: type) }
            }
            guard let createList = symbol("MTDeviceCreateList", as: CreateList.self),
                  let register = symbol("MTRegisterContactFrameCallback", as: Register.self),
                  let unregister = symbol("MTUnregisterContactFrameCallback", as: Register.self),
                  let start = symbol("MTDeviceStart", as: Start.self),
                  let stop = symbol("MTDeviceStop", as: Stop.self),
                  let deviceID = symbol("MTDeviceGetDeviceID", as: ReadDeviceID.self),
                  let sensorDimensions = symbol("MTDeviceGetSensorDimensions", as: SensorDimensions.self)
            else {
                dlclose(handle)
                return nil
            }
            self.handle = handle
            self.createList = createList
            self.register = register
            self.unregister = unregister
            self.start = start
            self.stop = stop
            self.deviceID = deviceID
            self.sensorDimensions = sensorDimensions
        }
    }

    private weak static var activeMonitor: TrackpadGestureMonitor?
    private static let callback: FrameCallback = { device, data, count, timestamp, _ in
        guard let device, let snapshot = decodeContacts(data: data, count: count) else { return 0 }
        let deviceID = UInt(bitPattern: device)
        let receivedAt = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async {
            activeMonitor?.receive(contacts: snapshot, deviceID: deviceID, timestamp: timestamp, receivedAt: receivedAt)
        }
        // Never consume a raw frame: doing so can disable macOS's gesture recognition.
        return 0
    }

    nonisolated static func decodeContacts(data: UnsafeRawPointer?, count: Int32) -> [TrackpadContact]? {
        guard (0 ... 16).contains(count), count == 0 || data != nil else { return nil }
        guard let data else { return [] }
        return (0 ..< Int(count)).compactMap { index in
            let record = data.advanced(by: index * 96)
            let state = record.load(fromByteOffset: 20, as: Int32.self)
            guard state == 3 || state == 4 else { return nil }
            return TrackpadContact(
                id: record.load(fromByteOffset: 16, as: Int32.self),
                x: Double(record.load(fromByteOffset: 32, as: Float.self)),
                y: Double(record.load(fromByteOffset: 36, as: Float.self))
            )
        }
    }

    private weak var controller: WMController?
    private var api: API?
    private struct Device {
        let pointer: UnsafeRawPointer
        // Each retained array owns its device references, including across subsequent enumerations.
        let owner: CFArray
        let attachedAt: Double
        var recognizer = FourFingerSwipeRecognizer()
    }

    private var devices: [UInt64: Device] = [:]
    private var deviceIDsByPointer: [UInt: UInt64] = [:]
    private var refreshTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(controller: WMController) {
        self.controller = controller
    }

    func start() {
        guard refreshTimer == nil else { return }
        if api == nil { api = API() }
        guard api != nil else {
            NSLog("Darniri: MultitouchSupport unavailable; four-finger navigation disabled")
            return
        }
        Self.activeMonitor = self
        refreshDevices()
        // Discover a Magic Trackpad connected after launch, without restarting running devices.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDevices() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.detachDevices()
                self?.refreshDevices()
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        detachDevices()
        if Self.activeMonitor === self { Self.activeMonitor = nil }
        // Keep the library loaded: callbacks already in flight must retain valid framework code.
    }

    private func refreshDevices() {
        guard let api, let list = api.createList()?.takeRetainedValue() else { return }
        var current: [UInt64: UnsafeRawPointer] = [:]
        for index in 0 ..< CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
            var rows: Int32 = 0
            var columns: Int32 = 0
            var id: UInt64 = 0
            // Exclude narrow surfaces such as Touch Bar. OpaqueSurface is false on current MacBook trackpads.
            guard api.sensorDimensions(device, &rows, &columns) == 0, rows >= 10, columns >= 10,
                  api.deviceID(device, &id) == 0
            else { continue }
            current[id] = device
        }
        for (id, device) in devices where current[id] == nil {
            api.stop(device.pointer)
            api.unregister(device.pointer, Self.callback)
            deviceIDsByPointer[UInt(bitPattern: device.pointer)] = nil
            devices[id] = nil
        }
        // Enumeration creates fresh pointers even for existing hardware. Compare physical IDs and
        // retain the original running device so a periodic scan cannot interrupt a swipe.
        for (id, pointer) in current where devices[id] == nil {
            devices[id] = Device(pointer: pointer, owner: list, attachedAt: ProcessInfo.processInfo.systemUptime)
            deviceIDsByPointer[UInt(bitPattern: pointer)] = id
            api.register(pointer, Self.callback)
            api.start(pointer, 0)
        }
    }

    private func detachDevices() {
        guard let api else { return }
        for device in devices.values {
            api.stop(device.pointer)
            api.unregister(device.pointer, Self.callback)
        }
        devices.removeAll()
        deviceIDsByPointer.removeAll()
    }

    private func receive(contacts: [TrackpadContact], deviceID: UInt, timestamp: Double, receivedAt: Double) {
        guard let controller, let id = deviceIDsByPointer[deviceID],
              let attachedAt = devices[id]?.attachedAt, receivedAt >= attachedAt
        else { return }
        let enabled = controller.isEnabled
            && !controller.isLockScreenActive
            && !controller.isFrontmostAppLockScreen()
            && !controller.serviceLifecycleManager.isSecureInputActive
            && !controller.isInteractiveGestureActive
        guard let direction = devices[id]?.recognizer.update(
            contacts: contacts, timestamp: timestamp, isEnabled: enabled
        ) else { return }
        controller.commandHandler.handleHotkeyCommand(FourFingerSwipeRecognizer.command(for: direction))
    }
}
