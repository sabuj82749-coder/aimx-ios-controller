import SwiftUI

/// SwiftUI port of Android `NativeConnectPcScreen` (MainActivity.kt:1212).
struct ConnectScreenView: View {
    @ObservedObject var viewModel: MainViewModel

    private let accent = Color(red: 0.357, green: 0.431, blue: 0.961)      // #5B6EF5
    private let accentDim = Color(red: 0.545, green: 0.608, blue: 0.969)   // #8B9BF7
    private let accentViolet = Color(red: 0.486, green: 0.361, blue: 0.906) // #7C5CE7
    private let glassSurface = Color.white.opacity(0.95)
    private let hairline = Color.black.opacity(0.10)
    private let textDim = Color(red: 0.42, green: 0.44, blue: 0.58)        // #6B7094
    private let textStrong = Color(red: 0.07, green: 0.08, blue: 0.12)     // #12151F
    private let accentRed = Color(red: 0.906, green: 0.298, blue: 0.298)   // #E74C4C

    @State private var pulse = false

    private var isActive: Bool {
        viewModel.isScanning || viewModel.connectionState == .connecting
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.914, green: 0.929, blue: 0.969),   // #E9EDF7
                    Color(red: 0.941, green: 0.953, blue: 0.976),   // #F0F3F9
                    Color(red: 0.957, green: 0.941, blue: 0.980)    // #F4F0FA
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(accent.opacity(isActive ? 0.9 : 0.4))
                            .frame(width: 7, height: 7)
                        Text("AIM-X")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(3)
                            .foregroundColor(textStrong)
                    }
                    Text("v1.0 • AIM-X SECURE BRIDGE")
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(accentDim)
                }
                .padding(.top, 24)
                .padding(.bottom, 16)

                Spacer()

                // Central radar
                ZStack {
                    if isActive {
                        Circle()
                            .stroke(accent.opacity(0.18), lineWidth: 1)
                            .frame(width: 260, height: 260)
                            .scaleEffect(pulse ? 1.0 : 0.8)
                            .opacity(pulse ? 0.0 : 0.6)
                            .animation(.easeOut(duration: 2).repeatForever(autoreverses: false), value: pulse)

                        Circle()
                            .stroke(accent.opacity(0.10), lineWidth: 0.5)
                            .frame(width: 364, height: 364)
                            .scaleEffect(pulse ? 1.0 : 0.8)
                            .opacity(pulse ? 0.0 : 0.4)
                            .animation(.easeOut(duration: 2).repeatForever(autoreverses: false).delay(0.2), value: pulse)

                        RadarSweep(color: accent)
                            .frame(width: 260, height: 260)
                            .clipShape(Circle())
                    }

                    Circle()
                        .stroke(accent.opacity(0.15), lineWidth: 1)
                        .frame(width: 286, height: 286)
                    Circle()
                        .stroke(accent.opacity(0.08), lineWidth: 0.5)
                        .frame(width: 195, height: 195)

                    // Center glass box
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            isActive
                                ? LinearGradient(colors: [accent, accentViolet], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    isActive ? accent.opacity(0.8) : accent.opacity(0.25),
                                    lineWidth: 1
                                )
                        )
                        .frame(width: 90, height: 90)
                        .contentShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            Group {
                                if isActive {
                                    HStack(spacing: 5) {
                                        Dot(color: .white, delay: 0)
                                        Dot(color: .white, delay: 0.15)
                                        Dot(color: .white, delay: 0.30)
                                    }
                                } else {
                                    Text("⚡")
                                        .font(.system(size: 28))
                                        .foregroundColor(accent.opacity(0.5))
                                }
                            }
                        )
                        .onTapGesture {
                            if !isActive { viewModel.runLanDiscovery() }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    pulse = true
                }

                Spacer()

                // Status card
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, accent.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                            .frame(height: 1)
                        Text(isActive ? "SCANNING..." : "OFFLINE")
                            .font(.system(size: 11, design: .monospaced))
                            .fontWeight(.bold)
                            .tracking(2)
                            .foregroundColor(isActive ? accent : accent.opacity(0.5))
                        Rectangle()
                            .fill(LinearGradient(colors: [accent.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(height: 1)
                    }

                    if viewModel.discoveredPCs.isEmpty {
                        diagnosticsCard
                    } else {
                        foundDevicesCard
                    }

                    if !isActive {
                        Button(action: { viewModel.runLanDiscovery() }) {
                            Text("RETRY SCAN")
                                .font(.system(size: 12, design: .monospaced))
                                .fontWeight(.bold)
                                .tracking(2)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(
                                    LinearGradient(colors: [accent, accentViolet], startPoint: .leading, endPoint: .trailing)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        viewModel.cancelScanning()
                        #if canImport(UIKit)
                        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                        #endif
                    }) {
                        Text("EXIT")
                            .font(.system(size: 11, design: .monospaced))
                            .fontWeight(.bold)
                            .tracking(2)
                            .foregroundColor(textDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            viewModel.autoConnect()
        }
        .onChange(of: viewModel.discoveredPCs) { discovered in
            if !discovered.isEmpty && viewModel.connectionState == .disconnected {
                viewModel.setPcIp(discovered[0])
                viewModel.toggleConnection()
            }
        }
    }

    private var diagnosticsCard: some View {
        VStack(spacing: 10) {
            HStack {
                Circle()
                    .fill(isActive ? accent.opacity(0.9) : accent.opacity(0.25))
                    .frame(width: 6, height: 6)
                Text("CONNECTION DIAGNOSTICS")
                    .font(.system(size: 10, design: .monospaced))
                    .fontWeight(.bold)
                    .tracking(1.5)
                    .foregroundColor(textStrong.opacity(0.9))
                Spacer()
            }
            Divider().background(hairline)
            HStack {
                Text("CHEAT STATUS")
                    .foregroundColor(textDim)
                Spacer()
                Text(isActive ? "SCANNING" : "NOT RUNNING")
                    .foregroundColor(isActive ? accent : accentRed)
            }
            .font(.system(size: 10, design: .monospaced))
            Divider().background(hairline)
            Text(isActive
                 ? "Scanning network..."
                 : "Make sure both devices are on the same Wi-Fi.")
                .font(.system(size: 10))
                .foregroundColor(textDim)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(glassSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.2), lineWidth: 1))
    }

    private var foundDevicesCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("CHEAT DETECTED")
                    .font(.system(size: 10, design: .monospaced))
                    .fontWeight(.bold)
                    .tracking(1.5)
                    .foregroundColor(accent)
                Spacer()
            }
            Divider().background(hairline)
            ForEach(Array(viewModel.discoveredPCs.enumerated()), id: \.offset) { index, ip in
                Button(action: {
                    viewModel.setPcIp(ip)
                    viewModel.toggleConnection()
                }) {
                    HStack {
                        Text("PC \(index + 1)")
                            .font(.system(size: 12, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(textStrong)
                        Spacer()
                        Text(ip)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(accent.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(accent.opacity(0.25), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(glassSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.2), lineWidth: 1))
    }
}

private struct Dot: View {
    let color: Color
    let delay: Double
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color.opacity(dim ? 0.2 : 1.0))
            .frame(width: 6, height: 6)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay)) {
                    dim.toggle()
                }
            }
    }
}

private struct RadarSweep: View {
    let color: Color
    @State private var angle: Double = 0

    var body: some View {
        GeometryReader { geometry in
            AngularGradient(
                gradient: Gradient(colors: [.clear, color.opacity(0.05), color.opacity(0.30), .clear]),
                center: .center,
                startAngle: .degrees(angle),
                endAngle: .degrees(angle + 90)
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .allowsHitTesting(false)
        }
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                angle = 360
            }
        }
    }
}