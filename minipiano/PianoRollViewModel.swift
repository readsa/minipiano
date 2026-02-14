//
//  PianoRollViewModel.swift
//  minipiano
//
//  Refactored from PianoRollView.swift on 2026/2/14.
//

import SwiftUI
import Combine

// MARK: - Undo / Redo snapshot

private struct EditorSnapshot {
    let notes: [RollNote]
    let measures: Int
    let bpm: Double
    let beatsPerMeasure: Int
}

// MARK: - Piano Roll ViewModel

@Observable
final class PianoRollViewModel {
    // MARK: Constants
    let totalRows = 61           // C2..C7 (5 octaves + 1)
    static let ticksPerMeasure = 48

    /// Allowed beats‐per‐measure values (divides 48 evenly)
    static let allowedBeats: [Int] = [1, 2, 3, 4, 6, 8, 12, 16]

    // MARK: Grid dimensions
    var measures = 8
    var beatsPerMeasure = 4

    var ticksPerBeat: Int { Self.ticksPerMeasure / beatsPerMeasure }
    var totalBeats: Int { measures * beatsPerMeasure }
    var totalTicks: Int { measures * Self.ticksPerMeasure }

    // MARK: Notes & playback state
    var notes: [RollNote] = []
    var bpm: Double = 120
    var isPlaying = false
    var currentTick: Int = 0

    // Audio configuration
    var selectedTimbre: Timbre = .sine

    // Project management
    var projectName: String = "未命名工程"
    var hasUnsavedChanges: Bool = false

    // Undo / Redo
    private var undoStack: [EditorSnapshot] = []
    private var redoStack: [EditorSnapshot] = []
    private let maxUndoLevels = 50
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // UI state flags
    var showClearConfirm = false
    var showSaveSheet = false
    var showLoadSheet = false
    var showUnsavedAlert = false
    var showSaveSuccess = false
    var savedProjects: [ProjectFileInfo] = []
    var saveNameInput: String = ""

    // Note names (bottom to top: C2, C#2, D2 ... B6, C7)
    let noteNames: [String] = {
        let names = ["C", "C#", "D", "D#", "E", "F",
                     "F#", "G", "G#", "A", "A#", "B"]
        var result: [String] = []
        for octave in 2...6 {
            for name in names { result.append("\(name)\(octave)") }
        }
        result.append("C7")
        return result
    }()

    /// Frequency for each row (row 0 = C2 = MIDI 36)
    let frequencies: [Double] = {
        (0..<61).map { i in
            440.0 * pow(2.0, Double(36 + i - 69) / 12.0)
        }
    }()

    /// Whether a given row is a black key
    func isBlackKey(row: Int) -> Bool {
        let semitone = row % 12
        return [1, 3, 6, 8, 10].contains(semitone)
    }

    // Audio engine
    private var engine = SineWaveEngine()
    private var playbackTimer: Timer?
    private var activeNoteIDs: Set<String> = []

    // MARK: - Init (auto-restore)

    init() {
        restoreAutoSave()
    }

    // MARK: - Beat setting

    func setBeatsPerMeasure(_ newValue: Int) {
        guard Self.allowedBeats.contains(newValue), newValue != beatsPerMeasure else { return }
        if isPlaying { stop() }
        recordSnapshot()
        beatsPerMeasure = newValue
        markDirty()
    }

    // MARK: - Note editing

    /// Add a note at the given beat index. If one already covers that position, remove it.
    func toggleNote(row: Int, beatIndex: Int) {
        let tick = beatIndex * ticksPerBeat
        if let existing = noteAt(row: row, tick: tick) {
            recordSnapshot()
            notes.removeAll { $0.id == existing.id }
            markDirty()
        } else {
            recordSnapshot()
            let dur = ticksPerBeat
            notes.append(RollNote(row: row, startTick: tick, durationTicks: dur, timbre: selectedTimbre))
            previewNote(row: row, timbre: selectedTimbre)
            markDirty()
        }
    }

