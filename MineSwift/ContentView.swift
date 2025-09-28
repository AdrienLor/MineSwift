// Helper to determine stroke color based on base color brightness (macOS only)
#if os(macOS)
private func strokeColor(for base: Color) -> Color {
    let ns = NSColor(base)
    guard let rgb = ns.usingColorSpace(.deviceRGB) else { return .black.opacity(0.2) }
    let lum = 0.299*rgb.redComponent + 0.587*rgb.greenComponent + 0.114*rgb.blueComponent
    return lum < 0.5 ? Color.white.opacity(0.5) : Color.black.opacity(0.2)
}

// Adaptive hover overlay color based on base color brightness (macOS only)
private func hoverOverlayColor(for base: Color) -> Color {
    let ns = NSColor(base)
    guard let rgb = ns.usingColorSpace(.deviceRGB) else { return Color.black.opacity(0.15) }
    let lum = 0.299*rgb.redComponent + 0.587*rgb.greenComponent + 0.114*rgb.blueComponent
    return lum > 0.7 ? Color.black.opacity(0.15) : Color.white.opacity(0.25)
}
#endif
import SwiftUI

enum Difficulty: String, CaseIterable, Identifiable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case expert = "Expert"
    case custom = "Custom"

    var id: String { rawValue }

    var settings: (width: Int, height: Int, mines: Int) {
        switch self {
        case .beginner: return (9, 9, 10)
        case .intermediate: return (16, 16, 40)
        case .expert: return (30, 16, 99)
        case .custom: return (10, 10, 10) // default for custom, actual values come from CustomSettings
        }
    }
}

struct LevelTheme {
    var unrevealed: Color
    var revealed: Color
    var hover: Color
    var flag: Color
}

struct CustomSettings {
    var width: Int = 10
    var height: Int = 10
    var mineCount: Int = 10
    var baseColor: Color = .blue
    var growthDelay: Double = 10.0

    var minMines: Int { Int(Double(width * height) * 0.05) }
    var maxMines: Int { Int(Double(width * height) * 0.4) }

    var minGrowthDelay: Double {
        max(2.0, Double((width * height) / 50))
    }
    var maxGrowthDelay: Double {
        min(60.0, Double((width * height) / 4))
    }

    var theme: LevelTheme {
        #if os(macOS)
        let uiColor = NSColor(baseColor)
        let lighter = uiColor.blended(withFraction: 0.75, of: .white) ?? uiColor
        let hoverColor = uiColor.blended(withFraction: 0.2, of: .white) ?? uiColor
        return LevelTheme(
            unrevealed: Color(uiColor),
            revealed: Color(lighter),
            hover: Color(hoverColor).opacity(0.35),
            flag: Color(red: 0.8, green: 0.1, blue: 0.1)
        )
        #else
        return LevelTheme(
            unrevealed: baseColor,
            revealed: baseColor.opacity(0.2),
            hover: baseColor.opacity(0.35),
            flag: Color(red: 0.8, green: 0.1, blue: 0.1)
        )
        #endif
    }
}

extension Difficulty {
    var theme: LevelTheme {
        switch self {
        case .beginner:
            return LevelTheme(
                unrevealed: Color(red: 0.80, green: 0.90, blue: 0.80),
                revealed: Color(red: 0.97, green: 0.98, blue: 0.97),
                hover: Color(red: 0.55, green: 0.75, blue: 0.55).opacity(0.35),
                flag: Color(red: 0.80, green: 0.10, blue: 0.10)
            )
        case .intermediate:
            return LevelTheme(
                unrevealed: Color(red: 0.72, green: 0.80, blue: 0.90),
                revealed: Color(red: 0.96, green: 0.97, blue: 0.98),
                hover: Color(red: 0.45, green: 0.65, blue: 0.90).opacity(0.35),
                flag: Color(red: 0.85, green: 0.25, blue: 0.00)
            )
        case .expert:
            return LevelTheme(
                unrevealed: Color(red: 0.72, green: 0.42, blue: 0.48), // lighter rose terra
                revealed: Color(red: 0.99, green: 0.97, blue: 0.96),   // very soft ivory-pink
                hover: Color(red: 1.0, green: 0.50, blue: 0.50).opacity(0.35), // bright coral highlight
                flag: Color(red: 0.82, green: 0.10, blue: 0.15)        // slightly brighter brick red
            )
        case .custom:
            return LevelTheme(
                unrevealed: Color.gray,
                revealed: Color.gray.opacity(0.2),
                hover: Color.gray.opacity(0.35),
                flag: Color(red: 0.8, green: 0.1, blue: 0.1)
            )
        }
    }
}

