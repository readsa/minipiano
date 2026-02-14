//
//  SineWaveEngine.swift
//  minipiano
//
//  Created on 2026/2/12.
//

import AVFoundation
import Foundation

// MARK: - Timbre/音色 definition

/// 8-bit retro gaming style timbres
enum Timbre: String, CaseIterable, Codable {
    case sine = "正弦波"
    case square = "方波"
    case triangle = "三角波"
    case sawtooth = "锯齿波"
    case pulse = "脉冲波"
    case noise = "噪声"
    
    var displayName: String { self.rawValue }
}

/// Thread-safe container for a dynamically changing frequency value.
final class DynamicFrequency: @unchecked Sendable {
    private var _value: Double
    private let lock = NSLock()

    init(_ value: Double) { _value = value }

    var value: Double {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

/// A polyphonic synthesizer built on AVAudioEngine supporting multiple timbres.
/// Each active note gets its own AVAudioSourceNode that generates the selected waveform
/// at the requested frequency. Multiple notes can sound simultaneously.
final class SineWaveEngine {

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var activeTones: [String: ToneNode] = [:]   // key = noteID
    private let lock = NSLock()
    
    var currentTimbre: Timbre = .sine {
        didSet {
            // Timbre can be changed during playback
        }
    }

    private struct ToneNode {
        let sourceNode: AVAudioSourceNode
        var phase: Double
    }

    init() {
        setupAudioSession()
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode,
                       format: engine.mainMixerNode.outputFormat(forBus: 0))
        do {
            try engine.start()
        } catch {
            print("AudioEngine failed to start: \(error)")
        }
    }

    // MARK: - Public

    /// Start playing a note with the current timbre at `frequency` Hz.
    func noteOn(id: String, frequency: Double) {
        lock.lock()
        // If already playing, ignore
        if activeTones[id] != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        var phase: Double = 0.0
        let phaseIncrement = 2.0 * Double.pi * frequency / sampleRate
        let timbre = currentTimbre  // Capture current timbre
        
        // Seed for noise
        var noisePhase: UInt32 = UInt32(frequency * 1000)
        var sampleCount: Int = 0

        let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let value = Self.generateSample(phase: phase, frequency: frequency, sampleRate: sampleRate, timbre: timbre, noisePhase: &noisePhase, sampleCount: sampleCount)
                sampleCount += 1
                phase += phaseIncrement
                if phase >= 2.0 * Double.pi {
                    phase -= 2.0 * Double.pi
                }
                for buffer in ablPointer {
                    let buf = buffer.mData!.assumingMemoryBound(to: Float.self)
                    buf[frame] = value
                }
            }
            return noErr
        }

        engine.attach(sourceNode)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(sourceNode, to: mixer, format: format)

