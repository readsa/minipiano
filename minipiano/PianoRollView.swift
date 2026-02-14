//
//  PianoRollView.swift
//  minipiano
//
//  Created on 2026/2/13.
//

import SwiftUI
import Combine

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

// MARK: - Piano Roll View

struct PianoRollView: View {
    var onBack: () -> Void = {}
    @State private var viewModel = PianoRollViewModel()
    @Environment(\.scenePhase) private var scenePhase

    // Grid cell sizing
    private let cellWidth: CGFloat = 40    // pixels per beat column
    private let cellHeight: CGFloat = 28
    private let keyLabelWidth: CGFloat = 50

    // Editing state
    @State private var selectedNoteID: UUID? = nil
    @State private var noteDragOffset: CGFloat = 0
    @State private var noteResizeDelta: CGFloat = 0

    /// Pixels per tick, derived from cellWidth and current ticksPerBeat
    private var pixelsPerTick: CGFloat {
        cellWidth / CGFloat(viewModel.ticksPerBeat)
    }

    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.12, blue: 0.15)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top toolbar
                toolbar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                // Note editing toolbar (shown when a note is selected)
                if let selID = selectedNoteID,
                   let note = viewModel.notes.first(where: { $0.id == selID }) {
                    noteEditingBar(note: note)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Piano roll grid
                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: true) {
                        HStack(alignment: .top, spacing: 0) {
                            pianoKeyLabels
                                .frame(width: keyLabelWidth)

                            ScrollView(.horizontal, showsIndicators: true) {
                                ZStack(alignment: .topLeading) {
                                    gridBackground
                                    notesLayer
                                    if viewModel.isPlaying {
                                        playheadView
                                    }
                                }
                                .frame(
                                    width: CGFloat(viewModel.totalBeats) * cellWidth,
                                    height: CGFloat(viewModel.totalRows) * cellHeight
                                )
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                    .defaultScrollAnchor(.bottom)
                }
            }

            // Back button – bottom-left
            VStack {
                Spacer()
                HStack {
                    Button(action: {
                        viewModel.autoSave()
                        viewModel.stop()
                        onBack()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 30)
                    Spacer()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedNoteID)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                viewModel.autoSave()
            }
        }
        .alert("确认清除", isPresented: $viewModel.showClearConfirm) {
            Button("清除所有音符", role: .destructive) { viewModel.clearAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作将删除当前所有音符，是否继续？")
        }
        .alert("未保存的更改", isPresented: $viewModel.showUnsavedAlert) {
            Button("保存并加载") { viewModel.showSaveSheet = true }
            Button("不保存，直接加载", role: .destructive) {
                viewModel.refreshSavedProjects()
                viewModel.showLoadSheet = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前工程有未保存的更改，是否先保存？")
        }
        .alert("保存成功", isPresented: $viewModel.showSaveSuccess) {
            Button("好的") {}
        } message: {
            Text("工程已保存为 \(viewModel.projectName)")
        }
        .sheet(isPresented: $viewModel.showSaveSheet) { saveProjectSheet }
        .sheet(isPresented: $viewModel.showLoadSheet) { loadProjectSheet }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Text("🎼 钢琴卷帘")
                    .font(.headline)
                    .foregroundColor(.white)

                // Timbre selector
                Menu {
                    ForEach(Timbre.allCases, id: \.self) { timbre in
                        Button {
                            viewModel.selectedTimbre = timbre
                        } label: {
                            HStack {
                                Text(timbre.displayName)
                                if viewModel.selectedTimbre == timbre {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(timbreColor(viewModel.selectedTimbre))
                            .frame(width: 10, height: 10)
                        Image(systemName: "waveform")
                        Text("画笔: \(viewModel.selectedTimbre.displayName)")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }

                // Beats per measure selector
                Menu {
                    ForEach(PianoRollViewModel.allowedBeats, id: \.self) { n in
                        Button {
                            selectedNoteID = nil
                            viewModel.setBeatsPerMeasure(n)
                        } label: {
                            HStack {
                                Text("每小节 \(n) 拍")
                                if viewModel.beatsPerMeasure == n {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "metronome.fill")
                        Text("\(viewModel.beatsPerMeasure)拍/小节")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }

                // Undo
                Button { viewModel.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.body)
                        .foregroundColor(viewModel.canUndo ? .white : .gray.opacity(0.3))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                .disabled(!viewModel.canUndo)

                // Redo
                Button { viewModel.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.body)
                        .foregroundColor(viewModel.canRedo ? .white : .gray.opacity(0.3))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                .disabled(!viewModel.canRedo)

                Divider()
                    .frame(height: 28)
                    .background(Color.white.opacity(0.2))

                // BPM control
                HStack(spacing: 6) {
                    Text("BPM")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("\(Int(viewModel.bpm))")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.orange)
                        .frame(width: 36)
                    Slider(value: $viewModel.bpm, in: 40...240, step: 1)
                        .frame(width: 100)
                        .tint(.orange)
                }

                // Play / Stop
                Button {
                    if viewModel.isPlaying { viewModel.stop() } else { viewModel.play() }
                } label: {
                    Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(viewModel.isPlaying ? .red : .green)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }

                // Clear
                Button {
                    if !viewModel.notes.isEmpty { viewModel.showClearConfirm = true }
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.gray)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }

                // Measure controls
                HStack(spacing: 4) {
                    Button { viewModel.removeMeasure() } label: {
                        Image(systemName: "minus")
                            .font(.caption.bold())
                            .foregroundColor(viewModel.measures <= 1 ? .gray.opacity(0.3) : .white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .disabled(viewModel.measures <= 1)

                    Text("\(viewModel.measures)小节")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(minWidth: 46)

                    Button { viewModel.addMeasure() } label: {
                        Image(systemName: "plus")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(6)
                    }
                }

                Divider()
                    .frame(height: 28)
                    .background(Color.white.opacity(0.2))

                // Save
                Button {
                    viewModel.saveNameInput = viewModel.projectName
                    viewModel.showSaveSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("保存")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }

                // Load
                Button {
                    if viewModel.hasUnsavedChanges && !viewModel.notes.isEmpty {
                        viewModel.showUnsavedAlert = true
                    } else {
                        viewModel.refreshSavedProjects()
                        viewModel.showLoadSheet = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("加载")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }

                if viewModel.hasUnsavedChanges {
                    Text("● 未保存")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .padding(.trailing, 12)
        }
    }

    // MARK: - Note editing toolbar

    private func noteEditingBar(note: RollNote) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Text("编辑音符")
                    .font(.caption.bold())
                    .foregroundColor(.white)

                Divider().frame(height: 20).background(Color.white.opacity(0.3))

                // Timbre options
                ForEach(Timbre.allCases, id: \.self) { timbre in
                    Button {
                        viewModel.changeNoteTimbre(noteID: note.id, to: timbre)
                    } label: {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(timbreColor(timbre))
                                .frame(width: 8, height: 8)
                            Text(timbre.displayName)
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            note.timbre == timbre
                                ? Color.white.opacity(0.25)
                                : Color.white.opacity(0.08)
                        )
                        .cornerRadius(6)
                    }
                    .foregroundColor(.white)
                }

                Divider().frame(height: 20).background(Color.white.opacity(0.3))

                // Info
                Text("起始:\(note.startTick)t  时长:\(note.durationTicks)t")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)

                // Delete
                Button {
                    let id = note.id
                    selectedNoteID = nil
                    viewModel.removeNote(noteID: id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }

                // Close editing
                Button {
                    selectedNoteID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(white: 0.18).cornerRadius(8))
        }
    }

    // MARK: - Save sheet

    private var saveProjectSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("保存工程")
                    .font(.title2.bold())
                    .padding(.top)

                VStack(alignment: .leading, spacing: 8) {
                    Text("工程名称")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("输入工程名称", text: $viewModel.saveNameInput)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 4) {
                    Text("工程信息")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack {
                        Label("\(viewModel.notes.count) 个音符", systemImage: "music.note")
                        Spacer()
                        Label("\(viewModel.measures) 小节", systemImage: "rectangle.split.3x1")
                        Spacer()
                        Label("\(viewModel.beatsPerMeasure) 拍/小节", systemImage: "metronome")
                        Spacer()
                        Label("BPM \(Int(viewModel.bpm))", systemImage: "metronome")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .padding(.horizontal)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { viewModel.showSaveSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let name = viewModel.saveNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        viewModel.saveProject(name: name.isEmpty ? "未命名工程" : name)
                        viewModel.showSaveSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Load sheet

    private var loadProjectSheet: some View {
        NavigationStack {
            Group {
                if viewModel.savedProjects.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("暂无已保存的工程")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.savedProjects) { info in
                            Button {
                                viewModel.loadProject(from: info.url)
                                viewModel.showLoadSheet = false
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(info.displayName)
                                        .font(.body.bold())
                                        .foregroundColor(.primary)
                                    Text(info.fileName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { indexSet in
                            for idx in indexSet {
                                viewModel.deleteProject(viewModel.savedProjects[idx])
                            }
                        }
                    }
                }
            }
            .navigationTitle("加载工程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { viewModel.showLoadSheet = false }
                }
            }
        }
    }

    // MARK: - Piano key labels

    private var pianoKeyLabels: some View {
        VStack(spacing: 0) {
            ForEach((0..<viewModel.totalRows).reversed(), id: \.self) { row in
                let isBlack = viewModel.isBlackKey(row: row)
                ZStack {
                    Rectangle()
                        .fill(isBlack ? Color(white: 0.2) : Color(white: 0.85))
                    Text(viewModel.noteNames[row])
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(isBlack ? .white : .black)
                }
                .frame(height: cellHeight)
            }
        }
    }

    // MARK: - Grid background

    private var gridBackground: some View {
        Canvas { context, size in
            let rows = viewModel.totalRows
            let totalBeats = viewModel.totalBeats
            let bpm = viewModel.beatsPerMeasure

            // Row backgrounds
            for row in 0..<rows {
                let displayRow = rows - 1 - row
                let isBlack = viewModel.isBlackKey(row: row)
                let rect = CGRect(
                    x: 0,
                    y: CGFloat(displayRow) * cellHeight,
                    width: size.width,
                    height: cellHeight
                )
                context.fill(
                    Path(rect),
                    with: .color(isBlack ? Color(white: 0.16) : Color(white: 0.20))
                )
            }

            // Beat & measure vertical lines
            for beat in 0...totalBeats {
                let x = CGFloat(beat) * cellWidth
                let isMeasureLine = beat % bpm == 0
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    path,
                    with: .color(isMeasureLine
                                 ? Color.white.opacity(0.35)
                                 : Color.white.opacity(0.1)),
                    lineWidth: isMeasureLine ? 1.2 : 0.5
                )
            }

            // Horizontal row lines
            for row in 0...rows {
                let y = CGFloat(row) * cellHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.08)),
                    lineWidth: 0.5
                )
            }

            // Measure numbers
            for measure in 0..<viewModel.measures {
                let x = CGFloat(measure * bpm) * cellWidth + 2
                context.draw(
                    Text("\(measure + 1)")
                        .font(.system(size: 9))
                        .foregroundColor(.gray),
                    at: CGPoint(x: x + 8, y: 6)
                )
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Notes layer

    private var notesLayer: some View {
        let ppt = pixelsPerTick
        let tpb = viewModel.ticksPerBeat

        return ZStack(alignment: .topLeading) {
            // Tap targets per beat column
            ForEach(0..<viewModel.totalRows, id: \.self) { row in
                ForEach(0..<viewModel.totalBeats, id: \.self) { beat in
                    let displayRow = viewModel.totalRows - 1 - row
                    Color.clear
                        .frame(width: cellWidth, height: cellHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedNoteID != nil {
                                selectedNoteID = nil
                                noteDragOffset = 0
                                noteResizeDelta = 0
                            } else {
                                viewModel.toggleNote(row: row, beatIndex: beat)
                            }
                        }
                        .offset(
                            x: CGFloat(beat) * cellWidth,
                            y: CGFloat(displayRow) * cellHeight
                        )
                }
            }

            // Rendered notes
            ForEach(viewModel.notes) { note in
                let isSelected = selectedNoteID == note.id
                let displayRow = viewModel.totalRows - 1 - note.row

                let baseX = CGFloat(note.startTick) * ppt
                let baseW = CGFloat(note.durationTicks) * ppt

                let effectiveOffset = isSelected ? noteDragOffset : 0
                let effectiveResizeDelta = isSelected ? noteResizeDelta : 0

                let noteW = max(4, baseW + effectiveResizeDelta - 2)
                let noteH = cellHeight - 2
                let noteX = baseX + effectiveOffset + 1 + noteW / 2
                let noteY = CGFloat(displayRow) * cellHeight + 1 + noteH / 2

                ZStack(alignment: .trailing) {
                    // Note body
                    RoundedRectangle(cornerRadius: 4)
                        .fill(timbreColor(note.timbre))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSelected ? Color.yellow : Color.white.opacity(0.4),
                                        lineWidth: isSelected ? 2 : 0.5)
                        )
                        .frame(width: noteW, height: noteH)

                    // Resize handle (visible when selected)
                    if isSelected {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: noteH)
                            .background(Color.black.opacity(0.45))
                            .cornerRadius(3)
                            .gesture(resizeDragGesture(for: note, ppt: ppt, tpb: tpb))
                    }
                }
                .frame(width: noteW, height: noteH)
                .contentShape(Rectangle())
                .gesture(isSelected
                         ? moveDragGesture(for: note, ppt: ppt, tpb: tpb)
                         : nil)
                .onTapGesture {
                    if isSelected {
                        selectedNoteID = nil
                        noteDragOffset = 0
                        noteResizeDelta = 0
                    } else {
                        // Select note (enter editing mode) instead of deleting
                        selectedNoteID = note.id
                        noteDragOffset = 0
                        noteResizeDelta = 0
                    }
                }
                .onLongPressGesture(minimumDuration: 0.4) {
                    selectedNoteID = note.id
                    noteDragOffset = 0
                    noteResizeDelta = 0
                }
                .position(x: noteX, y: noteY)
            }
        }
    }

    // MARK: - Drag gestures

    /// Drag gesture to move the selected note horizontally, snapping to beat grid
    private func moveDragGesture(for note: RollNote, ppt: CGFloat, tpb: Int) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                let rawTicks = value.translation.width / ppt
                let snappedTicks = round(rawTicks / CGFloat(tpb)) * CGFloat(tpb)
                noteDragOffset = snappedTicks * ppt
            }
            .onEnded { value in
                let rawTicks = value.translation.width / ppt
                let snappedTicks = Int(round(rawTicks / CGFloat(tpb))) * tpb
                let newStart = note.startTick + snappedTicks
                let clamped = max(0, min(newStart, viewModel.totalTicks - note.durationTicks))
                // Snap to beat grid
                let aligned = Int(round(Double(clamped) / Double(tpb))) * tpb
                viewModel.moveNote(noteID: note.id, toTick: aligned)
                noteDragOffset = 0
            }
    }

    /// Drag gesture to resize the selected note by dragging its right edge
    private func resizeDragGesture(for note: RollNote, ppt: CGFloat, tpb: Int) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let rawTicks = value.translation.width / ppt
                let snappedTicks = round(rawTicks / CGFloat(tpb)) * CGFloat(tpb)
                let proposedDur = CGFloat(note.durationTicks) + snappedTicks
                // Clamp: at least 1 beat, don't exceed grid
                let minDur = CGFloat(tpb)
                let maxDur = CGFloat(viewModel.totalTicks - note.startTick)
                let clampedDur = max(minDur, min(proposedDur, maxDur))
                noteResizeDelta = (clampedDur - CGFloat(note.durationTicks)) * ppt
            }
            .onEnded { value in
                let rawTicks = value.translation.width / ppt
                let snappedTicks = Int(round(rawTicks / CGFloat(tpb))) * tpb
                let newDur = note.durationTicks + snappedTicks
                let clamped = max(tpb, min(newDur, viewModel.totalTicks - note.startTick))
                // Snap to beat grid
                let aligned = max(tpb, Int(round(Double(clamped) / Double(tpb))) * tpb)
                viewModel.resizeNote(noteID: note.id, toDuration: aligned)
                noteResizeDelta = 0
            }
    }

    // MARK: - Playhead

    private var playheadView: some View {
        let x = CGFloat(viewModel.currentTick) * pixelsPerTick
        return Rectangle()
            .fill(Color.white.opacity(0.6))
            .frame(width: 2)
            .frame(height: CGFloat(viewModel.totalRows) * cellHeight)
            .offset(x: x)
            .allowsHitTesting(false)
            .animation(.linear(duration: 60.0 / viewModel.bpm / 48.0), value: viewModel.currentTick)
    }

    // MARK: - Helpers

    private func timbreColor(_ timbre: Timbre) -> Color {
        switch timbre {
        case .sine:     return Color(red: 0.29, green: 0.56, blue: 0.85)
        case .square:   return Color(red: 0.31, green: 0.78, blue: 0.47)
        case .triangle: return Color(red: 0.61, green: 0.35, blue: 0.71)
        case .sawtooth: return Color(red: 0.90, green: 0.49, blue: 0.13)
        case .pulse:    return Color(red: 0.91, green: 0.12, blue: 0.55)
        case .noise:    return Color(red: 0.56, green: 0.56, blue: 0.58)
        }
    }
}

#Preview {
    PianoRollView()
}