struct ContentView: View {
    @StateObject private var game = GameModel(width: 9, height: 9, mineCount: 10)
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer? = nil
    @State private var difficulty: Difficulty = .beginner
    @State private var showGrowthFace = false

    @State private var customSettings = CustomSettings()
    @State private var showCustomConfig = false
    @State private var customTheme: LevelTheme? = nil

    private let cellSide: CGFloat = 28

    var body: some View {
        VStack(spacing: 8) {
            topBar

            ScrollView([.vertical, .horizontal]) {
                gridView
                    .padding(8)
            }
            .background(.quaternary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(12)
        .overlay(gameOverlay)
        .onChange(of: game.isGameOver) { _, newValue in
            if newValue {
                timer?.invalidate()
                timer = nil
            }
        }
        .onChange(of: game.mineGrewAt) { _, _ in
            guard game.terrainModeEnabled else { return }
            showGrowthFace = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                showGrowthFace = false
            }
        }
        .sheet(isPresented: $showCustomConfig) {
            CustomSettingsSheet(
                settings: $customSettings,
                isPresented: $showCustomConfig
            ) { s in
                customTheme = s.theme
                game.newGame(width: s.width, height: s.height, mines: s.mineCount)
                game.growthDelay = s.growthDelay
                // Reset timer and growth countdown for new custom game
                timer?.invalidate()
                timer = nil
                elapsedSeconds = 0
                game.growthCountdown = nil
            }
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack(spacing: 12) {
            Menu("Level") {
                ForEach(Difficulty.allCases.filter { $0 != .custom }) { level in
                    Button(level.rawValue) {
                        difficulty = level
                        let s = level.settings
                        game.growthDelay = nil // Reset any custom growth delay
                        game.newGame(width: s.width, height: s.height, mines: s.mines)
                        // Reset timer and terrain growth state
                        timer?.invalidate()
                        timer = nil
                        elapsedSeconds = 0
                        game.growthCountdown = nil
                        game.mineCount = game.initialMineCount
                        game.terrainModeEnabled = false
                    }
                }
                Button("Custom") {
                    difficulty = .custom
                    showCustomConfig = true
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)

            Toggle("Growing Minefield", isOn: $game.terrainModeEnabled)
                .toggleStyle(.switch)
                .frame(width: 180)

            // Growth countdown badge
            if game.terrainModeEnabled, let countdown = game.growthCountdown {
                HStack(spacing: 4) {
                    Image(systemName: countdown <= 3 ? "flame.fill" : "hourglass")
                    Text("\(countdown)")
                        .monospacedDigit()
                }
                .font(.system(.body, design: .monospaced))
                .foregroundColor(countdown <= 3 ? .red : .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .clipShape(Capsule())
                .transition(.opacity)
            }

            // Mine counter (left)
            HStack(spacing: 6) {
                Image(systemName: "flag.fill")
                Text("\(game.minesRemaining)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.red)
                    .frame(minWidth: 36, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial)
            .clipShape(Capsule())

            Spacer()

            // Face button (center)
            Button {
                game.newGame()
                // Reset timer and terrain growth state
                timer?.invalidate()
                timer = nil
                elapsedSeconds = 0
                game.growthCountdown = nil
                game.mineCount = game.initialMineCount
            } label: {
                Text(showGrowthFace ? "🔥" : (game.isGameOver ? (game.isWin ? "😎" : "😵") : "🙂"))
                    .font(.system(size: 24))
                    .scaleEffect(showGrowthFace ? 1.4 : 1.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.5), value: showGrowthFace)
            }

            Spacer()

            // Timer (right)
            Text(String(format: "%03d", elapsedSeconds))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .clipShape(Capsule())
        }
    }

    // MARK: - Grid
    private var gridView: some View {
        let columns = Array(repeating: GridItem(.fixed(cellSide), spacing: 0), count: game.width)
#if os(macOS)
        let strokeCol: Color = difficulty == .custom ? strokeColor(for: customSettings.baseColor) : Color.black.opacity(0.15)
#else
        let strokeCol: Color = Color.black.opacity(0.15)
#endif

        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(gameCells()) { cell in
                cellView(cell)
                    .frame(width: cellSide, height: cellSide)
                    .overlay(Rectangle().stroke(strokeCol, lineWidth: 0.5))
                    .contentShape(Rectangle())
#if os(macOS)
                    .overlay(
                        RightClickCatcher { game.toggleFlag(at: cell.id) }
                    )
#endif
            }
        }
    }

    private func gameCells() -> [GameModel.Cell] {
        // Accès figé pour éviter warnings "Publishing changes from background thread"
        // (on est @MainActor mais on copie par prudence)
        return Array(game.cells)
    }

    // MARK: - Cell rendering
    @ViewBuilder
    private func cellView(_ c: GameModel.Cell) -> some View {
        if !c.isRevealed {
            CellView(cell: c, theme: difficulty == .custom ? (customTheme ?? difficulty.theme) : difficulty.theme) {
                // Start timer on first click if not started and game is not over
                if elapsedSeconds == 0 && !game.isGameOver {
                    timer?.invalidate()
                    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        Task { @MainActor in
                            elapsedSeconds += 1
                        }
                    }
                }
                game.startTerrainGrowthIfNeeded()
                game.leftClick(on: c.id)
            }
        } else {
            if c.isMine {
                ZStack {
                    Rectangle().fill(Color(red: 0.9, green: 0.1, blue: 0.1))
                    Text("💣")
                        .font(.system(size: 14))
                }
            } else {
                ZStack {
                    Rectangle().fill((difficulty == .custom ? (customTheme ?? difficulty.theme) : difficulty.theme).revealed)
                    if c.adjacent > 0 {
                        Text("\(c.adjacent)")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(numberColor(c.adjacent))
                    }
                }
                .onTapGesture {
                    if c.adjacent > 0 {
                        game.chord(at: c.id)
                    }
                }
            }
        }
    }

    private func numberColor(_ n: Int) -> Color {
        switch n {
        case 1: return .blue
        case 2: return .green
        case 3: return .red
        case 4: return .purple
        case 5: return .orange
        case 6: return .pink
        case 7: return .black
        case 8: return .gray
        default: return .primary
        }
    }

    // MARK: - Overlays (Win/Lose)
    @ViewBuilder
    private var gameOverlay: some View {
        if game.isGameOver {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Label(game.isWin ? "You win!" : "Game over", systemImage: game.isWin ? "face.smiling" : "xmark.octagon")
                        .font(.title2.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding()
                }
            }
            .allowsHitTesting(false)
        }
    }
}

private struct CustomSettingsSheet: View {
    @Binding var settings: CustomSettings
    @Binding var isPresented: Bool
    let onStart: (CustomSettings) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Game Settings")
                .font(.headline)
                .padding(.bottom, 4)

            Stepper("Width: \(settings.width)", value: $settings.width, in: 5...50)
            Stepper("Height: \(settings.height)", value: $settings.height, in: 5...30)

            VStack(alignment: .leading) {
                Text("Mines: \(settings.mineCount)")
                Slider(
                    value: Binding(
                        get: { Double(settings.mineCount) },
                        set: { settings.mineCount = Int($0) }
                    ),
                    in: Double(settings.minMines)...Double(settings.maxMines),
                    step: 1
                )
            }

            ColorPicker("Theme Color", selection: $settings.baseColor, supportsOpacity: false)
                
            VStack(alignment: .leading) {
                Text("Growth delay: \(Int(settings.growthDelay)) s")
                Slider(
                    value: $settings.growthDelay,
                    in: settings.minGrowthDelay...settings.maxGrowthDelay,
                    step: 1
                )
            }

            Text("Preview")
                .font(.subheadline)
            CustomGridPreview(settings: settings)
                .frame(width: 100, height: 100)
                .padding(6)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Start Game") {
                    onStart(settings)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

private struct CellView: View {
    let cell: GameModel.Cell
    let theme: LevelTheme
    let onReveal: () -> Void
    @State private var isHovering = false
    @GestureState private var isPressed = false
    
    var body: some View {
        ZStack {
            // Base background
            Rectangle()
                .fill(theme.unrevealed)

            // Hover tint (adaptive on macOS)
#if os(macOS)
            Rectangle()
                .fill(hoverOverlayColor(for: theme.unrevealed))
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(false)
                .animation(isHovering ? .none : .easeOut(duration: 0.35), value: isHovering)
#else
            Rectangle()
                .fill(theme.hover)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(false)
                .animation(isHovering ? .none : .easeOut(duration: 0.35), value: isHovering)
#endif

            // Markers
            Group {
                if cell.isFlagged {
                    Image(systemName: "flag.fill")
                        .imageScale(.small)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(theme.flag)
                } else if cell.isQuestion {
                    Text("?")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.gray)
                }
            }
            .transition(.scale(scale: 0.5).combined(with: .opacity))
            .animation(.easeOut(duration: 0.15), value: cell.isFlagged || cell.isQuestion)
        }
        .scaleEffect(isPressed ? 0.95 : (isHovering ? 1.05 : 1.0))
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            if hovering {
                isHovering = true
            } else {
                withAnimation(.easeOut(duration: 0.35)) {
                    isHovering = false
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 0).updating($isPressed) { _, state, _ in state = true }
                 .onEnded { _ in onReveal() })
        .overlay(
            Rectangle()
                .stroke(Color.black.opacity(0.25), lineWidth: 0.6)
        )
    }
}

#if os(macOS)
import AppKit

private struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> RightClickCatcherView {
        RightClickCatcherView(onRightClick: onRightClick)
    }

    func updateNSView(_ nsView: RightClickCatcherView, context: Context) {}

    final class RightClickCatcherView: NSView {
        let onRightClick: () -> Void
        init(onRightClick: @escaping () -> Void) {
            self.onRightClick = onRightClick
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        // Only capture true right-clicks or Control+left clicks; let normal left-clicks pass through
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent else { return nil }
            if e.type == .rightMouseDown { return self }
            if e.type == .leftMouseDown && e.modifierFlags.contains(.control) { return self }
            return nil
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick()
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                onRightClick()
            } else {
                super.mouseDown(with: event)
            }
        }
    }
}
#endif

