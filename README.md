# MineSwift

MineSwift is a modern macOS re-implementation of the classic Windows Minesweeper, built entirely with **Swift 6** and **SwiftUI 6**.  
It faithfully recreates the original gameplay while adding powerful customization options and a unique *Growing Minefield* mode for a fresh twist.

---

## ✨ Features

- **Three classic difficulty levels** — *Beginner*, *Intermediate*, *Expert*  
- **Fully Custom Mode**:
  - Adjustable grid size (5×5 to 50×30)  
  - Customizable mine count (with reasonable min/max based on grid size)  
  - Color theme picker with automatic contrast-aware palettes  
  - Live interactive 3×3 preview of the selected theme and grid
- **Growing Minefield Mode**:
  - Mines appear progressively over time  
  - Adjustable growth delay in Custom mode  
  - Live countdown badge showing the time until the next mine grows
- **Modern SwiftUI interface**:
  - Automatic contrast adjustment for strokes and hover effects  
  - Compact ColorPicker on macOS with live updates  
  - Smooth animations and subtle transitions
- **Classic Minesweeper interactions**:
  - Left-click to reveal cells  
  - Right-click or Ctrl-click to toggle flags  
  - Instant hover feedback  
  - Chording support (clicking a revealed number cell to auto-reveal surrounding cells when flags match)
