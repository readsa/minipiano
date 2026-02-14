//
//  PianoRollView.swift
//  minipiano
//
//  Created on 2026/2/13.
//  Refactored on 2026/2/14 — now a slim composition root.
//
//  Sub-components:
//    PianoRollModels.swift         – RollNote, PianoRollProject, ProjectFileInfo, Timbre.color
//    PianoRollViewModel.swift      – PianoRollViewModel (business logic, playback, persistence)
//    PianoRollToolbarView.swift    – Top toolbar (timbre, BPM, undo/redo, measures, save/load)
//    PianoRollNoteEditingBar.swift – Contextual note editing bar
//    PianoRollGridView.swift       – Grid canvas, key labels, notes layer, playhead, drag gestures
//    PianoRollProjectSheets.swift  – Save / Load project sheets
//

import SwiftUI

// MARK: - Piano Roll View (Composition Root)

struct PianoRollView: View {
    var onBack: () -> Void = {}
    @State private var viewModel = PianoRollViewModel()
    @Environment(\.scenePhase) private var scenePhase

    // Editing state (shared with child views via @Binding)
    @State private var selectedNoteID: UUID? = nil

    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.12, blue: 0.15)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top toolbar
                PianoRollToolbarView(viewModel: viewModel, selectedNoteID: $selectedNoteID)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                // Note editing toolbar (shown when a note is selected)
                if let selID = selectedNoteID,
                   let note = viewModel.notes.first(where: { $0.id == selID }) {
                    PianoRollNoteEditingBar(viewModel: viewModel, note: note, selectedNoteID: $selectedNoteID)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Piano roll grid
                PianoRollGridView(viewModel: viewModel, selectedNoteID: $selectedNoteID)
            }

            // Back button – bottom-left
            backButton
        }
        .animation(.easeInOut(duration: 0.2), value: selectedNoteID)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                viewModel.autoSave()
            }
        }
        .alert("确认清除", isPresented: Bindable(viewModel).showClearConfirm) {
            Button("清除所有音符", role: .destructive) { viewModel.clearAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作将删除当前所有音符，是否继续？")
        }
        .alert("未保存的更改", isPresented: Bindable(viewModel).showUnsavedAlert) {
            Button("保存并加载") { viewModel.showSaveSheet = true }
            Button("不保存，直接加载", role: .destructive) {
                viewModel.refreshSavedProjects()
                viewModel.showLoadSheet = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前工程有未保存的更改，是否先保存？")
        }
        .alert("保存成功", isPresented: Bindable(viewModel).showSaveSuccess) {
            Button("好的") {}
        } message: {
            Text("工程已保存为 \(viewModel.projectName)")
        }
        .sheet(isPresented: Bindable(viewModel).showSaveSheet) {
            SaveProjectSheet(viewModel: viewModel)
        }
        .sheet(isPresented: Bindable(viewModel).showLoadSheet) {
            LoadProjectSheet(viewModel: viewModel)
        }
    }

    // MARK: - Back button

    private var backButton: some View {
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
}

#Preview {
    PianoRollView()
}
