//
//  SineWaveEngine.swift
//  minipiano
//
//  Created on 2026/2/12.
//

import AVFoundation
import Foundation

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

/// A polyphonic sine-wave synthesizer built on AVAudioEngine.
/// Each active note gets its own AVAudioSourceNode that generates a sine wave
/// at the requested frequency. Multiple notes can sound simultaneously.
final class SineWaveEngine {

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var activeTones: [String: ToneNode] = [:]   // key = noteID
    private let lock = NSLock()

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

    /// Start playing a sine wave for the given note identifier at `frequency` Hz.
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

        let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let value = Float(sin(phase)) * 0.25   // amplitude
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

        let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let freq = holder.value

            for frame in 0..<Int(frameCount) {
                let phaseIncrement = 2.0 * Double.pi * freq / sampleRate

                // Brass-like waveform with harmonics
                let h1 = sin(phase) * 0.25
                let h2 = sin(phase * 2) * 0.15
                let h3 = sin(phase * 3) * 0.10
                let h4 = sin(phase * 4) * 0.05
                let h5 = sin(phase * 5) * 0.02
                let value = Float(h1 + h2 + h3 + h4 + h5)

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
