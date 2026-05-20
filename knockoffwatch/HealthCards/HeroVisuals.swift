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

struct BloodPressureHeroVisual: View {
    let sys: String?
    let dia: String?
    let isMeasuring: Bool
    @State private var arcTrim: Double = 0.35

    private var a11yLabel: String {
        if let s = sys, let d = dia { return "\(s) over \(d) millimeters of mercury" }
        return "Measuring blood pressure"
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.orange.opacity(0.15), lineWidth: 9)
            Circle()
                .trim(from: 0, to: arcTrim)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 3) {
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
            }
        }
        .frame(width: 126, height: 126)
        .accessibilityLabel(a11yLabel)
        .onChange(of: isMeasuring) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { arcTrim = 0.80 }
            } else {
                withAnimation(.easeOut(duration: 0.4)) { arcTrim = 0.35 }
            }
        }
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
        BloodPressureHeroVisual(sys: "118", dia: "76", isMeasuring: false)
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
        BloodPressureHeroVisual(sys: nil, dia: nil, isMeasuring: true)
            .frame(width: 140, height: 140)
        BloodOxygenHeroVisual(pct: nil, isMeasuring: true)
            .frame(width: 140, height: 140)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
