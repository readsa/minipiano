//
//  PianoView.swift
//  minipiano
//
//  Created on 2026/2/12.
//

import SwiftUI

// MARK: - Data model

/// Represents a single piano key within an octave.
struct PianoKey: Identifiable {
    let id: String          // e.g. "C4", "C#4"
    let noteName: String    // e.g. "C", "C#"
    let isBlack: Bool
    let frequency: Double
    /// Semitone index within the octave (0–11)
    let semitone: Int
}

// MARK: - Helpers

/// Standard note names for one octave in semitone order.
private let noteNames = ["C", "C#", "D", "D#", "E", "F",
                          "F#", "G", "G#", "A", "A#", "B"]

/// A4 = 440 Hz.  MIDI note 69 = A4.
/// Frequency for a given MIDI note number.
private func frequencyForMIDI(_ midiNote: Int) -> Double {
    440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
}

/// Build the 12 keys for one octave. `octave` follows scientific pitch
/// notation (C4 = middle C, MIDI 60).
func keysForOctave(_ octave: Int) -> [PianoKey] {
    let baseMIDI = (octave + 1) * 12  // C of given octave
    return (0..<12).map { semitone in
        let name = noteNames[semitone]
        let isBlack = name.contains("#")
        let midi = baseMIDI + semitone
        return PianoKey(id: "\(name)\(octave)",
                        noteName: name,
                        isBlack: isBlack,
                        frequency: frequencyForMIDI(midi),
                        semitone: semitone)
    }
}

// MARK: - Single octave row

/// A single octave rendered as overlapping white and black keys,
/// using a custom multi-touch gesture to support simultaneous presses.
struct OctaveRowView: View {
    let keys: [PianoKey]
    let engine: AudioSynthEngine

    /// White key indices within the semitone array:
    /// C=0, D=2, E=4, F=5, G=7, A=9, B=11
    private static let whiteIndices = [0, 2, 4, 5, 7, 9, 11]
    /// Black key positions: each is (semitone, fractional x among white keys)
    /// C#=1 between C(0) & D(1), D#=3 between D(1) & E(2),
    /// F#=6 between F(3) & G(4), G#=8 between G(4) & A(5), A#=10 between A(5) & B(6)
    private static let blackPositions: [(semitone: Int, afterWhite: Int)] = [
        (1, 0), (3, 1), (6, 3), (8, 4), (10, 5)
    ]

    var body: some View {
        GeometryReader { geo in
            let whiteKeyWidth = geo.size.width / 7
            let blackKeyWidth = whiteKeyWidth * 0.6
            let blackKeyHeight = geo.size.height * 0.6

            ZStack(alignment: .topLeading) {
                // White keys
                HStack(spacing: 0) {
                    ForEach(Self.whiteIndices, id: \.self) { semitone in
                        let key = keys[semitone]
                        WhiteKeyView(key: key, engine: engine)
                            .frame(width: whiteKeyWidth, height: geo.size.height)
                    }
                }

                // Black keys
                ForEach(Self.blackPositions, id: \.semitone) { pos in
                    let key = keys[pos.semitone]
                    let xOffset = whiteKeyWidth * CGFloat(pos.afterWhite + 1) - blackKeyWidth / 2
                    BlackKeyView(key: key, engine: engine)
                        .frame(width: blackKeyWidth, height: blackKeyHeight)
                        .offset(x: xOffset)
                }
            }
        }
    }
}

// MARK: - Individual key views with multi-touch via DragGesture

struct WhiteKeyView: View {
    let key: PianoKey
    let engine: AudioSynthEngine
    @State private var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isPressed ? Color.gray.opacity(0.5) : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black, lineWidth: 1)
            )
            .overlay(
                Text(key.noteName)
                    .font(.caption2)
                    .foregroundColor(.black)
                    .padding(.bottom, 4),
                alignment: .bottom
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            engine.noteOn(id: key.id, frequency: key.frequency)
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        engine.noteOff(id: key.id)
                    }
            )
    }
}

struct BlackKeyView: View {
    let key: PianoKey
    let engine: AudioSynthEngine
    @State private var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isPressed ? Color.gray : Color.black)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            engine.noteOn(id: key.id, frequency: key.frequency)
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        engine.noteOff(id: key.id)
                    }
            )
    }
}

// MARK: - Full 8-octave piano

struct PianoView: View {
    var onBack: () -> Void = {}
    @State private var engine = AudioSynthEngine()

    /// Octaves 1–8 (C1 ~ C8 covers a wide range).
    /// Rows are drawn bottom-to-top: octave 1 at bottom, octave 8 at top.
    private let octaves = Array(1...8)

    var body: some View {
        ZStack {
            VStack(spacing: 2) {
                ForEach(octaves.reversed(), id: \.self) { octave in
                    OctaveRowView(keys: keysForOctave(octave), engine: engine)
                }
            }
            .background(Color.black)
            .ignoresSafeArea()

            // Back button – bottom-left
            VStack {
                Spacer()
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.8))
                        .foregroundColor(.black)
                        .cornerRadius(20)
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 30)
                    Spacer()
                }
            }
        }
    }
}
