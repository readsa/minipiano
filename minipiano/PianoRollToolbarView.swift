//
//  PianoRollToolbarView.swift
//  minipiano
//
//  Refactored from PianoRollView.swift on 2026/2/14.
//

import SwiftUI

/// The top toolbar for the piano roll, containing timbre selection,
/// beats‐per‐measure, undo/redo, BPM, playback, measures, and save/load controls.
struct PianoRollToolbarView: View {
    var viewModel: PianoRollViewModel
    @Binding var selectedNoteID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                titleLabel
                timbreMenu
                beatsPerMeasureMenu
                undoRedoButtons
                divider
                bpmControl
                playStopButton
                clearButton
                measureControls
                divider
                saveButton
                loadButton
                unsavedIndicator
            }
            .padding(.trailing, 12)
        }
    }

    // MARK: - Title

    private var titleLabel: some View {
        Text("🎼 钢琴卷帘")
            .font(.headline)
            .foregroundColor(.white)
    }

    // MARK: - Timbre selector

    private var timbreMenu: some View {
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
                    .fill(viewModel.selectedTimbre.color)
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
    }

    // MARK: - Beats per measure

    private var beatsPerMeasureMenu: some View {
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
    }

    // MARK: - Undo / Redo

    private var undoRedoButtons: some View {
        HStack(spacing: 12) {
            Button { viewModel.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.body)
                    .foregroundColor(viewModel.canUndo ? .white : .gray.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }
            .disabled(!viewModel.canUndo)

            Button { viewModel.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.body)
                    .foregroundColor(viewModel.canRedo ? .white : .gray.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }
            .disabled(!viewModel.canRedo)
        }
    }

    // MARK: - BPM

    private var bpmControl: some View {
        HStack(spacing: 6) {
            Text("BPM")
                .font(.caption)
                .foregroundColor(.gray)
            Text("\(Int(viewModel.bpm))")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.orange)
                .frame(width: 36)
            Slider(value: Bindable(viewModel).bpm, in: 40...240, step: 1)
                .frame(width: 100)
                .tint(.orange)
        }
    }

    // MARK: - Play / Stop

    private var playStopButton: some View {
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
    }

    // MARK: - Clear

    private var clearButton: some View {
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
    }

    // MARK: - Measures

    private var measureControls: some View {
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
    }

    // MARK: - Save / Load

    private var saveButton: some View {
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
    }

    private var loadButton: some View {
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
    }

    // MARK: - Unsaved indicator

    @ViewBuilder
    private var unsavedIndicator: some View {
        if viewModel.hasUnsavedChanges {
            Text("● 未保存")
                .font(.caption2)
                .foregroundColor(.orange)
        }
    }

    // MARK: - Reusable divider

    private var divider: some View {
        Divider()
            .frame(height: 28)
            .background(Color.white.opacity(0.2))
    }
}
