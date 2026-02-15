//
//  PianoRollProjectSheets.swift
//  minipiano
//
//  Refactored from PianoRollView.swift on 2026/2/14.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Save project sheet

/// A sheet for saving the current piano roll project with a user-defined name.
struct SaveProjectSheet: View {
    var viewModel: PianoRollViewModel
    var isSaveAs: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(isSaveAs ? "另存为" : "保存工程")
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
                    Button("取消") { 
                        viewModel.shouldShareAfterSave = false
                        viewModel.showSaveSheet = false
                        viewModel.showSaveAsSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let name = viewModel.saveNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        viewModel.saveWithName(name.isEmpty ? "未命名工程" : name)
                        viewModel.showSaveSheet = false
                        viewModel.showSaveAsSheet = false
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
            VStack(spacing: 0) {
                // "从文件打开" button
                Button {
                    viewModel.showLoadSheet = false
                    viewModel.showDocumentPicker = true
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("从文件打开")
                                .font(.headline)
                            Text("选择其他位置的工程文件")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.top)
                
                Divider()
                    .padding(.vertical, 8)
                
                // App documents list
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
            .navigationTitle("打开工程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { viewModel.showLoadSheet = false }
                }
            }
        }
    }
}

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    var viewModel: PianoRollViewModel
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.json])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var viewModel: PianoRollViewModel
        
        init(viewModel: PianoRollViewModel) {
            self.viewModel = viewModel
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            // Load the project from the selected file
            viewModel.loadProject(from: url)
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
