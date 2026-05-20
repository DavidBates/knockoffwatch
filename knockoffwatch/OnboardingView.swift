import SwiftUI
import UIKit
import CoreBluetooth

// MARK: - Root onboarding container

struct OnboardingView: View {
    @Environment(BluetoothManager.self) private var bluetooth
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            welcomePage.tag(0)
            pairPage.tag(1)
            bluetoothPage.tag(2)
            healthPage.tag(3)
            connectPage.tag(4)
            finishPage.tag(5)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .animation(.easeInOut, value: currentPage)
        .ignoresSafeArea()
    }

    // MARK: Page 1 — Welcome

    private var welcomePage: some View {
        OnboardingPageView(
            systemImage: "applewatch",
            imageColor: .blue,
            title: "Welcome to\nLaxasFit Watch",
            subtitle: "Sync your LaxasFit Watch Ultra with Apple Health and keep track of your heart rate, blood pressure, and blood oxygen.",
            buttonLabel: "Get Started",
            action: { currentPage = 1 },
            extra: {
                Text("Personal reverse-engineering project. Not affiliated with or endorsed by the watch manufacturer. Health readings from unsupported third-party devices should not be used for medical decisions.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        )
    }

    // MARK: Page 2 — Pair the Watch

    private var pairPage: some View {
        OnboardingPageView(
            systemImage: "wave.3.right.circle.fill",
            imageColor: .blue,
            title: "Pair Your Watch",
            subtitle: "Make sure your LaxasFit Watch Ultra is:\n\n• Powered on\n• Charged or charging\n• Within Bluetooth range of your iPhone",
            buttonLabel: "Next",
            action: { currentPage = 2 }
        )
    }

    // MARK: Page 3 — Enable Bluetooth

    private var bluetoothPage: some View {
        OnboardingPageView(
            systemImage: "bluetooth",
            imageColor: .blue,
            title: "Enable Bluetooth",
            subtitle: "Bluetooth is required to connect to your watch.",
            buttonLabel: "Next",
            action: { currentPage = 3 },
            extra: { bluetoothStatusView }
        )
    }

    @ViewBuilder
    private var bluetoothStatusView: some View {
        switch bluetooth.centralState {
        case .poweredOn:
            Label("Bluetooth is on", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .poweredOff:
            VStack(spacing: 10) {
                Label("Bluetooth is off", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        case .unauthorized:
            VStack(spacing: 10) {
                Label("Bluetooth access denied", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        default:
            Label("Checking Bluetooth…", systemImage: "circle.dotted")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Page 4 — Apple Health

    private var healthPage: some View {
        let hk = bluetooth.healthKit
        let authorized = hk.authorizationStatus == .authorized
        return OnboardingPageView(
            systemImage: "heart.text.clipboard.fill",
            imageColor: .pink,
            title: "Apple Health",
            subtitle: "Allow the app to save heart rate, blood pressure, and blood oxygen to Apple Health.",
            buttonLabel: authorized ? "Next" : "Skip for Now",
            buttonStyle: authorized ? .primary : .secondary,
            action: { currentPage = 4 },
            extra: { healthAuthView }
        )
    }

    @ViewBuilder
    private var healthAuthView: some View {
        let hk = bluetooth.healthKit
        if hk.authorizationStatus == .authorized {
            Label("Apple Health connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if hk.isAvailable {
            Button {
                Task { await hk.requestAuthorization() }
            } label: {
                Label("Connect Apple Health", systemImage: "heart.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.pink)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        } else {
            Label("Apple Health not available on this device", systemImage: "exclamationmark.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    // MARK: Page 5 — Connect Watch

    private var isConnected: Bool {
        if case .connected = bluetooth.connectionState { return true }
        return false
    }

    private var connectPage: some View {
        OnboardingPageView(
            systemImage: "applewatch.radiowaves.left.and.right",
            imageColor: .blue,
            title: "Connect Your Watch",
            subtitle: "Scan for your LaxasFit Watch Ultra and tap to connect.",
            buttonLabel: isConnected ? "Next" : "Skip for Now",
            buttonStyle: isConnected ? .primary : .secondary,
            action: { currentPage = 5 },
            extra: { connectControlView }
        )
    }

    @ViewBuilder
    private var connectControlView: some View {
        if isConnected {
            Label(bluetooth.connectedDeviceName ?? "Watch connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if case .connecting = bluetooth.connectionState {
            HStack(spacing: 8) {
                ProgressView()
                Text("Connecting…").foregroundStyle(.secondary)
            }
        } else if bluetooth.isScanning {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.85)
                    Text("Scanning…").foregroundStyle(.secondary)
                }
                ForEach(bluetooth.peripherals.prefix(3)) { entry in
                    Button {
                        bluetooth.connect(to: entry)
                    } label: {
                        HStack {
                            Text(entry.name)
                            Spacer()
                            if entry.confidence > 0 {
                                Text("\(entry.confidence)%")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                Button("Stop Scanning", action: bluetooth.stopScan)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                bluetooth.startScan()
            } label: {
                Label("Scan for Watch", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.borderedProminent)
            .disabled(bluetooth.centralState != .poweredOn)
        }
    }

    // MARK: Page 6 — Finish

    private var finishPage: some View {
        OnboardingPageView(
            systemImage: "checkmark.seal.fill",
            imageColor: .green,
            title: "You're All Set!",
            subtitle: "Your LaxasFit Watch companion is ready. Sync your health data and keep an eye on your wellbeing.",
            buttonLabel: "Finish Setup",
            buttonStyle: .green,
            action: { hasCompletedOnboarding = true }
        )
    }
}

// MARK: - Reusable page template

enum OnboardingButtonStyle { case primary, secondary, green }

struct OnboardingPageView: View {
    let systemImage: String
    let imageColor: Color
    let title: String
    let subtitle: String
    let buttonLabel: String
    let buttonStyle: OnboardingButtonStyle
    let action: () -> Void
    let extra: AnyView

    // Without extra content
    init(
        systemImage: String,
        imageColor: Color = .blue,
        title: String,
        subtitle: String,
        buttonLabel: String,
        buttonStyle: OnboardingButtonStyle = .primary,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.imageColor = imageColor
        self.title = title
        self.subtitle = subtitle
        self.buttonLabel = buttonLabel
        self.buttonStyle = buttonStyle
        self.action = action
        self.extra = AnyView(EmptyView())
    }

    // With extra content
    init<V: View>(
        systemImage: String,
        imageColor: Color = .blue,
        title: String,
        subtitle: String,
        buttonLabel: String,
        buttonStyle: OnboardingButtonStyle = .primary,
        action: @escaping () -> Void,
        @ViewBuilder extra: () -> V
    ) {
        self.systemImage = systemImage
        self.imageColor = imageColor
        self.title = title
        self.subtitle = subtitle
        self.buttonLabel = buttonLabel
        self.buttonStyle = buttonStyle
        self.action = action
        self.extra = AnyView(extra())
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 72))
                .foregroundStyle(imageColor)
                .padding(.bottom, 32)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            extra
                .padding(.top, 24)
            Spacer()
            Button(action: action) {
                Text(buttonLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(buttonBackground)
                    .foregroundStyle(buttonForeground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityIdentifier("onboarding.continueButton")
            .padding(.horizontal, 32)
            .padding(.bottom, 80)
        }
    }

    private var buttonBackground: Color {
        switch buttonStyle {
        case .primary:   return .blue
        case .secondary: return Color(.systemGray5)
        case .green:     return .green
        }
    }

    private var buttonForeground: Color {
        switch buttonStyle {
        case .secondary: return .primary
        default:         return .white
        }
    }
}

#Preview("Onboarding") {
    OnboardingView()
        .environment(BluetoothManager())
}
