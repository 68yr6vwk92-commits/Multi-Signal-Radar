
import SwiftUI
import CoreBluetooth
import Combine

struct RadarDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var lastSeen: Date
}

final class RadarManager: NSObject, ObservableObject,
                          CBCentralManagerDelegate {

    @Published var devices: [RadarDevice] = []
    @Published var status = "Waiting for Bluetooth"
    @Published var scanning = false

    private var central: CBCentralManager!

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = "Bluetooth ready"
        case .poweredOff:
            status = "Bluetooth is OFF"
        case .unauthorized:
            status = "Bluetooth permission denied"
        case .unsupported:
            status = "Bluetooth unsupported"
        case .resetting:
            status = "Bluetooth resetting"
        default:
            status = "Bluetooth unavailable"
        }
    }

    func startScan() {
        guard central.state == .poweredOn else {
            status = "Bluetooth is not ready"
            return
        }

        devices.removeAll()

        central.scanForPeripherals(
            withServices: nil,
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ]
        )

        scanning = true
        status = "Scanning BLE advertisements..."
    }

    func stopScan() {
        central.stopScan()
        scanning = false
        status = "Scan stopped"
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier
        let signal = RSSI.intValue

        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Unknown BLE device"

        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].rssi = signal
            devices[index].lastSeen = Date()

            if devices[index].name == "Unknown BLE device" {
                devices[index].name = name
            }
        } else {
            devices.append(
                RadarDevice(
                    id: id,
                    name: name,
                    rssi: signal,
                    lastSeen: Date()
                )
            )
        }

        devices.sort { $0.rssi > $1.rssi }
    }
}

struct ContentView: View {
    @StateObject private var radar = RadarManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 14) {
                Text("MULTI-SIGNAL RADAR")
                    .font(.title2.bold())
                    .foregroundColor(.green)

                Text(radar.status)
                    .font(.caption)
                    .foregroundColor(.cyan)

                RadarView(devices: radar.devices)
                    .frame(width: 320, height: 320)

                HStack {
                    Button("START SCAN") {
                        radar.startScan()
                    }
                    .disabled(radar.scanning)
                    .tint(.green)
                    .buttonStyle(.borderedProminent)

                    Button("STOP") {
                        radar.stopScan()
                    }
                    .disabled(!radar.scanning)
                    .tint(.red)
                    .buttonStyle(.borderedProminent)
                }

                Text("DETECTED: \(radar.devices.count)")
                    .foregroundColor(.green)

                List(radar.devices) { device in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .foregroundColor(.green)

                        Text("RSSI: \(device.rssi) dBm")
                            .foregroundColor(.orange)

                        Text("Last seen: \(device.lastSeen.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .listRowBackground(Color.black)
                }
                
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}

struct RadarView: View {
    let devices: [RadarDevice]

    @State private var angle: Double = 0

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(
                x: size.width / 2,
                y: size.height / 2
            )

            let radius = min(size.width, size.height) / 2 - 10

            for i in 1...4 {
                let r = radius * CGFloat(i) / 4

                let rect = CGRect(
                    x: center.x - r,
                    y: center.y - r,
                    width: r * 2,
                    height: r * 2
                )

                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(.green.opacity(0.45))
                )
            }

            for i in 0..<8 {
                let a = Double(i) * .pi / 4

                var line = Path()
                line.move(to: center)
                line.addLine(to: CGPoint(
                    x: center.x + radius * CGFloat(cos(a)),
                    y: center.y + radius * CGFloat(sin(a))
                ))

                context.stroke(
                    line,
                    with: .color(.green.opacity(0.3))
                )
            }

            var beam = Path()
            beam.move(to: center)
            beam.addLine(to: CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            ))

            context.stroke(
                beam,
                with: .color(.green),
                lineWidth: 3
            )

            for device in devices {
                let strength = max(
                    0.05,
                    min(1.0, CGFloat(device.rssi + 100) / 65)
                )

                let r = radius * (1 - strength)

                let hash = device.id.uuidString.unicodeScalars
                    .reduce(0) {
                        ($0 &* 31 &+ Int($1.value)) & 0x7fffffff
                    }

                let a = Double(hash % 360) * .pi / 180

                let point = CGPoint(
                    x: center.x + r * CGFloat(cos(a)),
                    y: center.y + r * CGFloat(sin(a))
                )

                let dot = CGRect(
                    x: point.x - 5,
                    y: point.y - 5,
                    width: 10,
                    height: 10
                )

                context.fill(
                    Path(ellipseIn: dot),
                    with: .color(.red)
                )
            }
        }
        .onReceive(
            Timer.publish(
                every: 0.04,
                on: .main,
                in: .common
            ).autoconnect()
        ) { _ in
            angle = (angle + 0.05)
                .truncatingRemainder(dividingBy: 2 * .pi)
        }
    }
}
