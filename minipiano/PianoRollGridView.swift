//
//  PianoRollGridView.swift
//  minipiano
//
//  Refactored from PianoRollView.swift on 2026/2/14.
//

import SwiftUI

/// The main piano roll grid area: key labels on the left, scrollable grid with
/// note blocks and playhead on the right.
struct PianoRollGridView: View {
    var viewModel: PianoRollViewModel
    @Binding var selectedNoteID: UUID?
    var bottomInset: CGFloat = 0

    private let cellWidth  = PianoRollLayout.cellWidth
    private let cellHeight = PianoRollLayout.cellHeight
    private let keyLabelWidth = PianoRollLayout.keyLabelWidth
    private let measureHeaderHeight: CGFloat = 28

    /// Pixels per tick, derived from cellWidth and current ticksPerBeat
    private var pixelsPerTick: CGFloat {
        cellWidth / CGFloat(viewModel.ticksPerBeat)
    }

    private let progressBarHeight: CGFloat = 24

    var body: some View {
        let gridWidth = CGFloat(viewModel.totalBeats) * cellWidth
        let gridHeight = CGFloat(viewModel.totalRows) * cellHeight

        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                // Left column: empty space for progress bar + key labels
                VStack(spacing: 0) {
                    Color.clear.frame(height: measureHeaderHeight + progressBarHeight)
                    pianoKeyLabels
                }
                .frame(width: keyLabelWidth)

                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: measureHeaderHeight + progressBarHeight)

                        ZStack(alignment: .topLeading) {
                            gridBackground
                            notesLayer
                            playheadView
                        }
                        .frame(width: gridWidth, height: gridHeight)
                    }
                    .padding(.trailing, cellWidth)
                    .padding(.bottom, bottomInset)
                    .overlay(alignment: .topLeading) {
                        GeometryReader { geo in
                            let offset = geo.frame(in: .named("pianoRollVScroll")).minY
                            VStack(spacing: 0) {
                                measureHeaderBar(width: gridWidth + cellWidth)
                                playbackProgressBar(width: gridWidth + cellWidth)
                            }
                            .offset(y: max(0, -offset))
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: "pianoRollVScroll")
        .scrollIndicators(.visible)
        .defaultScrollAnchor(.bottom)
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

        }
        .allowsHitTesting(false)
    }

    // MARK: - Measure header bar

    /// Sticky header showing measure numbers, scrolls horizontally with grid.
    private func measureHeaderBar(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Background
            Rectangle()
                .fill(Color(red: 0.14, green: 0.14, blue: 0.17))

            // Bottom border
            VStack { Spacer(); Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1) }

            // Measure numbers & dividers
            let bpm = viewModel.beatsPerMeasure
            let measureWidth = CGFloat(bpm) * cellWidth
            ForEach(0..<viewModel.measures, id: \.self) { measure in
                let x = CGFloat(measure) * measureWidth
                // Divider line
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 1)
                    .offset(x: x)
                // Measure number label
                Text("\(measure + 1)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.7))
                    .offset(x: x + 6, y: 5)
            }
        }
        .frame(width: width, height: measureHeaderHeight)
        .clipped()
    }

    // MARK: - Notes layer

    private var notesLayer: some View {
        PianoRollNotesLayerView(
            viewModel: viewModel,
            selectedNoteID: $selectedNoteID,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            pixelsPerTick: pixelsPerTick
        )
    }

    // MARK: - Playhead

    private var playheadView: some View {
        TimelineView(.animation) { timeline in
            let smoothTick: CGFloat = smoothTickValue(at: timeline.date)
            let x = smoothTick * pixelsPerTick
            Rectangle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 2)
                .frame(height: CGFloat(viewModel.totalRows) * cellHeight)
                .offset(x: x)
                .allowsHitTesting(false)
        }
    }

    /// Shared smooth tick computation for playhead and progress bar.
    private func smoothTickValue(at date: Date) -> CGFloat {
        guard viewModel.isPlaying, let start = viewModel.playbackStartDate else {
            return CGFloat(viewModel.playheadTick)
        }
        let elapsed = date.timeIntervalSince(start)
        let ticksPerSecond = viewModel.bpm / 60.0 * 48.0
        let tick = CGFloat(viewModel.playbackStartTick) + CGFloat(elapsed * ticksPerSecond)
        if viewModel.isLooping {
            let t = tick.truncatingRemainder(dividingBy: CGFloat(viewModel.totalTicks))
            return t >= 0 ? t : t + CGFloat(viewModel.totalTicks)
        }
        return min(tick, CGFloat(viewModel.totalTicks))
    }

    // MARK: - Playback progress bar

    /// A tappable progress bar showing the current playhead position, aligned with the grid.
    private func playbackProgressBar(width: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let smoothTick = smoothTickValue(at: timeline.date)

            let totalTicks = CGFloat(viewModel.totalTicks)
            let gridWidth = width - cellWidth  // exclude trailing padding
            let progress = totalTicks > 0 ? smoothTick / totalTicks : 0
            let playheadX = progress * gridWidth

            ZStack(alignment: .leading) {
                // Track background
                Rectangle()
                    .fill(Color(white: 0.12))

                // Filled portion
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.6), Color.green.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, playheadX))

                // Playhead indicator
                Capsule()
                    .fill(.white)
                    .frame(width: 4, height: progressBarHeight - 6)
                    .offset(x: max(0, playheadX - 2))

                // Beat grid lines
                Canvas { context, size in
                    let bpm = viewModel.beatsPerMeasure
                    let totalBeats = viewModel.totalBeats
                    for beat in 0...totalBeats {
                        let x = CGFloat(beat) * cellWidth
                        let isMeasureLine = beat % bpm == 0
                        guard isMeasureLine else { continue }
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(
                            path,
                            with: .color(.white.opacity(0.2)),
                            lineWidth: 0.5
                        )
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(width: width, height: progressBarHeight)
            .contentShape(Rectangle())
            .onTapGesture { location in
                let tappedX = location.x
                let fraction = max(0, min(tappedX / gridWidth, 1.0))
                let tick = Int(fraction * totalTicks)
                // Snap to nearest beat
                let tpb = viewModel.ticksPerBeat
                let snapped = Int(round(Double(tick) / Double(tpb))) * tpb
                viewModel.seek(toTick: min(snapped, viewModel.totalTicks))
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let fraction = max(0, min(value.location.x / gridWidth, 1.0))
                        let tick = Int(fraction * totalTicks)
                        let tpb = viewModel.ticksPerBeat
                        let snapped = Int(round(Double(tick) / Double(tpb))) * tpb
                        viewModel.seek(toTick: min(snapped, viewModel.totalTicks))
                    }
            )
        }
    }
}

