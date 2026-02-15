//
//  AudioSynthEngine.swift
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
    case brass = "铜管乐器"
    
    var displayName: String { self.rawValue }
}

// MARK: - ADSR Envelope

/// ADSR Envelope parameters in seconds
struct EnvelopeParams {
    let attackTime: Double
    let decayTime: Double
    let sustainLevel: Float      // 0.0 to 1.0
    let releaseTime: Double
    
    static let `default` = EnvelopeParams(
        attackTime: 0.008,      // 8ms attack - fast but smooth enough to prevent clicks
        decayTime: 0.03,        // 30ms decay
        sustainLevel: 0.85,     // 85% sustain level
        releaseTime: 0.08       // 80ms release for soft tail
    )
}

/// Thread-safe container for note release state
final class ReleaseState: @unchecked Sendable {
    private var _released: Bool = false
    private var _releaseFrame: Int = 0
    private let lock = NSLock()
    
    var released: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _released }
        set { lock.lock(); _released = newValue; lock.unlock() }
    }
    
    var releaseFrame: Int {
        get { lock.lock(); defer { lock.unlock() }; return _releaseFrame }
        set { lock.lock(); _releaseFrame = newValue; lock.unlock() }
    }
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
/// Features ADSR envelope to eliminate clicking and provide smooth attack/release.
final class AudioSynthEngine {

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var activeTones: [String: ToneNode] = [:]   // key = noteID
    private let lock = NSLock()
    
    var currentTimbre: Timbre = .sine {
        didSet {
            // Timbre can be changed during playback
        }
    }
    
    var envelopeParams: EnvelopeParams = .default

    private struct ToneNode {
        let sourceNode: AVAudioSourceNode
        let releaseState: ReleaseState
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
        // Check and clean up existing tone atomically
        lock.lock()
        if let existingTone = activeTones.removeValue(forKey: id) {
            // Mark as released to stop audio generation immediately
            existingTone.releaseState.released = true
            lock.unlock()
            // Disconnect and detach outside the lock to avoid blocking
            engine.disconnectNodeOutput(existingTone.sourceNode)
            engine.detach(existingTone.sourceNode)
        } else {
            lock.unlock()
        }

        let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        var phase: Double = 0.0
        let phaseIncrement = 2.0 * Double.pi * frequency / sampleRate
        let timbre = currentTimbre  // Capture current timbre
        let envelope = envelopeParams  // Capture envelope params
        let releaseState = ReleaseState()
        
        // Seed for noise
        var noisePhase: UInt32 = UInt32(frequency * 1000)
        var sampleCount: Int = 0
        var currentFrame: Int = 0

        let sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            for frame in 0..<Int(frameCount) {
                // Generate base waveform
                let baseValue = Self.generateSample(
                    phase: phase,
                    frequency: frequency,
                    sampleRate: sampleRate,
                    timbre: timbre,
                    noisePhase: &noisePhase,
                    sampleCount: sampleCount
                )
                
                // Apply ADSR envelope
                let envelopeGain = Self.calculateEnvelope(
                    frameIndex: currentFrame,
                    sampleRate: sampleRate,
                    envelope: envelope,
                    releaseState: releaseState
                )
                
                let finalValue = baseValue * envelopeGain
                
                currentFrame += 1
                sampleCount += 1
                phase += phaseIncrement
                if phase >= 2.0 * Double.pi {
                    phase -= 2.0 * Double.pi
                }
                
                for buffer in ablPointer {
                    let buf = buffer.mData!.assumingMemoryBound(to: Float.self)
                    buf[frame] = finalValue
                }
            }
            
            // Check if release phase is complete and schedule cleanup
            if releaseState.released {
                let releaseFramesPassed = currentFrame - releaseState.releaseFrame
                let releaseFramesTotal = Int(envelope.releaseTime * sampleRate)
                if releaseFramesPassed >= releaseFramesTotal {
                    // Schedule cleanup on main queue
                    DispatchQueue.main.async { [weak self] in
                        self?.cleanupReleasedNote(id: id)
                    }
                }
            }
            
            return noErr
        }

        engine.attach(sourceNode)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(sourceNode, to: mixer, format: format)

