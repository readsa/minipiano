//
//  PianoRollNoteEditingBar.swift
//  minipiano
//
//  Refactored from PianoRollView.swift on 2026/2/14.
//  Redesigned as a floating bottom inspector card on 2026/2/14.
//

import SwiftUI

/// A floating inspector card shown at the bottom when a note is selected.
/// Displays note info, timbre selector, and delete action.
struct NoteInspectorCard: View {
    var viewModel: PianoRollViewModel
    let note: RollNote
    @Binding var selectedNoteID: UUID?

    var body: some View {
        VStack(spacing: 14) {
            // Drag handle
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 4)

            // Top row: note info + actions
            HStack(alignment: .center) {
                // Note pitch & info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(note.timbre.color)
                            .frame(width: 10, height: 10)
                        Text(viewModel.noteNames[note.row])
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                    Text("起始: \(note.startTick)t   时长: \(note.durationTicks)t")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Delete button
                Button(role: .destructive) {
                    let id = note.id
                    selectedNoteID = nil
                    viewModel.removeNote(noteID: id)
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                // Close button
                Button {
                    selectedNoteID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }

            // Timbre selector — horizontal grid
            HStack(spacing: 0) {
                ForEach(Timbre.allCases, id: \.self) { timbre in
                    let isActive = note.timbre == timbre
                    Button {
                        viewModel.changeNoteTimbre(noteID: note.id, to: timbre)
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(timbre.color.opacity(isActive ? 1.0 : 0.4))
                                    .frame(width: 30, height: 30)
                                if isActive {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            Text(timbre.displayName)
                                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? .white : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 12, y: -4)
    }
}
