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
struct RollNote: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    /// Row index (0 = lowest note)
    var row: Int
    /// Column index (beat position)
    var column: Int
    /// Duration in beats (minimum 1)
    var duration: Int

    init(row: Int, column: Int, duration: Int = 1) {
        self.id = UUID()
        self.row = row
        self.column = column
        self.duration = duration
    }

    // Only encode musical data (id is regenerated on decode)
    enum CodingKeys: String, CodingKey {
        case row, column, duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.row = try container.decode(Int.self, forKey: .row)
        self.column = try container.decode(Int.self, forKey: .column)
        self.duration = try container.decode(Int.self, forKey: .duration)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(row, forKey: .row)
        try container.encode(column, forKey: .column)
        try container.encode(duration, forKey: .duration)
    }
}

// MARK: - Project model

/// Represents a complete piano roll project, serializable to JSON.
struct PianoRollProject: Codable {
    var projectName: String
    var bpm: Double
    var measures: Int
    var notes: [RollNote]
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
}

// MARK: - Piano Roll ViewModel

@Observable
final class PianoRollViewModel {
    // Grid dimensions
    let totalRows = 61          // C2..C7 (5 octaves + 1)
    var measures = 8            // number of measures (4 beats each)
    var totalColumns: Int { measures * 4 }
    var notes: [RollNote] = []
    var bpm: Double = 120
    var isPlaying = false
    var currentBeat: Double = 0

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
    var showUnsavedAlert = false          // "save before load?" prompt
    var showSaveSuccess = false
    var savedProjects: [ProjectFileInfo] = []
    var saveNameInput: String = ""

    // Note names (bottom to top: C2, C#2, D2 ... B6, C7)
    let noteNames: [String] = {
        let names = ["C", "C#", "D", "D#", "E", "F",
                     "F#", "G", "G#", "A", "A#", "B"]
        var result: [String] = []
        for octave in 2...6 {
            for name in names {
                result.append("\(name)\(octave)")
            }
        }
        result.append("C7")  // top note
        return result
    }()

