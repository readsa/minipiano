//
//  ContentView.swift
//  minipiano
//
//  Created by 张海洋 on 2026/2/12.
//

import SwiftUI

enum AppPage {
    case menu
    case piano
    case trombone
}

// MARK: - Main menu

struct MainMenuView: View {
    @Binding var currentPage: AppPage

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(.systemBackground),
                    Color(.secondarySystemBackground)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 50) {
                Text("🎵 迷你乐器")
                    .font(.system(size: 36, weight: .bold))

                VStack(spacing: 24) {
                    // Piano card
                    Button { currentPage = .piano } label: {
                        HStack {
                            Text("🎹")
                                .font(.system(size: 40))
                            VStack(alignment: .leading) {
                                Text("钢琴")
                                    .font(.title2.bold())
                                Text("88 键钢琴模拟器")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.1),
                                        radius: 5, y: 2)
                        )
                    }
                    .buttonStyle(.plain)

                    // Trombone card
                    Button { currentPage = .trombone } label: {
                        HStack {
                            Text("🎺")
                                .font(.system(size: 40))
                            VStack(alignment: .leading) {
                                Text("长号")
                                    .font(.title2.bold())
                                Text("倾斜手机控制音调")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.1),
                                        radius: 5, y: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 30)
            }
        }
    }
}

// MARK: - Root view

struct ContentView: View {
    @State private var currentPage: AppPage = .menu

    var body: some View {
        switch currentPage {
        case .menu:
            MainMenuView(currentPage: $currentPage)
        case .piano:
            PianoView(onBack: { currentPage = .menu })
        case .trombone:
            TromboneView(onBack: { currentPage = .menu })
        }
    }
}

#Preview {
    ContentView()
}
