//
//  TromboneView.swift
//  minipiano
//
//  Created on 2026/2/12.
//

import SwiftUI
import CoreMotion

struct TromboneView: View {
    var onBack: () -> Void = {}

    @State private var engine = SineWaveEngine()
    @State private var motionManager = CMMotionManager()
    @State private var isPlaying = false
    @State private var currentFrequency: Double = 200.0
    @State private var dynamicFreq: DynamicFrequency?
    @State private var pitchAngle: Double = 0.0
    @State private var isTouchingBar = false       // 是否正在触摸条条
    @State private var barTouchY: CGFloat = 0       // 触摸位置归一化 0~1 (0=低, 1=高)

    // C4 = 261.63 Hz at horizontal (pitch = 0)
    // Range: C2 ~ C6
    private let centerFreq: Double = 261.63  // C4
    private let minFreq: Double = 65.41      // C2
    private let maxFreq: Double = 1046.50    // C6
    // Tilt angle range (radians): negative = tilt down, positive = tilt up
    private let minPitch: Double = -1.0
    private let maxPitch: Double = 1.0

    var body: some View {
        ZStack {
            // Brass-coloured background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.55, green: 0.35, blue: 0.05),
                    Color(red: 0.85, green: 0.65, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("长号模拟器")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("前后倾斜手机控制音调")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))

                // Frequency display
                Text("\(Int(currentFrequency)) Hz")
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.top, 8)

                // Visual pitch indicator
                pitchIndicator
                    .frame(width: 120, height: 450)

                Spacer()

                // The single trombone button
                Circle()
                    .fill(isPlaying
                          ? Color.red.opacity(0.85)
                          : Color.white.opacity(0.9))
                    .frame(width: 160, height: 160)
                    .overlay(
                        Text(isPlaying ? "🎵" : "按住吹奏")
                            .font(.title2)
                            .foregroundColor(isPlaying ? .white : .brown)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 10)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !isPlaying { startPlaying() }
                            }
                            .onEnded { _ in
                                stopPlaying()
                            }
                    )

                Spacer().frame(height: 50)
            }
            .padding()

            // Back button – bottom-left
            VStack {
                Spacer()
                HStack {
                    Button(action: {
                        stopPlaying()
                        stopMotionUpdates()
                        onBack()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 30)
                    Spacer()
                }
            }
        }
        .onAppear  { startMotionUpdates() }
        .onDisappear {
            stopPlaying()
            stopMotionUpdates()
        }
    }

    // MARK: - Pitch indicator

    // Note frequencies for marking
    private let noteMarkers: [(name: String, freq: Double)] = [
        ("C6", 1046.50),
        ("A5", 880.00),
        ("F5", 698.46),
        ("C5", 523.25),
        ("A4", 440.00),
        ("F4", 349.23),
        ("C4", 261.63),
        ("A3", 220.00),
        ("F3", 174.61),
        ("C3", 130.81),
        ("A2", 110.00),
        ("F2", 87.31),
        ("C2", 65.41)
    ]

    /// Convert a normalized position (0=low, 1=high) to frequency using log scale
    private func frequencyForNormalized(_ t: Double) -> Double {
        let logMin = log(minFreq)
        let logMax = log(maxFreq)
        return exp(logMin + t * (logMax - logMin))
    }

    private var pitchIndicator: some View {
        GeometryReader { geo in
            // Determine indicator Y position based on mode
            let indicatorY: CGFloat = {
                if isTouchingBar {
                    return geo.size.height * (1 - barTouchY)
                } else {
                    let normalized = (pitchAngle - minPitch) / (maxPitch - minPitch)
                    let clamped = min(max(normalized, 0), 1)
                    return geo.size.height * (1 - clamped)
                }
            }()

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isTouchingBar
                          ? Color.white.opacity(0.35)
                          : Color.white.opacity(0.2))

                // Draw note markers
                ForEach(noteMarkers, id: \.name) { marker in
                    let logMin = log(minFreq)
                    let logMax = log(maxFreq)
                    let logFreq = log(marker.freq)
                    let position = (logFreq - logMin) / (logMax - logMin)
                    let yPosition = geo.size.height * (1 - position)

                    if position >= 0 && position <= 1 {
                        ZStack {
                            // Horizontal line
                            Rectangle()
                                .fill(Color.white.opacity(0.5))
                                .frame(height: 1)
                                .position(x: geo.size.width / 2, y: yPosition)

                            // Note label
                            Text(marker.name)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .position(x: geo.size.width - 20, y: yPosition)
                        }
                    }
                }

                // Current position indicator
                Circle()
                    .fill((isPlaying || isTouchingBar) ? Color.red : Color.yellow)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .position(x: geo.size.width / 2, y: indicatorY)
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
            .contentShape(Rectangle())  // 让整个区域可触摸
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let y = value.location.y
                        let normalized = min(max(1 - y / geo.size.height, 0), 1)
                        barTouchY = normalized
                        let freq = frequencyForNormalized(normalized)
                        currentFrequency = freq

                        if !isTouchingBar {
                            isTouchingBar = true
                            startBarPlaying(frequency: freq)
                        } else {
                            dynamicFreq?.value = freq
                        }
                    }
                    .onEnded { _ in
                        isTouchingBar = false
                        stopBarPlaying()
                    }
            )
        }
    }

    // MARK: - Motion

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let motion = motion else { return }
            pitchAngle = motion.attitude.pitch

            // 触摸条条时陀螺仪不控制音高
            guard !isTouchingBar else { return }

            // Logarithmic frequency mapping: horizontal (pitch=0) → C3
            // Tilt up → higher, tilt down → lower
            let clampedPitch = min(max(pitchAngle, minPitch), maxPitch)
            let logCenter = log(centerFreq)
            let freq: Double
            if clampedPitch >= 0 {
                let t = clampedPitch / maxPitch
                freq = exp(logCenter + t * (log(maxFreq) - logCenter))
            } else {
                let t = -clampedPitch / (-minPitch)
                freq = exp(logCenter - t * (logCenter - log(minFreq)))
            }
            currentFrequency = freq

            dynamicFreq?.value = freq
        }
    }

    private func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - Playback

    private func startPlaying() {
        isPlaying = true
        let holder = engine.startDynamicTone(
            id: "trombone",
            frequency: currentFrequency
        )
        dynamicFreq = holder
    }

    private func stopPlaying() {
        guard isPlaying else { return }
        isPlaying = false
        engine.noteOff(id: "trombone")
        dynamicFreq = nil
    }

    // MARK: - Bar touch playback (independent from gyro)

    private func startBarPlaying(frequency: Double) {
        let holder = engine.startDynamicTone(
            id: "tromboneBar",
            frequency: frequency
        )
        dynamicFreq = holder
    }

    private func stopBarPlaying() {
        engine.noteOff(id: "tromboneBar")
        dynamicFreq = nil
    }
}

#Preview {
    TromboneView()
}
