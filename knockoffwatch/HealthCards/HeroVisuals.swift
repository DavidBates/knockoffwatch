import SwiftUI

// MARK: - Heart Rate Hero

struct HeartRateHeroVisual: View {
    let bpm: String?
    let isMeasuring: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Image(systemName: "heart.fill")
                .font(.system(size: 100))
                .foregroundStyle(.red.opacity(0.10))
            Image(systemName: "heart.fill")
                .font(.system(size: 78))
                .foregroundStyle(.red)
                .scaleEffect(pulse ? 1.10 : 1.0)
                .shadow(color: .red.opacity(pulse ? 0.40 : 0.10), radius: pulse ? 10 : 3)
            VStack(spacing: 1) {
                Text(bpm ?? "--")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .monospacedDigit()
                Text("BPM")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .offset(y: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(bpm.map { "\($0) beats per minute" } ?? "Measuring heart rate")
        .onChange(of: isMeasuring) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { pulse = true }
            } else {
                withAnimation(.spring(duration: 0.3)) { pulse = false }
            }
        }
    }
}

// MARK: - Blood Pressure Hero

private struct ECGLineView: View {
    let beatDuration: Double

    // Normalized (x, y) control points for one P-QRS-T heartbeat cycle.
    // y=0 is top, y=1 is bottom; baseline sits at y≈0.55.
    private let ecgPoints: [(CGFloat, CGFloat)] = [
        (0.00, 0.55), (0.12, 0.55),
        (0.18, 0.46), (0.23, 0.55),   // P wave
        (0.30, 0.55), (0.37, 0.55),
        (0.40, 0.10),                   // R spike
        (0.43, 0.72),                   // S dip
        (0.49, 0.42), (0.56, 0.55),    // T wave
        (0.76, 0.55), (1.00, 0.55),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = CGFloat((t / beatDuration).truncatingRemainder(dividingBy: 1.0))
                let pts = ecgPoints.map { CGPoint(x: $0.0 * size.width, y: $0.1 * size.height) }
                drawECG(ctx: ctx, phase: phase, pts: pts)
            }
        }
    }

    private func drawECG(ctx: GraphicsContext, phase: CGFloat, pts: [CGPoint]) {
        // Faint static trace
        var fullPath = Path()
        fullPath.move(to: pts[0])
        pts.dropFirst().forEach { fullPath.addLine(to: $0) }
        ctx.stroke(fullPath, with: .color(.orange.opacity(0.18)), lineWidth: 1.5)

        // Lit trail: last 20% of path behind the dot
        let trailLen: CGFloat = 0.20
        let trailStart = max(0.0, phase - trailLen)
        var trailPath = Path()
        for i in 0...18 {
            let p = trailStart + (phase - trailStart) * CGFloat(i) / 18.0
            let pt = pointOnPath(pts: pts, phase: p)
            if i == 0 { trailPath.move(to: pt) } else { trailPath.addLine(to: pt) }
        }
        ctx.stroke(trailPath, with: .color(.orange.opacity(0.90)), lineWidth: 2.0)

        // Glowing dot
        let center = pointOnPath(pts: pts, phase: phase)
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)),
                 with: .color(.orange.opacity(0.28)))
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
                 with: .color(.orange))
    }

    private func pointOnPath(pts: [CGPoint], phase: CGFloat) -> CGPoint {
        let total = CGFloat(pts.count - 1)
        let raw = min(phase * total, total)
        let idx = Int(raw)
        let t = raw - CGFloat(idx)
        guard idx < pts.count - 1 else { return pts.last! }
        let a = pts[idx], b = pts[idx + 1]
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

struct BloodPressureHeroVisual: View {
    let sys: String?
    let dia: String?
    let isMeasuring: Bool
    let latestHR: Int?

    private var beatDuration: Double {
        guard let hr = latestHR, hr > 30, hr < 220 else { return 60.0 / 75.0 }
        return 60.0 / Double(hr)
    }

    private var a11yLabel: String {
        if let s = sys, let d = dia { return "\(s) over \(d) millimeters of mercury" }
        return "Measuring blood pressure"
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "stethoscope")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
                .opacity(isMeasuring ? 0.65 : 1.0)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(sys ?? "--")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .monospacedDigit()
                Text("/")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                Text(dia ?? "--")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }

            Text("mmHg")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            if isMeasuring {
                ECGLineView(beatDuration: beatDuration)
                    .frame(height: 26)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(a11yLabel)
    }
}

// MARK: - Blood Oxygen Hero

struct BloodOxygenHeroVisual: View {
    let pct: String?
    let isMeasuring: Bool
    @State private var breathScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "lungs.fill")
                .font(.system(size: 52))
                .foregroundStyle(.blue)
                .scaleEffect(breathScale)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(pct ?? "--")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text("SpO2")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(pct.map { "\($0) percent blood oxygen" } ?? "Measuring blood oxygen")
        .onChange(of: isMeasuring) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathScale = 1.18 }
            } else {
                withAnimation(.spring(duration: 0.4)) { breathScale = 1.0 }
            }
        }
    }
}

// MARK: - Preview

#Preview("Hero Visuals") {
    HStack(spacing: 0) {
        HeartRateHeroVisual(bpm: "72", isMeasuring: false)
            .frame(width: 140, height: 140)
        BloodPressureHeroVisual(sys: "118", dia: "76", isMeasuring: false, latestHR: 72)
            .frame(width: 140, height: 140)
        BloodOxygenHeroVisual(pct: "98", isMeasuring: false)
            .frame(width: 140, height: 140)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Hero Visuals — Measuring") {
    HStack(spacing: 0) {
        HeartRateHeroVisual(bpm: nil, isMeasuring: true)
            .frame(width: 140, height: 140)
        BloodPressureHeroVisual(sys: nil, dia: nil, isMeasuring: true, latestHR: 72)
            .frame(width: 140, height: 140)
        BloodOxygenHeroVisual(pct: nil, isMeasuring: true)
            .frame(width: 140, height: 140)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
