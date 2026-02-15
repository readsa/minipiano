//
//  PianoRollModels.swift
//  minipiano
//
//  Refactored from PianoRollView.swift on 2026/2/14.
//

import SwiftUI

// MARK: - Data model

/// A single note placed on the piano roll grid.
/// Positions and durations are stored in **ticks** (1 measure = 48 ticks).
/// 48 is the LCM of 12 and 16, so it divides evenly by all allowed
/// beatsPerMeasure values (1, 2, 3, 4, 6, 8, 12, 16).
struct RollNote: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    /// Row index (0 = lowest note)
    var row: Int
    /// Start position in ticks (48 ticks per measure)
    var startTick: Int
    /// Duration in ticks (minimum 1)
    var durationTicks: Int
    /// The timbre/instrument for this note
    var timbre: Timbre

    init(row: Int, startTick: Int, durationTicks: Int = 12, timbre: Timbre = .sine) {
        self.id = UUID()
        self.row = row
        self.startTick = startTick
        self.durationTicks = max(1, durationTicks)
        self.timbre = timbre
    }

    // Coding keys include both old (column/duration) and new (startTick/durationTicks)
    enum CodingKeys: String, CodingKey {
        case row, column, duration, startTick, durationTicks, timbre
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.row = try container.decode(Int.self, forKey: .row)
        self.timbre = try container.decodeIfPresent(Timbre.self, forKey: .timbre) ?? .sine

        // Try new format first, fall back to legacy column/duration
        if let st = try? container.decode(Int.self, forKey: .startTick),
           let dt = try? container.decode(Int.self, forKey: .durationTicks) {
            self.startTick = st
            self.durationTicks = max(1, dt)
        } else {
            let column = try container.decode(Int.self, forKey: .column)
            let duration = try container.decode(Int.self, forKey: .duration)
            // Legacy: column was a beat index in 4‐beat mode → 12 ticks per beat
            self.startTick = column * 12
            self.durationTicks = max(1, duration * 12)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(row, forKey: .row)
        try container.encode(startTick, forKey: .startTick)
        try container.encode(durationTicks, forKey: .durationTicks)
        try container.encode(timbre, forKey: .timbre)
    }
}

// MARK: - Project model

/// Represents a complete piano roll project, serializable to JSON.
struct PianoRollProject: Codable {
    var projectName: String
    var bpm: Double
    var measures: Int
    var beatsPerMeasure: Int
    var notes: [RollNote]

    enum CodingKeys: String, CodingKey {
        case projectName, bpm, measures, beatsPerMeasure, notes
    }

    init(projectName: String, bpm: Double, measures: Int, beatsPerMeasure: Int, notes: [RollNote]) {
        self.projectName = projectName
        self.bpm = bpm
        self.measures = measures
        self.beatsPerMeasure = beatsPerMeasure
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.projectName = try container.decode(String.self, forKey: .projectName)
        self.bpm = try container.decode(Double.self, forKey: .bpm)
        self.measures = try container.decode(Int.self, forKey: .measures)
        self.beatsPerMeasure = try container.decodeIfPresent(Int.self, forKey: .beatsPerMeasure) ?? 4
        self.notes = try container.decode([RollNote].self, forKey: .notes)
    }
}

/// Metadata for listing saved projects (without loading full note data).
struct ProjectFileInfo: Identifiable {
    let id = UUID()
    let fileName: String
    let displayName: String
    let date: Date
    let url: URL
}

// MARK: - Timbre color mapping

extension Timbre {
    /// The display color associated with each timbre type.
    var color: Color {
        switch self {
        case .sine:     return Color(red: 0.29, green: 0.56, blue: 0.85)
        case .square:   return Color(red: 0.31, green: 0.78, blue: 0.47)
        case .triangle: return Color(red: 0.61, green: 0.35, blue: 0.71)
        case .sawtooth: return Color(red: 0.90, green: 0.49, blue: 0.13)
        case .pulse:    return Color(red: 0.91, green: 0.12, blue: 0.55)
        case .noise:    return Color(red: 0.56, green: 0.56, blue: 0.58)
        case .brass:    return Color(red: 0.85, green: 0.65, blue: 0.15)
        }
    }
}

// MARK: - Shared layout constants

/// Shared layout constants for the piano roll grid.
enum PianoRollLayout {
    static let cellWidth: CGFloat = 40      // pixels per beat column
    static let cellHeight: CGFloat = 28
    static let keyLabelWidth: CGFloat = 50
}