        lock.lock()
        activeTones[id] = ToneNode(sourceNode: sourceNode, releaseState: releaseState)
        lock.unlock()
    }

    /// Stop the sine wave for the given note identifier.
    func noteOff(id: String) {
        lock.lock()
        guard let tone = activeTones[id] else {
            lock.unlock()
            return
        }
        lock.unlock()
        
        // Mark as released - the audio callback will handle the release envelope
        tone.releaseState.released = true
        tone.releaseState.releaseFrame = 0  // Will be set by the callback
    }
    
    /// Clean up a note that has finished its release phase
    private func cleanupReleasedNote(id: String) {
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

        // Check and clean up existing tone atomically
        lock.lock()
        if let existingTone = activeTones.removeValue(forKey: id) {
            existingTone.releaseState.released = true
            lock.unlock()
            engine.disconnectNodeOutput(existingTone.sourceNode)
            engine.detach(existingTone.sourceNode)
        } else {
            lock.unlock()
        }

        let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        var phase: Double = 0.0
        let timbre = currentTimbre  // Capture current timbre
        let envelope = envelopeParams  // Capture envelope params
        let releaseState = ReleaseState()
        var noisePhase: UInt32 = UInt32(frequency * 1000)
        var sampleCount: Int = 0
        var currentFrame: Int = 0

        let sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let freq = holder.value

            for frame in 0..<Int(frameCount) {
                let phaseIncrement = 2.0 * Double.pi * freq / sampleRate
                
                // Generate base waveform
                let baseValue = Self.generateSample(
                    phase: phase,
                    frequency: freq,
                    sampleRate: sampleRate,
                    timbre: timbre,
                    noisePhase: &noisePhase,
                    sampleCount: sampleCount
                )
                
                // Apply ADSR envelope
                let envelopeGain = Self.calculateEnvelope(
                    frameIndex: currentFrame,
                    sampleRate: sampleRate,
                    envelope: envelope,
                    releaseState: releaseState
                )
                
                let finalValue = baseValue * envelopeGain
                
                currentFrame += 1
                sampleCount += 1
                phase += phaseIncrement
                if phase >= 2.0 * Double.pi {
                    phase -= 2.0 * Double.pi
                }

                for buffer in ablPointer {
                    let buf = buffer.mData!.assumingMemoryBound(to: Float.self)
                    buf[frame] = finalValue
                }
            }
            
            // Check if release phase is complete
            if releaseState.released {
                let releaseFramesPassed = currentFrame - releaseState.releaseFrame
                let releaseFramesTotal = Int(envelope.releaseTime * sampleRate)
                if releaseFramesPassed >= releaseFramesTotal {
                    DispatchQueue.main.async { [weak self] in
                        self?.cleanupReleasedNote(id: id)
                    }
                }
            }
            
            return noErr
        }

        engine.attach(sourceNode)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(sourceNode, to: mixer, format: format)

        lock.lock()
        activeTones[id] = ToneNode(sourceNode: sourceNode, releaseState: releaseState)
        lock.unlock()

        return holder
    }

    // MARK: - Private: Envelope calculation
    
    /// Calculate ADSR envelope gain for the current frame
    private static func calculateEnvelope(
        frameIndex: Int,
        sampleRate: Double,
        envelope: EnvelopeParams,
        releaseState: ReleaseState
    ) -> Float {
        let attackFrames = Int(envelope.attackTime * sampleRate)
        let decayFrames = Int(envelope.decayTime * sampleRate)
        let releaseFrames = Int(envelope.releaseTime * sampleRate)
        
        // Check if note is released
        if releaseState.released {
            // Set release start frame if not set yet
            if releaseState.releaseFrame == 0 {
                releaseState.releaseFrame = frameIndex
            }
            
            // Calculate release envelope
            let releaseFramesPassed = frameIndex - releaseState.releaseFrame
            if releaseFramesPassed >= releaseFrames {
                return 0.0
            }
            
            // Linear release from current level to 0
            let releaseProgress = Float(releaseFramesPassed) / Float(releaseFrames)
            
            // Calculate what the gain would have been before release
            let preReleaseGain: Float
            if frameIndex < attackFrames {
                let progress = Float(frameIndex) / Float(attackFrames)
                let minGain: Float = 0.01
                preReleaseGain = minGain + (1.0 - minGain) * progress * progress
            } else if frameIndex < attackFrames + decayFrames {
                let decayProgress = Float(frameIndex - attackFrames) / Float(decayFrames)
                preReleaseGain = 1.0 - (1.0 - envelope.sustainLevel) * decayProgress
            } else {
                preReleaseGain = envelope.sustainLevel
            }
            
            return preReleaseGain * (1.0 - releaseProgress)
        }
        
        // Attack phase: small start -> 1.0 with exponential curve for smooth onset
        if frameIndex < attackFrames {
            let progress = Float(frameIndex) / Float(attackFrames)
            // Exponential curve: starts at ~0.01, quickly rises to 1.0
            // This prevents the harsh 0->value transition that causes clicks
            let minGain: Float = 0.01
            return minGain + (1.0 - minGain) * progress * progress
        }
        
        // Decay phase: 1.0 -> sustainLevel
        if frameIndex < attackFrames + decayFrames {
            let decayProgress = Float(frameIndex - attackFrames) / Float(decayFrames)
            return 1.0 - (1.0 - envelope.sustainLevel) * decayProgress
        }
        
        // Sustain phase: constant sustainLevel
        return envelope.sustainLevel
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
            
        case .brass:
            return brassWave(phase: phase)
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
    
    /// Brass instrument wave - rich harmonic content for trombone-like sound
    /// Uses additive synthesis with carefully weighted harmonics
    private static func brassWave(phase: Double) -> Float {
        // Fundamental frequency (1st harmonic)
        let h1 = sin(phase) * 1.0
        // 2nd harmonic - adds body
        let h2 = sin(phase * 2.0) * 0.5
        // 3rd harmonic - adds brightness
        let h3 = sin(phase * 3.0) * 0.3
        // 4th harmonic - adds richness
        let h4 = sin(phase * 4.0) * 0.15
        // 5th harmonic - adds brilliance
        let h5 = sin(phase * 5.0) * 0.1
        // 6th harmonic - subtle upper harmonics
        let h6 = sin(phase * 6.0) * 0.05
        
        // Mix all harmonics with normalization
        let mixed = h1 + h2 + h3 + h4 + h5 + h6
        return Float(mixed) * 0.2  // Scale down to prevent clipping
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
