import AppKit

private let mongolianCharacters: [String] = [
    "\u{1820}", "\u{1821}", "\u{1822}", "\u{1823}", "\u{1824}", "\u{1825}",
    "\u{1826}", "\u{1827}", "\u{1828}", "\u{1829}", "\u{182A}", "\u{182B}",
    "\u{182C}", "\u{182D}", "\u{182E}", "\u{182F}", "\u{1830}", "\u{1831}",
    "\u{1832}", "\u{1833}", "\u{1834}", "\u{1835}", "\u{1836}", "\u{1837}",
    "\u{1838}", "\u{1839}", "\u{183A}", "\u{183B}", "\u{183C}", "\u{183D}",
    "\u{183E}", "\u{183F}", "\u{1840}", "\u{1841}", "\u{1842}"
]

private struct CellState {
    var age: Int = MatrixRainView.expiredAge
    var text: String = mongolianCharacters[0]
    var span: Int = 1
}

private struct CursorState {
    var column: Int
    var row: Int
    var speed: Int
    var tick: Int
    var drift: Int
}

final class MatrixRainView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    static let expiredAge = 90

    private var cells: [CellState] = []
    private var cursors: [CursorState] = []
    private var columnCount = 0
    private var rowCount = 0
    private var timer: Timer?
    private let cellWidth: CGFloat = 16
    private let cellHeight: CGFloat = 15
    private let fontSize: CGFloat = 14
    private let backgroundColor = NSColor.black

    private lazy var glyphFont: NSFont = {
        let preferredFonts = [
            "NotoSansMongolian-Regular",
            "Noto Sans Mongolian",
            "MongolianBaiti",
            "Mongolian Baiti",
            "Menlo"
        ]

        for name in preferredFonts {
            if let font = NSFont(name: name, size: fontSize) {
                return font
            }
        }

        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        resetSimulation(for: frameRect.size)
        startAnimation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        resetSimulation(for: bounds.size)
        startAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resetSimulation(for: newSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()

        for row in 0..<rowCount {
            for column in 0..<columnCount {
                let cell = cells[indexForCell(column: column, row: row)]
                guard cell.age < Self.expiredAge, cell.span > 0 else {
                    continue
                }

                let text = attributedText(for: cell, column: column, row: row)
                let rect = NSRect(
                    x: CGFloat(column) * cellWidth,
                    y: CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight * CGFloat(cell.span)
                )
                drawRotated(text, in: rect)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.terminate(nil)
    }

    private func startAnimation() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.advanceFrame()
        }
    }

    private func resetSimulation(for size: NSSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        columnCount = max(1, Int(ceil(size.width / cellWidth)))
        rowCount = max(1, Int(ceil(size.height / cellHeight)))
        cells = Array(repeating: CellState(), count: columnCount * rowCount)

        let cursorCount = max(28, Int(Double(columnCount) * 1.45))
        cursors = (0..<cursorCount).map { _ in
            makeCursor(startAboveScreen: Bool.random())
        }
    }

    private func advanceFrame() {
        guard rowCount > 0, columnCount > 0 else {
            return
        }

        for index in cells.indices where cells[index].age < Self.expiredAge {
            cells[index].age += 1
        }

        for index in cursors.indices {
            cursors[index].tick += 1
            guard cursors[index].tick >= cursors[index].speed else {
                continue
            }
            cursors[index].tick = 0

            let drawColumn = clampedColumn(cursors[index].column + cursors[index].drift)
            let drawRow = cursors[index].row
            if drawRow >= 0, drawRow < rowCount {
                igniteCell(column: drawColumn, row: drawRow)
            }

            if Int.random(in: 0..<9) == 0 {
                cursors[index].drift = Int.random(in: -1...1)
            }

            cursors[index].row += 1
            let overrun = Int.random(in: 8...36)
            if cursors[index].row > rowCount + overrun {
                cursors[index] = makeCursor(startAboveScreen: true)
            }
        }

        needsDisplay = true
    }

    private func colorForCell(age: Int, column: Int, row: Int) -> NSColor {
        let depth = depthFade(column: column, row: row)
        if age <= 1 {
            return NSColor(calibratedRed: 0.82, green: 1.0, blue: 0.82, alpha: 1.0)
        }

        if age < 10 {
            let t = CGFloat(age) / 10.0
            return NSColor(
                calibratedRed: (0.34 * (1.0 - t)) * depth,
                green: 1.0 * depth,
                blue: (0.42 * (1.0 - t)) * depth,
                alpha: 0.95
            )
        }

        let fade = max(0.0, 1.0 - CGFloat(age - 10) / CGFloat(Self.expiredAge - 10))
        return NSColor(
            calibratedRed: 0.0,
            green: (0.72 * fade + 0.08) * depth,
            blue: 0.12 * fade * depth,
            alpha: max(0.0, min(1.0, fade))
        )
    }

    private func depthFade(column: Int, row: Int) -> CGFloat {
        let centerColumn = CGFloat(columnCount) / 2.0
        let centerRow = CGFloat(rowCount) / 2.0
        let dx = (CGFloat(column) - centerColumn) / max(centerColumn, 1.0)
        let dy = (CGFloat(row) - centerRow) / max(centerRow, 1.0)
        let distance = min(1.0, sqrt(dx * dx + dy * dy))
        return 1.0 - distance * 0.38
    }

    private func attributedText(for cell: CellState, column: Int, row: Int) -> NSAttributedString {
        let text = cell.text as NSString
        let attributed = NSMutableAttributedString(string: cell.text)

        for characterIndex in 0..<text.length {
            let distanceFromLastCharacter = text.length - characterIndex - 1
            let characterAge = min(Self.expiredAge, cell.age + distanceFromLastCharacter * 12)
            let color = colorForCell(age: characterAge, column: column, row: row + characterIndex)
            attributed.addAttributes(
                [
                    .font: glyphFont,
                    .foregroundColor: color
                ],
                range: NSRange(location: characterIndex, length: 1)
            )
        }

        return attributed
    }

    private func igniteCell(column: Int, row: Int) {
        guard !isCoveredByChunk(column: column, row: row) else {
            return
        }

        let index = indexForCell(column: column, row: row)
        let text = randomMatrixText(maxRowsAvailable: rowCount - row)
        let span = max(1, text.count)

        cells[index].age = 0
        cells[index].text = text
        cells[index].span = span

        if span > 1 {
            for coveredRow in (row + 1)..<min(row + span, rowCount) {
                let coveredIndex = indexForCell(column: column, row: coveredRow)
                cells[coveredIndex].age = 0
                cells[coveredIndex].text = ""
                cells[coveredIndex].span = 0
            }
        }
    }

    private func randomMatrixText(maxRowsAvailable: Int) -> String {
        let roll = Int.random(in: 0..<100)
        let count: Int
        switch roll {
        case 0..<68:
            count = 1
        case 68..<91:
            count = 2
        case 91..<99:
            count = 3
        default:
            count = 4
        }

        let boundedCount = max(1, min(count, maxRowsAvailable))
        return (0..<boundedCount)
            .map { _ in mongolianCharacters.randomElement() ?? "\u{1820}" }
            .joined()
    }

    private func isCoveredByChunk(column: Int, row: Int) -> Bool {
        guard row > 0 else {
            return false
        }

        let startRow = max(0, row - 4)
        for previousRow in startRow..<row {
            let previous = cells[indexForCell(column: column, row: previousRow)]
            if previous.age < Self.expiredAge, previous.span > row - previousRow {
                return true
            }
        }

        return false
    }

    private func makeCursor(startAboveScreen: Bool) -> CursorState {
        CursorState(
            column: Int.random(in: 0..<max(columnCount, 1)),
            row: startAboveScreen ? -Int.random(in: 1...rowCount) : Int.random(in: 0..<max(rowCount, 1)),
            speed: Int.random(in: 1...4),
            tick: Int.random(in: 0...3),
            drift: Int.random(in: -1...1)
        )
    }

    private func indexForCell(column: Int, row: Int) -> Int {
        row * columnCount + column
    }

    private func clampedColumn(_ column: Int) -> Int {
        min(max(column, 0), max(columnCount - 1, 0))
    }

    private func drawRotated(_ text: NSAttributedString, in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            text.draw(in: rect)
            return
        }

        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: .pi / 2)

        let glyphSize = text.size()
        let drawPoint = NSPoint(x: -glyphSize.width / 2, y: -glyphSize.height / 2)
        text.draw(at: drawPoint)
        context.restoreGState()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.contentView = MatrixRainView(frame: NSRect(origin: .zero, size: screenFrame.size))
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        NSCursor.hide()
        self.window = window
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSCursor.unhide()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
