

import SwiftUI
import CoreBluetooth
import Combine
import CoreLocation

struct RadarDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var lastSeen: Date

    // Approximate BLE distance using RSSI
    var estimatedDistance: Double {
        let referenceRSSI = -59.0
        let pathLossExponent = 2.2

        let exponent = (referenceRSSI - Double(rssi)) /
                       (10.0 * pathLossExponent)

        let distance = pow(10.0, exponent)

        return min(50.0, max(0.3, distance))
    }

    var distanceLabel: String {
        if estimatedDistance >= 20 {
            return "20m+"
        }

        return String(format: "%.1fm", estimatedDistance)
    }
}

final class RadarManager: NSObject,
                          ObservableObject,
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

        guard signal < 0 else { return }

        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Unknown BLE device"

        if let index = devices.firstIndex(where: { $0.id == id }) {

            // Smooth RSSI changes
            let oldRSSI = devices[index].rssi
            devices[index].rssi = (oldRSSI * 3 + signal) / 4

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

        devices.sort {
            $0.estimatedDistance < $1.estimatedDistance
        }
    }
}

struct ContentView: View {
    @StateObject private var radar = RadarManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {

                Text("MULTI-SIGNAL RADAR")
                    .font(.title2.bold())
                    .foregroundColor(.green)

                Text(radar.status)
                    .font(.caption)
                    .foregroundColor(.cyan)

                RadarView(devices: radar.devices)
                    .frame(width: 320, height: 320)

                Text("DISTANCE IS RSSI-BASED ESTIMATION")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.gray)

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
                    VStack(alignment: .leading, spacing: 5) {

                        HStack {
                            Text(device.name)
                                .foregroundColor(.green)

                            Spacer()

                            Text(device.distanceLabel)
                                .foregroundColor(.cyan)
                                .fontWeight(.bold)
                        }

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
    @State private var pulsePhase: Double = 0

    private let maximumDistance = 20.0
    private let ringDistances: [Double] = [2, 5, 10, 20]

    var body: some View {
        Canvas { context, size in

            let center = CGPoint(
                x: size.width / 2,
                y: size.height / 2
            )

            let radius = min(size.width, size.height) / 2 - 15

            // Distance rings
            for distance in ringDistances {

                let ringRadius = radius *
                    CGFloat(distance / maximumDistance)

                let rect = CGRect(
                    x: center.x - ringRadius,
                    y: center.y - ringRadius,
                    width: ringRadius * 2,
                    height: ringRadius * 2
                )

                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(.green.opacity(0.55)),
                    lineWidth: 1
                )

                // Ring distance labels
                context.draw(
                    Text("\(Int(distance))m")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.green),
                    at: CGPoint(
                        x: center.x + 18,
                        y: center.y - ringRadius + 8
                    )
                )
            }

            // Radar direction lines
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
                    with: .color(.green.opacity(0.25)),
                    lineWidth: 1
                )
            }

            // Sweep trail behind scanning beam
            for trailIndex in (1...14).reversed() {

                let trailAngle = angle -
                    Double(trailIndex) * 0.045

                let trailOpacity =
                    Double(15 - trailIndex) / 15.0 * 0.22

                var trail = Path()
                trail.move(to: center)

                trail.addLine(to: CGPoint(
                    x: center.x + radius * CGFloat(cos(trailAngle)),
                    y: center.y + radius * CGFloat(sin(trailAngle))
                ))

                context.stroke(
                    trail,
                    with: .color(.green.opacity(trailOpacity)),
                    lineWidth: 1.5
                )
            }

            // Main scanning beam
            var beam = Path()
            beam.move(to: center)

            beam.addLine(to: CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            ))

            context.stroke(
                beam,
                with: .color(.green),
                lineWidth: 2
            )

            // Detected BLE devices
            for device in devices {

                let distance = device.estimatedDistance

                let normalizedDistance = min(
                    1.0,
                    distance / maximumDistance
                )

                let pointRadius = radius *
                    CGFloat(normalizedDistance)

                let hash = device.id.uuidString.unicodeScalars
                    .reduce(0) {
                        ($0 &* 31 &+ Int($1.value)) & 0x7fffffff
                    }

                let a = Double(hash % 360) * .pi / 180

                let point = CGPoint(
                    x: center.x + pointRadius * CGFloat(cos(a)),
                    y: center.y + pointRadius * CGFloat(sin(a))
                )

                // Individual pulse animation
                let individualPulse = sin(
                    pulsePhase + Double(hash % 100) * 0.1
                )

                let pulse = (individualPulse + 1.0) / 2.0

                let dotSize: CGFloat =
                    5.0 + CGFloat(pulse * 3.0)

                let glowSize = dotSize * 2.8

                // Outer red glow
                let glow = CGRect(
                    x: point.x - glowSize / 2,
                    y: point.y - glowSize / 2,
                    width: glowSize,
                    height: glowSize
                )

                context.fill(
                    Path(ellipseIn: glow),
                    with: .color(
                        .red.opacity(0.12 + pulse * 0.10)
                    )
                )

                // Main red pulse dot
                let dot = CGRect(
                    x: point.x - dotSize / 2,
                    y: point.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )

                context.fill(
                    Path(ellipseIn: dot),
                    with: .color(.red)
                )

                // Distance beside device
                let labelPosition = CGPoint(
                    x: point.x + 17,
                    y: point.y - 9
                )

                context.draw(
                    Text(device.distanceLabel)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan),
                    at: labelPosition
                )
            }

            // Radar center glow
            let centerGlow = CGRect(
                x: center.x - 7,
                y: center.y - 7,
                width: 14,
                height: 14
            )

            context.fill(
                Path(ellipseIn: centerGlow),
                with: .color(.green.opacity(0.15))
            )

            // Radar center dot
            let centerDot = CGRect(
                x: center.x - 3,
                y: center.y - 3,
                width: 6,
                height: 6
            )

            context.fill(
                Path(ellipseIn: centerDot),
                with: .color(.green)
            )
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

            pulsePhase = (pulsePhase + 0.12)
                .truncatingRemainder(dividingBy: 2 * .pi)
        }
    }
    final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var status = "Waiting for GPS"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            status = "GPS ACTIVE"
            manager.startUpdatingLocation()
        case .denied, .restricted:
            status = "GPS PERMISSION DENIED"
        default:
            status = "WAITING FOR GPS PERMISSION"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }
}