    /// Frequency for each row (row 0 = C2)
    let frequencies: [Double] = {
        // C2 = MIDI 36
        return (0..<61).map { i in
            let midi = 36 + i
            return 440.0 * pow(2.0, Double(midi - 69) / 12.0)
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

    // MARK: - Note editing

    /// Toggle a note at (row, column). If one exists, remove it; otherwise add one.
    func toggleNote(row: Int, column: Int) {
        recordSnapshot()
        if let idx = notes.firstIndex(where: { $0.row == row && $0.column == column }) {
            notes.remove(at: idx)
        } else {
            notes.append(RollNote(row: row, column: column, duration: 1))
            previewNote(row: row)
        }
        markDirty()
    }

    /// Play a short preview of a note when placed
    private func previewNote(row: Int) {
        let previewID = "preview_\(UUID())"
        engine.noteOn(id: previewID, frequency: frequencies[row])
        let stepDuration = 60.0 / bpm / 4.0
        DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration) { [weak self] in
            self?.engine.noteOff(id: previewID)
        }
    }

    /// Check if a cell is occupied by a note (either starting or sustained)
    func noteAt(row: Int, column: Int) -> RollNote? {
        notes.first { n in
            n.row == row && column >= n.column && column < n.column + n.duration
        }
    }

    /// Check if a cell is the start of a note
    func isNoteStart(row: Int, column: Int) -> Bool {
        notes.contains { $0.row == row && $0.column == column }
    }

    // MARK: - Playback

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        currentBeat = 0

        let interval = 60.0 / bpm / 4.0  // 16th note resolution
        playbackTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick()
        }
    }

    func stop() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        currentBeat = 0
        for id in activeNoteIDs {
            engine.noteOff(id: id)
        }
        activeNoteIDs.removeAll()
    }

    private func tick() {
        let beatIndex = Int(currentBeat)
        if beatIndex >= totalColumns {
            stop()
            return
        }

        let startingNotes = notes.filter { $0.column == beatIndex }
        for note in startingNotes {
            let noteID = "roll_\(note.id)"
            engine.noteOn(id: noteID, frequency: frequencies[note.row])
            activeNoteIDs.insert(noteID)

            let duration = 60.0 / bpm / 4.0 * Double(note.duration)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.engine.noteOff(id: noteID)
                self?.activeNoteIDs.remove(noteID)
            }
        }

        currentBeat += 1
    }

    /// Clear all notes (called after user confirmation)
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
        let maxCol = totalColumns
        notes.removeAll { $0.column >= maxCol }
        for i in notes.indices {
            let end = notes[i].column + notes[i].duration
            if end > maxCol {
                notes[i].duration = max(1, maxCol - notes[i].column)
            }
        }
        markDirty()
    }

    // MARK: - Undo / Redo

    private func recordSnapshot() {
        let snap = EditorSnapshot(notes: notes, measures: measures, bpm: bpm)
        undoStack.append(snap)
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func undo() {
        guard let snap = undoStack.popLast() else { return }
        // Save current state to redo
        redoStack.append(EditorSnapshot(notes: notes, measures: measures, bpm: bpm))
        applySnapshot(snap)
    }

    func redo() {
        guard let snap = redoStack.popLast() else { return }
        undoStack.append(EditorSnapshot(notes: notes, measures: measures, bpm: bpm))
        applySnapshot(snap)
    }

    private func applySnapshot(_ snap: EditorSnapshot) {
        if isPlaying { stop() }
        notes = snap.notes
        measures = snap.measures
        bpm = snap.bpm
        hasUnsavedChanges = true
        autoSave()
    }

    // MARK: - Dirty tracking

    private func markDirty() {
        hasUnsavedChanges = true
        autoSave()
    }

    // MARK: - Project save / load

    /// Directory for saved projects
    private static var projectsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("PianoRollProjects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Auto-save file path
    private static var autoSaveURL: URL {
        projectsDirectory.appendingPathComponent("_autosave.json")
    }

    /// Build a filename from date + project name
    private func makeFileName(name: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateStr = df.string(from: Date())
        let safeName = name.replacingOccurrences(of: "/", with: "-")
                           .replacingOccurrences(of: ":", with: "-")
        return "\(dateStr)-\(safeName).json"
    }

    /// Save current project to a named file
    func saveProject(name: String) {
        let project = PianoRollProject(
            projectName: name,
            bpm: bpm,
            measures: measures,
            notes: notes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(project) else { return }

        let fileName = makeFileName(name: name)
        let url = Self.projectsDirectory.appendingPathComponent(fileName)
        try? data.write(to: url)

        projectName = name
        hasUnsavedChanges = false
        showSaveSuccess = true
    }

    /// Load project from a file URL
    func loadProject(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let project = try? JSONDecoder().decode(PianoRollProject.self, from: data) else { return }
        if isPlaying { stop() }

        // Reset undo/redo for the new project
        undoStack.removeAll()
        redoStack.removeAll()

        notes = project.notes
        measures = project.measures
        bpm = project.bpm
        projectName = project.projectName
        hasUnsavedChanges = false
        autoSave()
    }

    /// List all saved project files, sorted by date descending
    func refreshSavedProjects() {
        let fm = FileManager.default
        let dir = Self.projectsDirectory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else {
            savedProjects = []
            return
        }
        savedProjects = files
            .filter { $0.lastPathComponent != "_autosave.json" && $0.pathExtension == "json" }
            .compactMap { url -> ProjectFileInfo? in
                let name = url.deletingPathExtension().lastPathComponent
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let date = (attrs?[.creationDate] as? Date) ?? Date.distantPast
                // Extract display name: strip the date prefix (20 chars: yyyy-MM-dd-HH-mm-ss-)
                let displayName: String
                if name.count > 20 {
                    displayName = String(name.dropFirst(20))
                } else {
                    displayName = name
                }
                return ProjectFileInfo(fileName: url.lastPathComponent, displayName: displayName, date: date, url: url)
            }
            .sorted { $0.date > $1.date }
    }

    /// Delete a saved project file
    func deleteProject(_ info: ProjectFileInfo) {
        try? FileManager.default.removeItem(at: info.url)
        refreshSavedProjects()
    }

    // MARK: - Auto-save (temp persistence)

    /// Save current state to the auto-save file
    func autoSave() {
        let project = PianoRollProject(
            projectName: projectName,
            bpm: bpm,
            measures: measures,
            notes: notes
        )
        guard let data = try? JSONEncoder().encode(project) else { return }
        try? data.write(to: Self.autoSaveURL)
    }

    /// Restore from the auto-save file on launch
    private func restoreAutoSave() {
        let url = Self.autoSaveURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let project = try? JSONDecoder().decode(PianoRollProject.self, from: data) else { return }
        notes = project.notes
        measures = project.measures
        bpm = project.bpm
        projectName = project.projectName
        // Restored from auto-save means there may be unsaved work
        hasUnsavedChanges = true
    }
}

// MARK: - Piano Roll View

struct PianoRollView: View {
    var onBack: () -> Void = {}
    @State private var viewModel = PianoRollViewModel()
    @Environment(\.scenePhase) private var scenePhase

    // Grid cell size
    private let cellWidth: CGFloat = 40
    private let cellHeight: CGFloat = 28
    private let keyLabelWidth: CGFloat = 50

    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.12, blue: 0.15)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top toolbar
                toolbar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

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
                                    width: CGFloat(viewModel.totalColumns) * cellWidth,
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
        // Auto-save when app goes to background
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                viewModel.autoSave()
            }
        }
        // Clear all confirmation
        .alert("确认清除", isPresented: $viewModel.showClearConfirm) {
            Button("清除所有音符", role: .destructive) {
                viewModel.clearAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作将删除当前所有音符，是否继续？")
        }
        // Unsaved changes alert (shown before loading)
        .alert("未保存的更改", isPresented: $viewModel.showUnsavedAlert) {
            Button("保存并加载") {
                viewModel.showSaveSheet = true
            }
            Button("不保存，直接加载", role: .destructive) {
                viewModel.refreshSavedProjects()
                viewModel.showLoadSheet = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前工程有未保存的更改，是否先保存？")
        }
        // Save success toast
        .alert("保存成功", isPresented: $viewModel.showSaveSuccess) {
            Button("好的") {}
        } message: {
            Text("工程已保存为 \(viewModel.projectName)")
        }
        // Save sheet
        .sheet(isPresented: $viewModel.showSaveSheet) {
            saveProjectSheet
        }
        // Load sheet
        .sheet(isPresented: $viewModel.showLoadSheet) {
            loadProjectSheet
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Text("🎼 钢琴卷帘")
                    .font(.headline)
                    .foregroundColor(.white)

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
                    if viewModel.isPlaying {
                        viewModel.stop()
                    } else {
                        viewModel.play()
                    }
                } label: {
                    Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(viewModel.isPlaying ? .red : .green)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }

                // Clear (with confirmation)
                Button {
                    if viewModel.notes.isEmpty {
                        return  // nothing to clear
                    }
                    viewModel.showClearConfirm = true
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
                    Button {
                        viewModel.removeMeasure()
                    } label: {
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

                    Button {
                        viewModel.addMeasure()
                    } label: {
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

                // Project name indicator
                if viewModel.hasUnsavedChanges {
                    Text("● 未保存")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .padding(.trailing, 12)
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
            let cols = viewModel.totalColumns

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
                    with: .color(isBlack
                                 ? Color(white: 0.16)
                                 : Color(white: 0.20))
                )
            }

            for col in 0...cols {
                let x = CGFloat(col) * cellWidth
                let isBeat = col % 4 == 0
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    path,
                    with: .color(isBeat
                                 ? Color.white.opacity(0.3)
                                 : Color.white.opacity(0.1)),
                    lineWidth: isBeat ? 1.0 : 0.5
                )
            }

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

            for col in stride(from: 0, to: cols, by: 4) {
                let x = CGFloat(col) * cellWidth + 2
                context.draw(
                    Text("\(col / 4 + 1)")
                        .font(.system(size: 9))
                        .foregroundColor(.gray),
                    at: CGPoint(x: x + 8, y: 6)
                )
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Notes layer (tappable)

    private var notesLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<viewModel.totalRows, id: \.self) { row in
                ForEach(0..<viewModel.totalColumns, id: \.self) { col in
                    let displayRow = viewModel.totalRows - 1 - row
                    Color.clear
                        .frame(width: cellWidth, height: cellHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.toggleNote(row: row, column: col)
                        }
                        .offset(
                            x: CGFloat(col) * cellWidth,
                            y: CGFloat(displayRow) * cellHeight
                        )
                }
            }

            ForEach(viewModel.notes) { note in
                let displayRow = viewModel.totalRows - 1 - note.row
                RoundedRectangle(cornerRadius: 4)
                    .fill(noteColor(row: note.row))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                    )
                    .frame(
                        width: CGFloat(note.duration) * cellWidth - 2,
                        height: cellHeight - 2
                    )
                    .offset(
                        x: CGFloat(note.column) * cellWidth + 1,
                        y: CGFloat(displayRow) * cellHeight + 1
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Playhead

    private var playheadView: some View {
        let x = CGFloat(viewModel.currentBeat) * cellWidth
        return Rectangle()
            .fill(Color.white.opacity(0.6))
            .frame(width: 2)
            .frame(height: CGFloat(viewModel.totalRows) * cellHeight)
            .offset(x: x)
            .allowsHitTesting(false)
            .animation(.linear(duration: 60.0 / viewModel.bpm / 4.0), value: viewModel.currentBeat)
    }

    // MARK: - Helpers

    private func noteColor(row: Int) -> Color {
        let hue = Double(row % 12) / 12.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.85)
    }
}

#Preview {
    PianoRollView()
}
