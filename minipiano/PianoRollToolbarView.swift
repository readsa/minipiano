//
//  PianoRollToolbarView.swift
//  minipiano
//
//  Refactored from PianoRollView.swift on 2026/2/14.
//  Redesigned as a compact parameter strip on 2026/2/14.
//

import SwiftUI

/// A compact parameter strip below the navigation bar.
/// Contains timbre picker, beats-per-measure, BPM slider, and measure controls.
struct PianoRollParameterStrip: View {
    var viewModel: PianoRollViewModel
    @Binding var selectedNoteID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                timbreMenu
                separator
                beatsPerMeasureMenu
                separator
                bpmControl
                separator
                measureControls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }

    // MARK: - Timbre selector

    private var timbreMenu: some View {
        Menu {
            ForEach(Timbre.allCases, id: \.self) { timbre in
                Button {
                    viewModel.selectedTimbre = timbre
                } label: {
                    Label {
                        Text(timbre.displayName)
                    } icon: {
                        if viewModel.selectedTimbre == timbre {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.selectedTimbre.color)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                    }
                Text(viewModel.selectedTimbre.displayName)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
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
                    Label {
                        Text("每小节 \(n) 拍")
                    } icon: {
                        if viewModel.beatsPerMeasure == n {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "metronome.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(viewModel.beatsPerMeasure)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Text("拍/小节")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
        }
    }

    // MARK: - BPM

    private var bpmControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Int(viewModel.bpm))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.orange)
                .contentTransition(.numericText())
                .frame(minWidth: 30, alignment: .trailing)
            Slider(value: Bindable(viewModel).bpm, in: 40...240, step: 1)
                .frame(width: 100)
                .tint(.orange)
            Text("BPM")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Measures

    private var measureControls: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.removeMeasure()
            } label: {
                Image(systemName: "minus")
                    .font(.caption.bold())
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.1), in: .rect(cornerRadius: 6))
            }
            .disabled(viewModel.measures <= 1)

            Text("\(viewModel.measures)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .frame(minWidth: 20, alignment: .center)

            Button {
                viewModel.addMeasure()
            } label: {
                Image(systemName: "plus")
                    .font(.caption.bold())
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.1), in: .rect(cornerRadius: 6))
            }

            Text("小节")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Reusable separator

    private var separator: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(.white.opacity(0.15))
            .frame(width: 1, height: 22)
    }
}
