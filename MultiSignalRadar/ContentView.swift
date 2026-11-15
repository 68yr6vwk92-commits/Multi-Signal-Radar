
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
                    with: .color(.green.opacity(0.40)),
                    lineWidth: 1
                )

                context.draw(
                    Text("\(Int(distance))m")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.green.opacity(0.75)),
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
                    with: .color(.green.opacity(0.18)),
                    lineWidth: 1
                )
            }

            // Glowing radar sweep trail
            for i in (1...12).reversed() {
                let trailAngle = angle - Double(i) * 0.075

                var trail = Path()
                trail.move(to: center)

                trail.addLine(to: CGPoint(
                    x: center.x + radius * CGFloat(cos(trailAngle)),
                    y: center.y + radius * CGFloat(sin(trailAngle))
                ))

                let opacity = 0.35 *
                    (1.0 - Double(i) / 13.0)

                context.stroke(
                    trail,
                    with: .color(.green.opacity(opacity)),
                    lineWidth: 2
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
                lineWidth: 2.5
            )

            // Pulsing detected devices
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

                let individualPulse = sin(
                    pulsePhase + Double(hash % 100) * 0.1
                )

                let dotSize = 5.0 + (individualPulse + 1) * 2.0

                // Outer red glow
                let glowSize = dotSize * 2.8

                let glow = CGRect(
                    x: point.x - glowSize / 2,
                    y: point.y - glowSize / 2,
                    width: glowSize,
                    height: glowSize
                )

                context.fill(
                    Path(ellipseIn: glow),
                    with: .color(.red.opacity(0.12 + 0.10 * (individualPulse + 1)))
                )

                // Pulsing red dot
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

                // Distance label
                context.draw(
                    Text(device.distanceLabel)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan),
                    at: CGPoint(
                        x: point.x + 17,
                        y: point.y - 9
                    )
                )
            }

            // Radar center
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

            pulsePhase += 0.12
        }
    }
}