private struct CustomGridPreview: View {
    let settings: CustomSettings
    @State private var revealed: Set<Int> = []
    @State private var flagged: Set<Int> = []
    @State private var hoverIndex: Int? = nil

    var body: some View {
        let theme = settings.theme
        let columns = Array(repeating: GridItem(.fixed(30), spacing: 0), count: 3)

        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<9, id: \.self) { i in
                ZStack {
                    Rectangle()
                        .fill(theme.unrevealed)
                    if revealed.contains(i) {
                        Rectangle().fill(theme.revealed)
                        if i == 4 {
                            Text("💣")
                        } else if i % 2 == 0 {
                            Text("\(i/2)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                        }
                    }
                    if flagged.contains(i) {
                        Image(systemName: "flag.fill")
                            .foregroundColor(theme.flag)
                    }
                    if hoverIndex == i && !revealed.contains(i) {
#if os(macOS)
                        Rectangle()
                            .fill(hoverOverlayColor(for: settings.baseColor))
                            .allowsHitTesting(false)
#else
                        Rectangle()
                            .fill(theme.hover)
                            .allowsHitTesting(false)
#endif
                    }
                }
                .frame(width: 30, height: 30)
#if os(macOS)
                .overlay(Rectangle().stroke(strokeColor(for: settings.baseColor), lineWidth: 0.5))
#else
                .overlay(Rectangle().stroke(Color.black.opacity(0.15), lineWidth: 0.5))
#endif
                .onTapGesture {
                    if flagged.contains(i) {
                        flagged.remove(i)
                    } else {
                        revealed.insert(i)
                    }
                }
#if os(macOS)
                .onHover { hovering in
                    hoverIndex = hovering ? i : nil
                }
                .simultaneousGesture(
                    TapGesture(count: 1)
                        .modifiers(.control)
                        .onEnded {
                            if flagged.contains(i) {
                                flagged.remove(i)
                            } else {
                                flagged.insert(i)
                            }
                        }
                )
#endif
            }
        }
    }
}