// MARK: - Notes layer view

/// Renders all note blocks on the grid and handles tap, drag, and resize gestures.
struct PianoRollNotesLayerView: View {
    var viewModel: PianoRollViewModel
    @Binding var selectedNoteID: UUID?

    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let pixelsPerTick: CGFloat

    @State private var noteDragOffset: CGFloat = 0
    @State private var noteResizeDelta: CGFloat = 0

    var body: some View {
        let tpb = viewModel.ticksPerBeat

        ZStack(alignment: .topLeading) {
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

                let baseX = CGFloat(note.startTick) * pixelsPerTick
                let baseW = CGFloat(note.durationTicks) * pixelsPerTick

                let effectiveOffset = isSelected ? noteDragOffset : 0
                let effectiveResizeDelta = isSelected ? noteResizeDelta : 0

                let noteW = max(4, baseW + effectiveResizeDelta - 2)
                let noteH = cellHeight - 2
                let bodyCenterX = baseX + effectiveOffset + 1 + noteW / 2
                let noteY = CGFloat(displayRow) * cellHeight + 1 + noteH / 2

                // Note body
                RoundedRectangle(cornerRadius: 4)
                    .fill(note.timbre.color)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelected ? Color.yellow : Color.white.opacity(0.4),
                                    lineWidth: isSelected ? 2 : 0.5)
                    )
                    .frame(width: noteW, height: noteH)
                    .contentShape(Rectangle())
                    .gesture(isSelected
                             ? moveDragGesture(for: note, ppt: pixelsPerTick, tpb: tpb)
                             : nil)
                    .onTapGesture {
                        if isSelected {
                            selectedNoteID = nil
                            noteDragOffset = 0
                            noteResizeDelta = 0
                        } else {
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
                    .position(x: bodyCenterX, y: noteY)

                // Resize handle
                if isSelected {
                    let handleWidth: CGFloat = 22
                    let handleX = baseX + effectiveOffset + 1 + noteW + handleWidth / 2
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: handleWidth, height: noteH)
                        .background(Color.orange.opacity(0.7))
                        .cornerRadius(3)
                        .contentShape(Rectangle())
                        .gesture(resizeDragGesture(for: note, ppt: pixelsPerTick, tpb: tpb))
                        .position(x: handleX, y: noteY)
                }
            }
        }
    }

    // MARK: - Drag gestures

    /// Drag gesture to move the selected note horizontally, snapping to beat grid
    private func moveDragGesture(for note: RollNote, ppt: CGFloat, tpb: Int) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
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
                let aligned = Int(round(Double(clamped) / Double(tpb))) * tpb
                viewModel.moveNote(noteID: note.id, toTick: aligned)
                noteDragOffset = 0
            }
    }

    /// Drag gesture to resize the selected note by dragging its right edge
    private func resizeDragGesture(for note: RollNote, ppt: CGFloat, tpb: Int) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                let rawTicks = value.translation.width / ppt
                let snappedTicks = round(rawTicks / CGFloat(tpb)) * CGFloat(tpb)
                let proposedDur = CGFloat(note.durationTicks) + snappedTicks
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
                let aligned = max(tpb, Int(round(Double(clamped) / Double(tpb))) * tpb)
                viewModel.resizeNote(noteID: note.id, toDuration: aligned)
                noteResizeDelta = 0
            }
    }
}
