//
//  PianoRollNoteEditingBar.swift
//  minipiano
//
//  Refactored from PianoRollView.swift on 2026/2/14.
//

import SwiftUI

/// A contextual toolbar shown when a note is selected, allowing timbre change,
/// deletion, and displaying note information.
struct PianoRollNoteEditingBar: View {
    var viewModel: PianoRollViewModel
    let note: RollNote
    @Binding var selectedNoteID: UUID?

    var body: some View {
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
                                .fill(timbre.color)
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
}
