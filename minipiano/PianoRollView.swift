//
//  PianoRollView.swift
//  minipiano
//
//  Created on 2026/2/13.
//  Redesigned on 2026/2/14 — modern NavigationStack layout.
//
//  Sub-components:
//    PianoRollModels.swift         – RollNote, PianoRollProject, ProjectFileInfo, Timbre.color
//    PianoRollViewModel.swift      – PianoRollViewModel (business logic, playback, persistence)
//    PianoRollToolbarView.swift    – Parameter strip (timbre, BPM, beats, measures)
//    PianoRollNoteEditingBar.swift – Floating note inspector card
//    PianoRollGridView.swift       – Grid canvas, key labels, notes layer, playhead, drag gestures
//    PianoRollProjectSheets.swift  – Save / Load project sheets
//

import SwiftUI

// MARK: - Piano Roll View (Composition Root)

struct PianoRollView: View {
    var onBack: () -> Void = {}
    @State private var viewModel = PianoRollViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // Editing state (shared with child views via @Binding)
    @State private var selectedNoteID: UUID? = nil

    private var isPortrait: Bool { verticalSizeClass == .regular }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.12, green: 0.12, blue: 0.15)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Project name row (portrait only)
                    if isPortrait {
                        projectNameBar
                    }

                    // Compact parameter strip
                    PianoRollParameterStrip(viewModel: viewModel, selectedNoteID: $selectedNoteID)

                    // Piano roll grid
                    PianoRollGridView(
                        viewModel: viewModel,
                        selectedNoteID: $selectedNoteID,
                        bottomInset: selectedNoteID != nil ? 220 : 0
                    )
                }

                // Floating note inspector card (bottom)
                if let selID = selectedNoteID,
                   let note = viewModel.notes.first(where: { $0.id == selID }) {
                    VStack {
                        Spacer()
                        NoteInspectorCard(viewModel: viewModel, note: note, selectedNoteID: $selectedNoteID)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                // MARK: Leading — Back
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.autoSave()
                        viewModel.stop()
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }

                // MARK: Principal — Project name (landscape only)
                if !isPortrait {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 5) {
                            Text(viewModel.projectName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            if viewModel.hasUnsavedChanges {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }

                // MARK: Trailing — Undo, Redo, Play, File menu
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { viewModel.undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!viewModel.canUndo)

                    Button { viewModel.redo() } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!viewModel.canRedo)

                    // Return to start
                    Button { viewModel.returnToStart() } label: {
                        Image(systemName: "backward.end.fill")
                    }

                    // Play / Pause
                    Button { viewModel.togglePlayPause() } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .foregroundStyle(viewModel.isPlaying ? .yellow : .green)
                    }

                    // Loop toggle
                    Button { viewModel.isLooping.toggle() } label: {
                        Image(systemName: "repeat")
                            .foregroundStyle(viewModel.isLooping ? .green : .secondary)
                    }

                    fileMenu
                }
            }
            .animation(.easeInOut(duration: 0.25), value: selectedNoteID)
        }
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

    // MARK: - File menu (Save / Load / Clear)

    // MARK: - Project name bar (portrait)

    private var projectNameBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(viewModel.projectName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
            if viewModel.hasUnsavedChanges {
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.2)
        }
    }

    private var fileMenu: some View {
        Menu {
            Section {
                Button {
                    viewModel.saveNameInput = viewModel.projectName
                    viewModel.showSaveSheet = true
                } label: {
                    Label("保存工程", systemImage: "square.and.arrow.down")
                }

                Button {
                    if viewModel.hasUnsavedChanges && !viewModel.notes.isEmpty {
                        viewModel.showUnsavedAlert = true
                    } else {
                        viewModel.refreshSavedProjects()
                        viewModel.showLoadSheet = true
                    }
                } label: {
                    Label("加载工程", systemImage: "folder")
                }
            }

            Section {
                Button(role: .destructive) {
                    if !viewModel.notes.isEmpty { viewModel.showClearConfirm = true }
                } label: {
                    Label("清除所有音符", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

#Preview {
    PianoRollView()
}
