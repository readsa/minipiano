//
//  PianoRollProjectSheets.swift
//  minipiano
//
//  Refactored from PianoRollView.swift on 2026/2/14.
//

import SwiftUI

// MARK: - Save project sheet

/// A sheet for saving the current piano roll project with a user-defined name.
struct SaveProjectSheet: View {
    var viewModel: PianoRollViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("保存工程")
                    .font(.title2.bold())
                    .padding(.top)

                VStack(alignment: .leading, spacing: 8) {
                    Text("工程名称")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("输入工程名称", text: Bindable(viewModel).saveNameInput)
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
}

// MARK: - Load project sheet

/// A sheet for browsing and loading previously saved piano roll projects.
struct LoadProjectSheet: View {
    var viewModel: PianoRollViewModel

    var body: some View {
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
}