    /// Change the timbre of an existing note
    func changeNoteTimbre(noteID: UUID, to timbre: Timbre) {
        recordSnapshot()
        if let idx = notes.firstIndex(where: { $0.id == noteID }) {
            notes[idx].timbre = timbre
        }
        markDirty()
    }

    /// Remove a specific note by its ID
    func removeNote(noteID: UUID) {
        recordSnapshot()
        notes.removeAll { $0.id == noteID }
        markDirty()
    }

    /// Move a note to a new startTick (clamped to valid range)
    func moveNote(noteID: UUID, toTick newStart: Int) {
        recordSnapshot()
        if let idx = notes.firstIndex(where: { $0.id == noteID }) {
            let clamped = max(0, min(newStart, totalTicks - notes[idx].durationTicks))
            notes[idx].startTick = clamped
        }
        markDirty()
    }

    /// Resize a note to a new duration in ticks (minimum = 1 tick)
    func resizeNote(noteID: UUID, toDuration newDur: Int) {
        recordSnapshot()
        if let idx = notes.firstIndex(where: { $0.id == noteID }) {
            let clamped = max(1, min(newDur, totalTicks - notes[idx].startTick))
            notes[idx].durationTicks = clamped
        }
        markDirty()
    }

    /// Play a short preview of a note when placed
    private func previewNote(row: Int, timbre: Timbre) {
        let previewID = "preview_\(UUID())"
        engine.currentTimbre = timbre
        engine.noteOn(id: previewID, frequency: frequencies[row])
        let dur = 60.0 / bpm / 48.0 * Double(ticksPerBeat)
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) { [weak self] in
            self?.engine.noteOff(id: previewID)
        }
    }

    /// Return the note covering the given tick/row, if any.
    func noteAt(row: Int, tick: Int) -> RollNote? {
        notes.first { n in
            n.row == row && tick >= n.startTick && tick < n.startTick + n.durationTicks
        }
    }

    // MARK: - Playback

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        currentTick = 0

        let interval = 60.0 / bpm / 48.0  // seconds per tick
        playbackTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        currentTick = 0
        for id in activeNoteIDs { engine.noteOff(id: id) }
        activeNoteIDs.removeAll()
    }

    private func tick() {
        if currentTick >= totalTicks {
            stop()
            return
        }

        let starting = notes.filter { $0.startTick == currentTick }
        for note in starting {
            let noteID = "roll_\(note.id)"
            engine.currentTimbre = note.timbre
            engine.noteOn(id: noteID, frequency: frequencies[note.row])
            activeNoteIDs.insert(noteID)

            let dur = 60.0 / bpm / 48.0 * Double(note.durationTicks)
            DispatchQueue.main.asyncAfter(deadline: .now() + dur) { [weak self] in
                self?.engine.noteOff(id: noteID)
                self?.activeNoteIDs.remove(noteID)
            }
        }

        currentTick += 1
    }

    /// Clear all notes
    func clearAll() {
        recordSnapshot()
        stop()
        notes.removeAll()
        markDirty()
    }

    // MARK: - Measure management

    func addMeasure() {
        if isPlaying { stop() }
        recordSnapshot()
        measures += 1
        markDirty()
    }

    func removeMeasure() {
        if isPlaying { stop() }
        guard measures > 1 else { return }
        recordSnapshot()
        measures -= 1
        let maxTick = totalTicks
        notes.removeAll { $0.startTick >= maxTick }
        for i in notes.indices {
            let end = notes[i].startTick + notes[i].durationTicks
            if end > maxTick {
                notes[i].durationTicks = max(1, maxTick - notes[i].startTick)
            }
        }
        markDirty()
    }

    // MARK: - Undo / Redo

    private func recordSnapshot() {
        let snap = EditorSnapshot(notes: notes, measures: measures, bpm: bpm, beatsPerMeasure: beatsPerMeasure)
        undoStack.append(snap)
        if undoStack.count > maxUndoLevels { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let snap = undoStack.popLast() else { return }
        redoStack.append(EditorSnapshot(notes: notes, measures: measures, bpm: bpm, beatsPerMeasure: beatsPerMeasure))
        applySnapshot(snap)
    }

    func redo() {
        guard let snap = redoStack.popLast() else { return }
        undoStack.append(EditorSnapshot(notes: notes, measures: measures, bpm: bpm, beatsPerMeasure: beatsPerMeasure))
        applySnapshot(snap)
    }

    private func applySnapshot(_ snap: EditorSnapshot) {
        if isPlaying { stop() }
        notes = snap.notes
        measures = snap.measures
        bpm = snap.bpm
        beatsPerMeasure = snap.beatsPerMeasure
        hasUnsavedChanges = true
        autoSave()
    }

    // MARK: - Dirty tracking

    private func markDirty() {
        hasUnsavedChanges = true
        autoSave()
    }

    // MARK: - Project save / load

    private static var projectsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("PianoRollProjects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var autoSaveURL: URL {
        projectsDirectory.appendingPathComponent("_autosave.json")
    }

    private func makeFileName(name: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateStr = df.string(from: Date())
        let safeName = name.replacingOccurrences(of: "/", with: "-")
                           .replacingOccurrences(of: ":", with: "-")
        return "\(dateStr)-\(safeName).json"
    }

    func saveProject(name: String) {
        let project = PianoRollProject(
            projectName: name, bpm: bpm,
            measures: measures, beatsPerMeasure: beatsPerMeasure,
            notes: notes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(project) else { return }
        let url = Self.projectsDirectory.appendingPathComponent(makeFileName(name: name))
        try? data.write(to: url)
        projectName = name
        hasUnsavedChanges = false
        showSaveSuccess = true
    }

    func loadProject(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let project = try? JSONDecoder().decode(PianoRollProject.self, from: data) else { return }
        if isPlaying { stop() }
        undoStack.removeAll()
        redoStack.removeAll()
        notes = project.notes
        measures = project.measures
        bpm = project.bpm
        beatsPerMeasure = project.beatsPerMeasure
        projectName = project.projectName
        hasUnsavedChanges = false
        autoSave()
    }

    func refreshSavedProjects() {
        let fm = FileManager.default
        let dir = Self.projectsDirectory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else {
            savedProjects = []; return
        }
        savedProjects = files
            .filter { $0.lastPathComponent != "_autosave.json" && $0.pathExtension == "json" }
            .compactMap { url -> ProjectFileInfo? in
                let name = url.deletingPathExtension().lastPathComponent
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let date = (attrs?[.creationDate] as? Date) ?? Date.distantPast
                let displayName = name.count > 20 ? String(name.dropFirst(20)) : name
                return ProjectFileInfo(fileName: url.lastPathComponent, displayName: displayName, date: date, url: url)
            }
            .sorted { $0.date > $1.date }
    }

    func deleteProject(_ info: ProjectFileInfo) {
        try? FileManager.default.removeItem(at: info.url)
        refreshSavedProjects()
    }

    // MARK: - Auto-save

    func autoSave() {
        let project = PianoRollProject(
            projectName: projectName, bpm: bpm,
            measures: measures, beatsPerMeasure: beatsPerMeasure,
            notes: notes
        )
        guard let data = try? JSONEncoder().encode(project) else { return }
        try? data.write(to: Self.autoSaveURL)
    }

    private func restoreAutoSave() {
        let url = Self.autoSaveURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let project = try? JSONDecoder().decode(PianoRollProject.self, from: data) else { return }
        notes = project.notes
        measures = project.measures
        bpm = project.bpm
        beatsPerMeasure = project.beatsPerMeasure
        projectName = project.projectName
        hasUnsavedChanges = true
    }
}
