# 🎵 MiniPiano — 迷你乐器

A lightweight iOS virtual instrument app built entirely with **SwiftUI** and **AVFoundation**. It ships three interactive instruments in a single app: a full-range piano, a gyroscope-driven trombone, and a piano roll melody editor.

---

## Table of Contents / 目录

- [English](#english)
- [中文](#中文)

---

<a id="english"></a>

## English

### Overview

**MiniPiano** is a native iOS app that lets you play and compose music right on your iPhone. It includes three instruments:

| Instrument | Description |
|---|---|
| 🎹 **Piano** | An 8-octave (C1–C8) virtual piano with multi-touch support — press multiple keys simultaneously |
| 🎺 **Trombone** | A trombone simulator controlled by tilting your phone (CoreMotion gyroscope) or sliding on a touch bar, with a brass-like harmonic waveform |
| 🎼 **Piano Roll Editor** | A grid-based MIDI-style note editor spanning 5 octaves (C2–C7). Compose melodies, adjust BPM, play them back, and save/load projects as JSON |

### Features

- **Multi-timbre polyphonic synthesizer** — real-time audio generation via `AVAudioSourceNode`, supporting multiple simultaneous notes with 6 different waveforms (sine, square, triangle, sawtooth, pulse, noise)
- **ADSR envelope** — smooth attack and release phases eliminate clicking and popping sounds for professional audio quality
- **Multi-touch piano keys** — independent `DragGesture` per key, allowing chords
- **Gyroscope-controlled trombone** — tilt forward/backward to sweep C2–C6; or use the on-screen touch bar for precise pitch control
- **Piano roll editor** with:
  - Tap to place/remove notes on a scrollable grid
  - Adjustable BPM (40–300)
  - Adjustable measure count
  - Playback with real-time cursor
  - Undo / Redo (up to 50 levels)
  - Save / Load projects (persisted as JSON files in the app's Documents directory)
  - Auto-save on edit
- **Pure SwiftUI** — no storyboards, no UIKit, no third-party dependencies

### Requirements

| Item | Minimum |
|---|---|
| Platform | iOS |
| Deployment Target | iOS 26.0+ |
| Xcode | 26+ |
| Swift | 5.0 |

### Project Structure

```
minipiano/
├── minipianoApp.swift        # App entry point
├── ContentView.swift         # Navigation: main menu → instruments
├── PianoView.swift           # 8-octave virtual piano (multi-touch)
├── TromboneView.swift        # Gyroscope trombone simulator
├── PianoRollView.swift       # Piano roll note editor & playback
├── AudioSynthEngine.swift    # Multi-timbre polyphonic audio synthesizer with ADSR envelope
└── Assets.xcassets/          # App icons & accent color
```

### Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/<your-username>/minipiano.git
   ```
2. Open `minipiano.xcodeproj` in Xcode.
3. Select an iPhone simulator or a real device.
4. Build and run (**⌘R**).

> **Note:** The trombone's gyroscope feature requires a **real device** — it will not respond to tilt in the Simulator.

### Architecture

- **`AudioSynthEngine`** — A thread-safe, polyphonic synthesizer built on `AVAudioEngine`. Supports 6 waveforms (sine, square, triangle, sawtooth, pulse, noise) with customizable ADSR envelope for smooth attack and release. Each active note spawns its own `AVAudioSourceNode`. Also supports `DynamicFrequency` for real-time pitch bending (trombone).
- **`PianoRollViewModel`** — An `@Observable` view model managing the note grid, playback timer, undo/redo snapshots, and JSON-based project persistence.
- **Navigation** — A simple `enum AppPage` state machine drives page transitions without `NavigationStack`, keeping the UI minimal.

### License

This project is provided as-is for educational and personal use.

---

<a id="中文"></a>

## 中文

### 概述

**迷你乐器 (MiniPiano)** 是一款原生 iOS 应用，让你在 iPhone 上即可演奏和创作音乐。内含三种乐器：

| 乐器 | 说明 |
|---|---|
| 🎹 **钢琴** | 8 个八度（C1–C8）的虚拟钢琴，支持多点触控同时按下多个琴键 |
| 🎺 **长号** | 通过倾斜手机（CoreMotion 陀螺仪）或滑动屏幕上的触摸条来控制音高，采用铜管乐器风格的谐波波形 |
| 🎼 **音乐编辑器** | 基于网格的钢琴卷帘编辑器，覆盖 5 个八度（C2–C7）。可创作旋律、调节 BPM、回放，并以 JSON 格式保存/加载工程 |

### 功能特性

- **多音色复音合成器** — 通过 `AVAudioSourceNode` 实时生成音频，支持多音同时发声，提供 6 种波形（正弦波、方波、三角波、锯齿波、脉冲波、噪声）
- **ADSR 包络** — 柔和的切入和释放阶段，消除爆破音和噼啪声，提供专业音质
- **多点触控琴键** — 每个琴键独立手势，可弹奏和弦
- **陀螺仪控制长号** — 前后倾斜手机在 C2–C6 之间滑动音高；也可使用屏幕触摸条精准控制
- **钢琴卷帘编辑器**：
  - 点击网格放置/删除音符
  - 可调 BPM（40–300）
  - 可调小节数
  - 带实时光标的回放功能
  - 撤销 / 重做（最多 50 步）
  - 保存 / 加载工程（以 JSON 文件存储在应用 Documents 目录）
  - 编辑时自动保存
- **纯 SwiftUI** — 无 Storyboard、无 UIKit、无第三方依赖

### 环境要求

| 项目 | 最低要求 |
|---|---|
| 平台 | iOS |
| 部署目标 | iOS 26.0+ |
| Xcode | 26+ |
| Swift | 5.0 |

### 项目结构

```
minipiano/
├── minipianoApp.swift        # 应用入口
├── ContentView.swift         # 导航：主菜单 → 各乐器页面
├── PianoView.swift           # 8 八度虚拟钢琴（多点触控）
├── TromboneView.swift        # 陀螺仪长号模拟器
├── PianoRollView.swift       # 钢琴卷帘音符编辑器 & 回放
├── AudioSynthEngine.swift    # 多音色复音音频合成器（带 ADSR 包络）
└── Assets.xcassets/          # 应用图标 & 主题色
```

### 快速开始

1. 克隆仓库：
   ```bash
   git clone https://github.com/<your-username>/minipiano.git
   ```
2. 用 Xcode 打开 `minipiano.xcodeproj`。
3. 选择 iPhone 模拟器或真机。
4. 编译并运行（**⌘R**）。

> **提示：** 长号的陀螺仪功能需要在**真机**上运行，模拟器中无法响应倾斜操作。

### 架构说明

- **`AudioSynthEngine`** — 基于 `AVAudioEngine` 的线程安全多音合成器。支持 6 种波形（正弦波、方波、三角波、锯齿波、脉冲波、噪声），配备可定制的 ADSR 包络以实现柔和的切入和释放。每个活跃音符生成独立的 `AVAudioSourceNode`。支持 `DynamicFrequency` 实时变调（长号）。
- **`PianoRollViewModel`** — 使用 `@Observable` 的视图模型，管理音符网格、回放定时器、撤销/重做快照以及基于 JSON 的工程持久化。
- **页面导航** — 通过简单的 `enum AppPage` 状态机驱动页面切换，无需 `NavigationStack`，保持 UI 精简。

### 许可

本项目仅供学习和个人使用。