        lock.lock()
        activeTones[id] = ToneNode(sourceNode: sourceNode, phase: 0)
        lock.unlock()
    }

    /// Stop the sine wave for the given note identifier.
    func noteOff(id: String) {
        lock.lock()
        guard let tone = activeTones.removeValue(forKey: id) else {
            lock.unlock()
            return
        }
        lock.unlock()

        engine.disconnectNodeOutput(tone.sourceNode)
        engine.detach(tone.sourceNode)
    }

    /// Start a dynamic tone whose frequency can be changed in real time.
    /// Returns a DynamicFrequency holder that the caller can update.
    func startDynamicTone(id: String, frequency: Double) -> DynamicFrequency {
        let holder = DynamicFrequency(frequency)

        lock.lock()
        if activeTones[id] != nil {
            lock.unlock()
            return holder
        }
        lock.unlock()

        let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        var phase: Double = 0.0
        let timbre = currentTimbre  // Capture current timbre
        var noisePhase: UInt32 = UInt32(frequency * 1000)
        var sampleCount: Int = 0

        let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let freq = holder.value

            for frame in 0..<Int(frameCount) {
                let phaseIncrement = 2.0 * Double.pi * freq / sampleRate
                let value = Self.generateSample(phase: phase, frequency: freq, sampleRate: sampleRate, timbre: timbre, noisePhase: &noisePhase, sampleCount: sampleCount)
                sampleCount += 1

                phase += phaseIncrement
                if phase >= 2.0 * Double.pi {
                    phase -= 2.0 * Double.pi
                }

                for buffer in ablPointer {
                    let buf = buffer.mData!.assumingMemoryBound(to: Float.self)
                    buf[frame] = value
                }
            }
            return noErr
        }

        engine.attach(sourceNode)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(sourceNode, to: mixer, format: format)

        lock.lock()
        activeTones[id] = ToneNode(sourceNode: sourceNode, phase: 0)
        lock.unlock()

        return holder
    }

    // MARK: - Private: Waveform generation
    
    /// Generate a single audio sample for the given timbre
    private static func generateSample(
        phase: Double,
        frequency: Double,
        sampleRate: Double,
        timbre: Timbre,
        noisePhase: inout UInt32,
        sampleCount: Int
    ) -> Float {
        switch timbre {
        case .sine:
            return sineWave(phase: phase)
            
        case .square:
            return squareWave(phase: phase)
            
        case .triangle:
            return triangleWave(phase: phase)
            
        case .sawtooth:
            return sawtoothWave(phase: phase)
            
        case .pulse:
            return pulseWave(phase: phase, dutyCycle: 0.25)
            
        case .noise:
            return noiseWave(phase: &noisePhase, sampleRate: sampleRate, sampleCount: sampleCount)
        }
    }
    
    /// Classic sine wave
    private static func sineWave(phase: Double) -> Float {
        return Float(sin(phase)) * 0.25
    }
    
    /// Square wave - classic 8-bit sound
    private static func squareWave(phase: Double) -> Float {
        let normalized = phase / (2.0 * Double.pi)
        return (normalized < 0.5 ? 1.0 : -1.0) * 0.25
    }
    
    /// Triangle wave - warm 8-bit tone
    private static func triangleWave(phase: Double) -> Float {
        let normalized = phase / (2.0 * Double.pi)
        let value: Double
        if normalized < 0.25 {
            value = normalized * 4.0  // 0 to 1
        } else if normalized < 0.75 {
            value = 2.0 - normalized * 4.0  // 1 to -1
        } else {
            value = normalized * 4.0 - 4.0  // -1 to 0
        }
        return Float(value) * 0.25
    }
    
    /// Sawtooth wave - bright 8-bit tone
    private static func sawtoothWave(phase: Double) -> Float {
        let normalized = phase / (2.0 * Double.pi)
        let value = (normalized * 2.0) - 1.0
        return Float(value) * 0.25
    }
    
    /// Pulse wave - variable duty cycle
    private static func pulseWave(phase: Double, dutyCycle: Double) -> Float {
        let normalized = phase / (2.0 * Double.pi)
        return (normalized < dutyCycle ? 1.0 : -1.0) * 0.25
    }
    
    /// Pseudo-random noise generator with sample-and-hold for 8-bit retro effect
    private static func noiseWave(phase: inout UInt32, sampleRate: Double, sampleCount: Int) -> Float {
        // Simulate 8kHz sampling rate (typical for 80s game audio)
        let targetSampleRate = 8000.0
        let downsampleFactor = Int(sampleRate / targetSampleRate)
        
        // Update noise value only every downsampleFactor samples (sample and hold)
        if sampleCount % max(1, downsampleFactor) == 0 {
            // Linear feedback shift register noise
            let bit = (((phase >> 0) ^ (phase >> 2) ^ (phase >> 3) ^ (phase >> 5)) & 1) as UInt32
            phase = (phase >> 1) | (bit << 31)
        }
        
        // Convert LFSR state to audio sample
        let sample = Int16(bitPattern: UInt16((phase >> 16) & 0xFFFF))
        return Float(sample) / 32768.0 * 0.25
    }

    // MARK: - Private

    private func setupAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default,
                                    options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
        #endif
    }
}
