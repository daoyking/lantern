import Foundation
import CoreBluetooth

/// Bluetooth radar (common checklist #16): continuous scan for nearby
/// advertising devices with signal strength. macOS 27 removed the legacy
/// IOBluetooth enumeration C API (tbd exports only ~254 symbols — no
/// DeviceInquiry, no LocalDeviceConnectedDevices), so "who is already
/// connected" has no public path; CoreBluetooth scanning of nearby
/// advertising devices is the honest substitute. Enabling the feature
/// triggers the one-time system Bluetooth permission prompt (weather/
/// calendar pattern: only users who toggle it ever see it).
struct BTRadarEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

final class BluetoothRadarService: BaseFeatureService {

    static let shared = BluetoothRadarService(feature: .bluetoothRadar)

    @Published public private(set) var entries: [BTRadarEntry] = []
    @Published public private(set) var radioOn: Bool?

    private var box: CentralBox?

    private override init(feature: AppFeature) { super.init(feature: feature) }

    override public func start() throws { beginScan() }
    override public func stop() throws { stopScan() }

    deinit { stopScan() }

    private func beginScan() {
        guard box == nil else { return }
        let box = CentralBox(owner: self)
        box.central = CBCentralManager(delegate: box, queue: .main)
        self.box = box
    }

    private func stopScan() {
        box?.central.stopScan()
        box?.central.delegate = nil
        box = nil
        radioOn = nil
        entries = []
    }

    /// Public rescan hook for the section header button.
    public func rescan() {
        stopScan()
        beginScan()
    }

    fileprivate func upsert(id: UUID, name: String?, rssi: Int) {
        let entry = BTRadarEntry(id: id, name: name ?? "Bluetooth", rssi: rssi)
        entries.removeAll { $0.id == id }
        entries.append(entry)
        entries.sort { $0.rssi > $1.rssi }
        if entries.count > 12 { entries.removeFirst(entries.count - 12) }
    }

    fileprivate func setRadio(_ on: Bool?) { radioOn = on }
}

/// NSObject shim so the service can host a CBCentralManagerDelegate
/// (BaseFeatureService is not an NSObject).
final class CentralBox: NSObject, CBCentralManagerDelegate {
    weak var owner: BluetoothRadarService?
    var central: CBCentralManager!

    init(owner: BluetoothRadarService?) {
        self.owner = owner
        super.init()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        owner?.setRadio(central.state == .poweredOn)
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        owner?.upsert(id: peripheral.identifier,
                      name: peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String,
                      rssi: RSSI.intValue)
    }
}
