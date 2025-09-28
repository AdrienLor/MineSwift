import Foundation
import SwiftUI
import Combine

@MainActor
final class GameModel: ObservableObject {

    private var terrainTimer: Timer?
    private var terrainGrowthStarted = false
    @Published var terrainModeEnabled = false {
        didSet {
            if !terrainModeEnabled {
                terrainTimer?.invalidate()
                terrainTimer = nil
                countdownTimer?.invalidate()
                countdownTimer = nil
                growthCountdown = nil
                terrainGrowthStarted = false
            }
        }
    }
    @Published var mineGrewAt: Date? = nil
    var growthDelay: Double? = nil
    @Published var growthCountdown: Int? = nil
    private var countdownTimer: Timer?
    internal private(set) var initialMineCount: Int

    // MARK: - Cellule
    struct Cell: Identifiable, Hashable {
        let id: Int       // index global dans le tableau 1D
        let x: Int
        let y: Int
        var isMine: Bool = false
        var isRevealed: Bool = false
        var isFlagged: Bool = false
        var isQuestion: Bool = false // pour plus tard (cycle drapeau ?)
        var adjacent: Int = 0
    }

    // MARK: - Paramètres & État
    @Published var width: Int
    @Published var height: Int
    @Published var mineCount: Int

    @Published private(set) var cells: [Cell] = []
    @Published private(set) var firstClickDone = false
    @Published private(set) var isGameOver = false
    @Published private(set) var isWin = false

    // Mode drapeau (au début on l’active via un bouton ; on ajoutera le clic droit après)
    @Published var flagMode = false

    // MARK: - Init
    init(width: Int = 9, height: Int = 9, mineCount: Int = 10) {
        self.width = width
        self.height = height
        self.mineCount = mineCount
        self.initialMineCount = mineCount
        resetEmptyBoard()
    }

    // MARK: - Accès utils
    private func index(x: Int, y: Int) -> Int { y * width + x }

    private func coords(of index: Int) -> (x: Int, y: Int) {
        (index % width, index / width)
    }

    private func inBounds(_ x: Int, _ y: Int) -> Bool {
        (0..<width).contains(x) && (0..<height).contains(y)
    }

    private func neighborIndices(of index: Int) -> [Int] {
        let (cx, cy) = coords(of: index)
        var out: [Int] = []
        for dy in -1...1 {
            for dx in -1...1 {
                if dx == 0 && dy == 0 { continue }
                let nx = cx + dx, ny = cy + dy
                if inBounds(nx, ny) { out.append(self.index(x: nx, y: ny)) }
            }
        }
        return out
    }

    // MARK: - Board setup
    func newGame(width: Int? = nil, height: Int? = nil, mines: Int? = nil) {
        terrainTimer?.invalidate()
        terrainTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        growthCountdown = nil
        terrainGrowthStarted = false
        mineGrewAt = nil

        if let w = width { self.width = w }
        if let h = height { self.height = h }
        if let m = mines {
            self.mineCount = m
            self.initialMineCount = m
        }

        mineCount = initialMineCount

        // Rebuild the board and basic state
        resetEmptyBoard()

        // Do NOT start terrain growth here; it will start on the first left click via startTerrainGrowthIfNeeded()
    }

    private func resetEmptyBoard() {
        let count = width * height
        cells = (0..<count).map { i in
            let (x, y) = coords(of: i)
            return Cell(id: i, x: x, y: y)
        }
        firstClickDone = false
        isGameOver = false
        isWin = false
        flagMode = false
    }

    private func placeMines(excluding safeSet: Set<Int>) {
        var slots = Array(0..<(width*height)).filter { !safeSet.contains($0) }
        slots.shuffle()
        let mines = slots.prefix(mineCount)
        for m in mines {
            cells[m].isMine = true
        }
        computeAdjacents()
    }

    private func computeAdjacents() {
        for i in cells.indices {
            if cells[i].isMine {
                cells[i].adjacent = -1
                continue
            }
            let n = neighborIndices(of: i).reduce(0) { $0 + (cells[$1].isMine ? 1 : 0) }
            cells[i].adjacent = n
        }
    }

    private func startTerrainGrowth() {
        guard terrainModeEnabled else { return }

        terrainTimer?.invalidate()

        let interval: TimeInterval
        if let customDelay = growthDelay {
            interval = customDelay
        } else {
            switch mineCount {
            case 0..<20: interval = 30
            case 20..<50: interval = 20
            default: interval = 10
            }
        }

        growthCountdown = Int(interval)
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            // Ensure we don't capture the non-Sendable timer `t` inside an async Task.
            guard let self else { t.invalidate(); return }
            Task { @MainActor in
                if let remaining = self.growthCountdown {
                    if remaining > 0 {
                        self.growthCountdown = remaining - 1
                    } else {
                        self.growthCountdown = Int(interval)
                    }
                }
            }
        }

        terrainTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.growMine()
            }
        }
    }
    
    func startTerrainGrowthIfNeeded() {
        guard terrainModeEnabled, !terrainGrowthStarted, !isGameOver else { return }
        terrainGrowthStarted = true
        startTerrainGrowth()
    }

    private func growMine() {
        let candidates = cells.indices.filter { !cells[$0].isMine && !cells[$0].isRevealed }
        guard let newMineIndex = candidates.randomElement() else { return }

        cells[newMineIndex].isMine = true

        for n in neighborIndices(of: newMineIndex) {
            if !cells[n].isMine {
                cells[n].adjacent += 1
            }
        }

        mineCount += 1
        mineGrewAt = Date()

        if terrainModeEnabled {
            let interval = growthDelay ?? (mineCount < 20 ? 30 : mineCount < 50 ? 20 : 10)
            growthCountdown = Int(interval)
        }
    }

    // MARK: - Gameplay
    var flagsPlaced: Int {
        cells.reduce(0) { $0 + ($1.isFlagged ? 1 : 0) }
    }

    var minesRemaining: Int {
        max(mineCount - flagsPlaced, 0)
    }

    func leftClick(on index: Int) {
        guard !isGameOver else { return }
        guard cells.indices.contains(index) else { return }

        if flagMode {
            toggleFlag(at: index)
            return
        }

        // Premier clic : générer mines en excluant la case + son voisinage
        if !firstClickDone {
            var safe = Set<Int>([index])
            neighborIndices(of: index).forEach { safe.insert($0) }
            placeMines(excluding: safe)
            firstClickDone = true
        }

        reveal(at: index)
    }

    func toggleFlag(at index: Int) {
        guard !isGameOver else { return }
        guard cells.indices.contains(index) else { return }
        guard !cells[index].isRevealed else { return }

        if !cells[index].isFlagged && !cells[index].isQuestion {
            // vide → drapeau
            cells[index].isFlagged = true
        } else if cells[index].isFlagged {
            // drapeau → ?
            cells[index].isFlagged = false
            cells[index].isQuestion = true
        } else {
            // ? → vide
            cells[index].isQuestion = false
        }
    }

    private func reveal(at index: Int) {
        guard cells.indices.contains(index) else { return }
        if cells[index].isRevealed || cells[index].isFlagged { return }

        if cells[index].isMine {
            // Perdu
            cells[index].isRevealed = true
            isGameOver = true
            revealAllMines()
            terrainTimer?.invalidate()
            terrainTimer = nil
            countdownTimer?.invalidate()
            countdownTimer = nil
            growthCountdown = nil
            return
        }

        // BFS : on révèle les zéros et leur périphérie
        var queue = [index]
        var visited = Set<Int>()

        while let cur = queue.first {
            queue.removeFirst()
            if visited.contains(cur) { continue }
            visited.insert(cur)

            if cells[cur].isRevealed || cells[cur].isFlagged { continue }
            cells[cur].isRevealed = true

            if cells[cur].adjacent == 0 {
                for n in neighborIndices(of: cur) {
                    if !visited.contains(n) && !cells[n].isRevealed && !cells[n].isFlagged {
                        if !cells[n].isMine {
                            queue.append(n)
                        }
                    }
                }
            }
        }

        checkWin()
        if isWin {
            terrainTimer?.invalidate()
            terrainTimer = nil
            countdownTimer?.invalidate()
            countdownTimer = nil
            growthCountdown = nil
        }
    }

    /// Minesweeper chording: If the cell at index is revealed, has adjacent > 0, and not game over,
    /// and the number of flagged neighbors equals adjacent, reveals all non-flagged, non-revealed neighbors.
    public func chord(at index: Int) {
        guard cells.indices.contains(index) else { return }
        let cell = cells[index]
        guard cell.isRevealed, cell.adjacent > 0, !isGameOver else { return }

        // Get neighbors
        let neighbors = neighborIndices(of: index)
        let flaggedCount = neighbors.filter { cells[$0].isFlagged }.count

        // Only chord if number of flags equals adjacent number
        guard flaggedCount == cell.adjacent else { return }

        // Reveal all non-flagged, non-revealed neighbors
        for n in neighbors {
            if !cells[n].isFlagged && !cells[n].isRevealed {
                reveal(at: n)
            }
        }
    }

    private func revealAllMines() {
        for i in cells.indices where cells[i].isMine {
            cells[i].isRevealed = true
        }
    }

    private func checkWin() {
        let safeTotal = width * height - mineCount
        let revealedSafe = cells.reduce(0) { $0 + ((!$1.isMine && $1.isRevealed) ? 1 : 0) }
        if revealedSafe == safeTotal {
            isWin = true
            isGameOver = true
        }
    }
}
