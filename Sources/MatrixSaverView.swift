import Cocoa
import CoreText
import Metal
import MetalKit
import ScreenSaver
import simd

private struct MatrixColor {
    var r: Float
    var g: Float
    var b: Float

    func blend(_ t: Float, with other: MatrixColor) -> MatrixColor {
        let a = max(0, min(1, t))
        let b = 1 - a
        return MatrixColor(r: r * a + other.r * b, g: g * a + other.g * b, b: self.b * a + other.b * b)
    }
}

private struct Cell {
    var glyph: UInt8 = 0
    var phase: Int32 = 0
    var phaseTicks: Int32 = 0
    var waitTicks: Int32 = 0
    var age: Int32 = 0
    var brightness: Float = 0
    var color = SIMD4<Float>(0, 0, 0, 0)
}

private struct Cursor {
    var row: Int = 0
    var column: Int = 0
    var phase: Int32 = 4
    var active = false
}

private struct CellVertex {
    var x: UInt16
    var y: UInt16
    var z: UInt16
    var texX: UInt8
    var texY: UInt8
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8
}

private struct Uniforms {
    var gridSize: SIMD2<Float>
    var depthScale: Float
    var padding: Float = 0
}

@objc(org_indirect_screensaver_Matrix)
public final class Matrix: ScreenSaverView {
    private var metalView: MatrixMetalView?
    private var configurationController: MatrixConfigurationController?

    public override var frame: NSRect {
        didSet {
            syncMetalViewFrame(resetSimulation: oldValue.size != frame.size)
        }
    }

    public override var bounds: NSRect {
        didSet {
            syncMetalViewFrame(resetSimulation: oldValue.size != bounds.size)
        }
    }

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
        setupView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 30.0
        setupView()
    }

    public override var hasConfigureSheet: Bool { true }
    public override var configureSheet: NSWindow? {
        let controller = MatrixConfigurationController(preferences: MatrixPreferences.load()) { [weak self] preferences in
            preferences.save()
            self?.metalView?.applyPreferences(preferences)
        }
        configurationController = controller
        return controller.window
    }

    public override func animateOneFrame() {
        syncMetalViewFrame(resetSimulation: false)
        metalView?.tick()
        metalView?.draw()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncMetalViewFrame(resetSimulation: true)
    }

    public override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        syncMetalViewFrame(resetSimulation: true)
    }

    public override func layout() {
        super.layout()
        syncMetalViewFrame(resetSimulation: false)
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        syncMetalViewFrame(resetSimulation: oldSize != bounds.size)
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        syncMetalViewFrame(resetSimulation: true)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncMetalViewFrame(resetSimulation: true)
    }

    public override func viewWillDraw() {
        super.viewWillDraw()
        syncMetalViewFrame(resetSimulation: false)
    }

    private func setupView() {
        guard metalView == nil, let device = MTLCreateSystemDefaultDevice() else { return }
        let view = MatrixMetalView(frame: NSRect(origin: .zero, size: bounds.size), device: device)
        view.applyPreferences(MatrixPreferences.load())
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        metalView = view
        syncMetalViewFrame(resetSimulation: true)
    }

    private func syncMetalViewFrame(resetSimulation: Bool) {
        guard let metalView else { return }
        let targetFrame = NSRect(origin: .zero, size: bounds.size)
        if metalView.frame != targetFrame {
            metalView.frame = targetFrame
        }
        if resetSimulation {
            metalView.resetSimulation()
        }
    }
}

private struct MatrixPreferences {
    var minorInstability = true
    var threeDFade = true
    var rotate = false
    var cellSize = 16
    var colors = [
        MatrixColor(r: 1, g: 1, b: 1),
        MatrixColor(r: 0, g: 1, b: 0),
        MatrixColor(r: 0, g: 1, b: 0)
    ]

    static func load() -> MatrixPreferences {
        var prefs = MatrixPreferences()
        guard let defaults = ScreenSaverDefaults(forModuleWithName: "org.indirect.screensaver.Matrix") else {
            return prefs
        }

        if defaults.object(forKey: "MinorInstability") != nil {
            prefs.minorInstability = defaults.bool(forKey: "MinorInstability")
        }
        if defaults.object(forKey: "3DFade") != nil {
            prefs.threeDFade = defaults.bool(forKey: "3DFade")
        }
        if defaults.object(forKey: "Rotate") != nil {
            prefs.rotate = defaults.bool(forKey: "Rotate")
        }

        let size = defaults.integer(forKey: "CellSize")
        if size > 0 {
            prefs.cellSize = size
        }

        for index in 0..<3 {
            if let color = colorFromDefaults(defaults, key: "color\(index)") {
                prefs.colors[index] = color
            }
        }
        return prefs
    }

    func save() {
        guard let defaults = ScreenSaverDefaults(forModuleWithName: "org.indirect.screensaver.Matrix") else {
            return
        }
        defaults.set(minorInstability, forKey: "MinorInstability")
        defaults.set(threeDFade, forKey: "3DFade")
        defaults.set(rotate, forKey: "Rotate")
        defaults.set(cellSize, forKey: "CellSize")
        defaults.set("Metal", forKey: "Renderer")
        for index in 0..<3 {
            defaults.set([colors[index].r, colors[index].g, colors[index].b], forKey: "color\(index)")
        }
        defaults.synchronize()
    }

    private static func colorFromDefaults(_ defaults: ScreenSaverDefaults, key: String) -> MatrixColor? {
        if let color = (defaults.object(forKey: key) as? NSColor)?.usingColorSpace(NSColorSpace.deviceRGB) {
            return MatrixColor(r: Float(color.redComponent), g: Float(color.greenComponent), b: Float(color.blueComponent))
        }

        if let data = defaults.data(forKey: key),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)?.usingColorSpace(.deviceRGB) {
            return MatrixColor(r: Float(color.redComponent), g: Float(color.greenComponent), b: Float(color.blueComponent))
        }

        if let values = defaults.array(forKey: key) as? [NSNumber], values.count >= 3 {
            return MatrixColor(r: values[0].floatValue, g: values[1].floatValue, b: values[2].floatValue)
        }

        return nil
    }
}

private final class MatrixConfigurationController: NSObject {
    let window: NSWindow
    private let onSave: (MatrixPreferences) -> Void
    private let rendererPopup = NSPopUpButton(frame: NSRect(x: 130, y: 178, width: 181, height: 26), pullsDown: false)
    private let minorInstabilityButton = NSButton(checkboxWithTitle: "Minor instability", target: nil, action: nil)
    private let threeDFadeButton = NSButton(checkboxWithTitle: "3D fade", target: nil, action: nil)
    private let rotateButton = NSButton(checkboxWithTitle: "Rotate", target: nil, action: nil)
    private let cellSizePopup = NSPopUpButton(frame: NSRect(x: 130, y: 88, width: 181, height: 26), pullsDown: false)
    private let colorWells = [NSColorWell(), NSColorWell(), NSColorWell()]

    init(preferences: MatrixPreferences, onSave: @escaping (MatrixPreferences) -> Void) {
        self.onSave = onSave
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 442, height: 299),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ConfigureSheet"
        window.isRestorable = true
        super.init()

        let saveButton = NSButton(title: "OK", target: self, action: #selector(save))
        saveButton.frame = NSRect(x: 338, y: 13, width: 90, height: 34)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.frame = NSRect(x: 248, y: 13, width: 90, height: 34)
        cancelButton.bezelStyle = .rounded
        let defaultsButton = NSButton(title: "Defaults", target: self, action: #selector(setDefaults))
        defaultsButton.frame = NSRect(x: 18, y: 14, width: 93, height: 32)
        defaultsButton.bezelStyle = .rounded

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 442, height: 299))
        window.contentView = content

        let iconView = NSImageView(frame: NSRect(x: 24, y: 219, width: 64, height: 64))
        iconView.image = NSImage(named: NSImage.applicationIconName)
        iconView.imageScaling = .scaleProportionallyUpOrDown

        let title = label("Matrix", frame: NSRect(x: 104, y: 267, width: 290, height: 17))
        title.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)

        let copyright = label(
            Bundle(for: Matrix.self).localizedString(forKey: "NSHumanReadableCopyright", value: "Copyright 2003-2021, Monroe Williams", table: "InfoPlist"),
            frame: NSRect(x: 104, y: 247, width: 320, height: 20)
        )

        let linkButton = NSButton(title: "https://github.com/monroewilliams/MatrixDownload/", target: self, action: #selector(clickLink))
        linkButton.frame = NSRect(x: 106, y: 223, width: 309, height: 23)
        linkButton.bezelStyle = .inline
        linkButton.isBordered = false
        linkButton.alignment = .left

        let separator = NSBox(frame: NSRect(x: 12, y: 209, width: 418, height: 5))
        separator.boxType = .separator

        rendererPopup.addItem(withTitle: "Metal")
        rendererPopup.lastItem?.tag = 2
        rendererPopup.selectItem(withTag: 2)
        rendererPopup.isEnabled = false

        for (title, tag) in [("Small", 8), ("Medium", 16), ("Large", 32)] {
            cellSizePopup.addItem(withTitle: title)
            cellSizePopup.lastItem?.tag = tag
        }

        minorInstabilityButton.frame = NSRect(x: 131, y: 139, width: 133, height: 18)
        threeDFadeButton.frame = NSRect(x: 131, y: 159, width: 133, height: 18)
        rotateButton.frame = NSRect(x: 131, y: 119, width: 133, height: 18)
        for button in [minorInstabilityButton, threeDFadeButton, rotateButton] {
            button.setButtonType(.switch)
        }

        let controls: [NSView] = [
            cancelButton, saveButton, defaultsButton, iconView, title, copyright, linkButton, separator,
            label("Renderer:", frame: NSRect(x: 10, y: 184, width: 118, height: 17)), rendererPopup,
            threeDFadeButton, minorInstabilityButton, rotateButton,
            cellSizePopup, label("Glyph Size:", frame: NSRect(x: 10, y: 94, width: 118, height: 17)),
            label("Colors:", frame: NSRect(x: 10, y: 63, width: 118, height: 17)),
            colorWells[0], colorWells[1], colorWells[2]
        ]
        controls.forEach { content.addSubview($0) }

        colorWells[0].frame = NSRect(x: 133, y: 60, width: 44, height: 23)
        colorWells[1].frame = NSRect(x: 185, y: 60, width: 44, height: 23)
        colorWells[2].frame = NSRect(x: 237, y: 60, width: 44, height: 23)
        apply(preferences)
    }

    @objc private func save() {
        let colors = colorWells.map { well -> MatrixColor in
            let color = well.color.usingColorSpace(.deviceRGB) ?? well.color
            return MatrixColor(r: Float(color.redComponent), g: Float(color.greenComponent), b: Float(color.blueComponent))
        }
        let preferences = MatrixPreferences(
            minorInstability: minorInstabilityButton.state == .on,
            threeDFade: threeDFadeButton.state == .on,
            rotate: rotateButton.state == .on,
            cellSize: cellSizePopup.selectedItem?.tag ?? 16,
            colors: colors
        )
        onSave(preferences)
        window.sheetParent?.endSheet(window)
    }

    @objc private func cancel() {
        window.sheetParent?.endSheet(window)
    }

    @objc private func setDefaults() {
        apply(MatrixPreferences())
    }

    @objc private func clickLink() {
        if let url = URL(string: "https://github.com/monroewilliams/MatrixDownload/") {
            NSWorkspace.shared.open(url)
        }
    }

    private func apply(_ preferences: MatrixPreferences) {
        minorInstabilityButton.state = preferences.minorInstability ? .on : .off
        threeDFadeButton.state = preferences.threeDFade ? .on : .off
        rotateButton.state = preferences.rotate ? .on : .off
        cellSizePopup.selectItem(withTag: preferences.cellSize)
        if cellSizePopup.selectedItem == nil {
            cellSizePopup.selectItem(withTag: 16)
        }
        for index in 0..<3 {
            let color = preferences.colors[index]
            colorWells[index].color = NSColor(calibratedRed: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: 1)
        }
    }

    private func label(_ text: String, frame: NSRect) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = frame
        field.alignment = .left
        return field
    }
}

private final class MatrixMetalView: MTKView, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let glyphTexture: MTLTexture
    private let glyphSampler: MTLSamplerState
    private let vertexOffsetsBuffer: MTLBuffer
    private let frameSemaphore = DispatchSemaphore(value: 3)

    private var cells: [Cell] = []
    private var cursors: [Cursor] = []
    private var instanceVertices: [CellVertex] = []
    private var instanceBuffers: [MTLBuffer] = []
    private var instanceBufferCapacity = 0
    private var frameIndex = 0
    private var columns = 0
    private var rows = 0
    private var logicalWidth: Float = 1
    private var logicalHeight: Float = 1
    private var pixelWidth: Double = 1
    private var pixelHeight: Double = 1
    private var activeCellCount = 0
    private var tickCount: Int32 = 0
    private var fadeState: Int32 = 0
    private var fadeDistance: Double = 0
    private var rotationDegrees: Float = 0
    private var initialized = false
    private let cameraDistance: Float = 2048
    private var cellSize = 16
    private var minorInstability = true
    private var threeDFade = true
    private var rotate = false
    private var colors = [
        MatrixColor(r: 1, g: 1, b: 1),
        MatrixColor(r: 0, g: 1, b: 0),
        MatrixColor(r: 0, g: 1, b: 0)
    ]
    private var deterministicRandomState: UInt64?
    private var deterministicRandomLogRemaining = 0
    private var deterministicRandomCallIndex = 0

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        guard let device,
              let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: metalShaderSource, options: nil),
              let vertexFunction = library.makeFunction(name: "vertex_main"),
              let fragmentFunction = library.makeFunction(name: "fragment_main") else {
            fatalError("Metal is unavailable")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .ushort3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .uchar4Normalized
        vertexDescriptor.attributes[1].offset = 8
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .uchar2
        vertexDescriptor.attributes[2].offset = 6
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<CellVertex>.stride
        vertexDescriptor.layouts[0].stepFunction = .perInstance
        vertexDescriptor.layouts[0].stepRate = 1

        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipelineState = try! device.makeRenderPipelineState(descriptor: descriptor)

        let textureURL = Bundle(for: Matrix.self).url(forResource: "clean32", withExtension: "png")!
        glyphTexture = try! MTKTextureLoader(device: device).newTexture(URL: textureURL, options: [
            .allocateMipmaps: true,
            .generateMipmaps: true
        ])

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.normalizedCoordinates = true
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.maxAnisotropy = 16
        glyphSampler = device.makeSamplerState(descriptor: samplerDescriptor)!

        var offsets = [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 1),
            SIMD2<Float>(1, 1)
        ]
        vertexOffsetsBuffer = device.makeBuffer(bytes: &offsets, length: MemoryLayout<SIMD2<Float>>.stride * offsets.count)!
        self.commandQueue = commandQueue

        super.init(frame: frameRect, device: device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        isPaused = true
        enableSetNeedsDisplay = true
        delegate = self
        (layer as? CAMetalLayer)?.colorspace = nil
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makeMongolianGlyphTexture(device: MTLDevice) -> MTLTexture {
        let tileSize = 32
        let atlasTiles = 16
        let atlasSize = tileSize * atlasTiles
        let bytesPerPixel = 4
        let bytesPerRow = atlasSize * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: atlasSize * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        pixels.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(data: baseAddress,
                                          width: atlasSize,
                                          height: atlasSize,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: colorSpace,
                                          bitmapInfo: bitmapInfo) else { return }

            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: atlasSize, height: atlasSize))
            context.setShouldAntialias(true)
            context.setAllowsAntialiasing(true)

            let baseFont = CTFontCreateWithName("Noto Sans Mongolian" as CFString, 27, nil)
            let fallbackFont = CTFontCreateWithName("Mongolian Baiti" as CFString, 27, nil)
            let characters = mongolianGlyphCharacters()

            for index in 0..<(atlasTiles * atlasTiles) {
                let x = (index % atlasTiles) * tileSize
                let y = atlasSize - ((index / atlasTiles) + 1) * tileSize
                let character = characters[index % characters.count] as CFString
                let selectedFont = fontFor(character: character, baseFont: baseFont, fallbackFont: fallbackFont)
                let attributes: [CFString: Any] = [
                    kCTFontAttributeName: selectedFont,
                    kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
                ]
                let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, character, attributes as CFDictionary))
                let bounds = CTLineGetImageBounds(line, context)
                guard bounds.width > 0, bounds.height > 0 else { continue }

                let centerX = CGFloat(x) + CGFloat(tileSize) * 0.5
                let centerY = CGFloat(y) + CGFloat(tileSize) * 0.5
                let inset: CGFloat = 3
                let available = CGFloat(tileSize) - inset * 2
                let rotatedWidth = bounds.height
                let rotatedHeight = bounds.width
                let scale = min(available / max(rotatedWidth, 1), available / max(rotatedHeight, 1), 1)

                context.saveGState()
                context.translateBy(x: centerX, y: centerY)
                context.rotate(by: .pi / 2)
                context.scaleBy(x: scale, y: scale)
                context.textMatrix = .identity

                let drawX = -bounds.width * 0.5 - bounds.minX
                let drawY = -bounds.height * 0.5 - bounds.minY
                context.textPosition = CGPoint(x: drawX, y: drawY)
                CTLineDraw(line, context)
                context.restoreGState()
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                  width: atlasSize,
                                                                  height: atlasSize,
                                                                  mipmapped: false)
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)!
        texture.replace(region: MTLRegionMake2D(0, 0, atlasSize, atlasSize),
                        mipmapLevel: 0,
                        withBytes: pixels,
                        bytesPerRow: bytesPerRow)
        return texture
    }

    private static func mongolianGlyphCharacters() -> [String] {
        let scalars: [UnicodeScalar] = [
            "\u{1820}", "\u{1821}", "\u{1822}", "\u{1823}", "\u{1824}", "\u{1825}", "\u{1826}", "\u{1827}",
            "\u{1828}", "\u{1829}", "\u{182A}", "\u{182B}", "\u{182C}", "\u{182D}", "\u{182E}", "\u{182F}",
            "\u{1830}", "\u{1831}", "\u{1832}", "\u{1833}", "\u{1834}", "\u{1835}", "\u{1836}", "\u{1837}",
            "\u{1838}", "\u{1839}", "\u{183A}", "\u{183B}", "\u{183C}", "\u{183D}", "\u{183E}", "\u{183F}",
            "\u{1840}", "\u{1841}", "\u{1842}", "\u{1843}", "\u{1844}", "\u{1845}", "\u{1846}", "\u{1847}",
            "\u{1848}", "\u{1849}", "\u{184A}", "\u{184B}", "\u{184C}", "\u{184D}", "\u{184E}", "\u{184F}",
            "\u{1850}", "\u{1851}", "\u{1852}", "\u{1853}", "\u{1854}", "\u{1855}", "\u{1856}", "\u{1857}",
            "\u{1858}", "\u{1859}", "\u{185A}", "\u{185B}", "\u{185C}", "\u{185D}", "\u{185E}", "\u{185F}",
            "\u{1860}", "\u{1861}", "\u{1862}", "\u{1863}", "\u{1864}", "\u{1865}", "\u{1866}", "\u{1867}",
            "\u{1868}", "\u{1869}", "\u{186A}", "\u{186B}", "\u{186C}", "\u{186D}", "\u{186E}", "\u{186F}",
            "\u{1870}", "\u{1871}", "\u{1872}", "\u{1873}", "\u{1874}", "\u{1875}", "\u{1876}", "\u{1877}",
            "\u{1880}", "\u{1881}", "\u{1882}", "\u{1883}", "\u{1884}", "\u{1885}", "\u{1886}", "\u{1887}",
            "\u{1888}", "\u{1889}", "\u{188A}", "\u{188B}", "\u{188C}", "\u{188D}", "\u{188E}", "\u{188F}",
            "\u{1890}", "\u{1891}", "\u{1892}", "\u{1893}", "\u{1894}", "\u{1895}", "\u{1896}", "\u{1897}",
            "\u{1898}", "\u{1899}", "\u{189A}", "\u{189B}", "\u{189C}", "\u{189D}", "\u{189E}", "\u{189F}",
            "\u{18A0}", "\u{18A1}", "\u{18A2}", "\u{18A3}", "\u{18A4}", "\u{18A5}", "\u{18A6}", "\u{18A7}",
            "\u{18A8}", "\u{18A9}"
        ]
        return scalars.map { String($0) }
    }

    private static func fontSupports(font: CTFont, string: String) -> Bool {
        var unichars = Array(string.utf16)
        var glyphs = Array(repeating: CGGlyph(), count: unichars.count)
        return CTFontGetGlyphsForCharacters(font, &unichars, &glyphs, unichars.count)
    }

    private static func fontFor(character: CFString, baseFont: CTFont, fallbackFont: CTFont) -> CTFont {
        let length = CFStringGetLength(character)
        let resolvedFont = CTFontCreateForString(baseFont, character, CFRange(location: 0, length: length))
        if fontSupports(font: resolvedFont, string: character as String) {
            return resolvedFont
        }
        if fontSupports(font: fallbackFont, string: character as String) {
            return fallbackFont
        }
        return baseFont
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
        resetSimulation()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        updateDrawableSize()
        resetSimulation()
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        resetSimulation()
        super.viewDidChangeBackingProperties()
    }

    func applyPreferences(_ preferences: MatrixPreferences) {
        minorInstability = preferences.minorInstability
        threeDFade = preferences.threeDFade
        rotate = false
        cellSize = preferences.cellSize
        colors = preferences.colors
        resetSimulation()
    }

    func tick() {
        let expectedSize = expectedDrawableSize()
        if drawableSize != expectedSize {
            drawableSize = expectedSize
            resetSimulation()
        }
        ensureSimulation()
        stepSimulation()
    }

    private func updateDrawableSize() {
        drawableSize = expectedDrawableSize()
    }

    private func expectedDrawableSize() -> CGSize {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        return CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
    }

    func resetSimulation() {
        initialized = false
    }

    @objc func debugSetDeterministicSeed(_ seed: NSNumber) {
        deterministicRandomState = seed.uint64Value
        deterministicRandomLogRemaining = Int(ProcessInfo.processInfo.environment["MATRIX_DEBUG_RNG_LOG"] ?? "") ?? 0
        deterministicRandomCallIndex = 0
        resetSimulation()
    }

    @objc func debugRunTicks(_ ticks: NSNumber) {
        ensureSimulation()
        for _ in 0..<max(0, ticks.intValue) {
            stepSimulation()
        }
    }

    @objc func debugSnapshot() -> NSString {
        ensureSimulation()
        rebuildInstanceVertices()
        let vertices = instanceVertices
        var lines: [String] = []
        lines.append("core bytes=\(vertices.count * MemoryLayout<CellVertex>.stride) vertexCount=\(vertices.count)")
        lines.append(String(format: "dims width=%0.6f height=%0.6f rows=%d cols=%d cursorGroups=%d active=%d tick=%d fadeState=%d rotate=%0.6f fadeDistance=%0.6f cellSize=%d drawBytes=%d",
                            logicalWidth, logicalHeight, rows, columns, cursors.count, activeCellCount,
                            tickCount, fadeState, rotationDegrees, fadeDistance, cellSize,
                            vertices.count * MemoryLayout<CellVertex>.stride))
        lines.append(String(format: "flags rotate=%d 3DFade=%d minorInstability=%d colors=(%.4f %.4f %.4f),(%.4f %.4f %.4f),(%.4f %.4f %.4f)",
                            rotate ? 1 : 0, threeDFade ? 1 : 0, minorInstability ? 1 : 0,
                            colors[0].r, colors[0].g, colors[0].b,
                            colors[1].r, colors[1].g, colors[1].b,
                            colors[2].r, colors[2].g, colors[2].b))
        let vertexLimit = Int(ProcessInfo.processInfo.environment["MATRIX_DEBUG_VERTEX_LIMIT"] ?? "") ?? 16
        for (index, vertex) in vertices.prefix(vertexLimit).enumerated() {
            lines.append("v\(index) pos=(\(vertex.x) \(vertex.y) \(vertex.z)) tile=(\(vertex.texX) \(vertex.texY)) color=(\(vertex.r) \(vertex.g) \(vertex.b) \(vertex.a))")
        }
        lines.append("cellVector count=\(cells.count) cursorVector count=\(cursors.count)")
        let cellLimit = Int(ProcessInfo.processInfo.environment["MATRIX_DEBUG_CELL_LIMIT"] ?? "") ?? 12
        for (index, cell) in cells.prefix(cellLimit).enumerated() {
            lines.append(String(format: "cell%d glyph=%u phase=%d t08=%d t0c=0 wait=%d age=%d f18=%.4f color=(%.4f %.4f %.4f %.4f)",
                                index, cell.glyph, cell.phase, cell.phaseTicks, cell.waitTicks, cell.age,
                                cell.brightness, cell.color.x, cell.color.y, cell.color.z, cell.color.w))
        }
        for (index, cursor) in cursors.prefix(8).enumerated() {
            let minColumn = index * 4
            let maxColumn = min(columns - 1, index * 4 + 3)
            lines.append("cursor\(index) row=\(cursor.row) col=\(cursor.column) phase=\(cursor.phase) active=\(cursor.active ? 1 : 0) minCol=\(minColumn) maxCol=\(maxColumn) textLen=0 index=0 raw17=0")
        }
        return lines.joined(separator: "\n") as NSString
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        resetSimulation()
    }

    func draw(in view: MTKView) {
        ensureSimulation()
        render()
    }

    private func ensureSimulation() {
        guard !initialized else { return }
        initialized = true
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let width = max(1, Int(bounds.width))
        let height = max(1, Int(bounds.height))
        let backingWidth = max(1, Int(bounds.width * scale))
        let backingHeight = max(1, Int(bounds.height * scale))
        logicalWidth = Float(width)
        logicalHeight = Float(height)
        pixelWidth = Double(backingWidth)
        pixelHeight = Double(backingHeight)

        columns = max(1, Int(ceil(Double(width) / Double(cellSize))))
        rows = max(1, Int(ceil(Double(height) / Double(cellSize))))
        let remainder = columns & 3
        if remainder != 0 {
            columns += 4 - remainder
        }

        cells = Array(repeating: Cell(), count: rows * columns)
        cursors = Array(repeating: Cursor(), count: columns / 4)
        for index in cursors.indices {
            cursors[index].row = random(Int(max(1, rows)))
            cursors[index].column = randomClosed(index * 4, min(columns - 1, index * 4 + 3))
            cursors[index].phase = 4
            cursors[index].active = false
        }

        tickCount = 0
        fadeState = 0
        fadeDistance = 0
        rotationDegrees = 0
        activeCellCount = 0
        drawableSize = CGSize(width: backingWidth, height: backingHeight)

        for _ in 0..<max(rows, 1) {
            advanceCursors()
            ageExistingCells(fadeBrightnessSeed: randomUnit())
        }
        rebuildVisibleCells()
    }

    private func stepSimulation() {
        fadeDistance = 0
        let fadeBrightnessSeed = randomUnit()
        let previousTick = tickCount
        tickCount += 1

        if fadeState == 0, threeDFade, previousTick >= 9000 {
            fadeState = 1
            tickCount = 0
        } else if fadeState == 1, previousTick >= 120 {
            let d = pow(Double(previousTick - 119) * 0.5, 2)
            fadeDistance = d
            if d > Double(cameraDistance * 2) {
                fadeState = 0
                tickCount = 0
                fadeDistance = 0
                resetCursors()
            }
        }

        ageExistingCells(fadeBrightnessSeed: fadeBrightnessSeed)
        if fadeState != 1 {
            advanceCursors()
        }
        rebuildVisibleCells()

        rotationDegrees = 0
    }

    private func ageExistingCells(fadeBrightnessSeed: Float) {
        for index in cells.indices {
            guard cells[index].phase != 0 else { continue }

            if fadeState != 1 {
                cells[index].phaseTicks -= 1
                if cells[index].phaseTicks <= 0 {
                    cells[index].phase -= 1
                    if cells[index].phase > 0 {
                        cells[index].phaseTicks = phaseDuration(cells[index].phase)
                    }
                }
            }

            if cells[index].phase == 3, cells[index].phaseTicks < 0 {
                cells[index].phaseTicks = Int32(randomClosed(rows, max(rows, rows * 2)))
            }

            guard cells[index].phase != 0 else { continue }
            if fadeState == 1 {
                cells[index].brightness = (Float(cells[index].age) * fadeBrightnessSeed / 40) - (randomUnit() * 0.1)
                continue
            }

            if cells[index].age <= 119 {
                if cells[index].waitTicks > 0 {
                    cells[index].waitTicks -= 1
                } else {
                    let age = Int(cells[index].age)
                    if age > 3 {
                        cells[index].waitTicks = Int32(3 + random(max(1, age - 2)))
                    } else {
                        cells[index].waitTicks = Int32(age + random(max(1, 4 - age)))
                    }
                    cells[index].glyph = UInt8(random(0xa0) + 0x60)
                }
            }
        }
    }

    private func advanceCursors() {
        for index in cursors.indices {
            cursors[index].row += 1
            if cursors[index].row >= rows {
                cursors[index].row = 0
                cursors[index].column = randomClosed(index * 4, min(columns - 1, index * 4 + 3))
                cursors[index].active = true
            }

            let minColumn = index * 4
            let maxColumn = min(columns - 1, index * 4 + 3)
            if minorInstability {
                let jitter = (randomUnit() * 2) - 1
                if jitter < -0.95 {
                    if cursors[index].column > minColumn {
                        cursors[index].column -= 1
                    } else {
                        cursors[index].column += 1
                    }
                } else if jitter > 0.95 {
                    if cursors[index].column < maxColumn {
                        cursors[index].column += 1
                    } else {
                        cursors[index].column -= 1
                    }
                }
            }

            if randomUnit() > 0.99 {
                cursors[index].row = 0
                cursors[index].column = randomClosed(minColumn, maxColumn)
            }

            guard cursors[index].active else { continue }

            let initialCellIndex = cursors[index].row * columns + cursors[index].column
            guard initialCellIndex >= 0, initialCellIndex < cells.count else { continue }
            if cells[initialCellIndex].phase != 0 {
                let direction = (randomUnit() * 2) - 1
                if direction < 0, cursors[index].column > minColumn {
                    cursors[index].column -= 1
                } else if direction >= 0, cursors[index].column < maxColumn {
                    cursors[index].column += 1
                }
            }

            let cellIndex = cursors[index].row * columns + cursors[index].column
            guard cellIndex >= 0, cellIndex < cells.count else { continue }
            cells[cellIndex].phase = cursors[index].phase
            cells[cellIndex].phaseTicks = phaseDuration(cursors[index].phase)
            cells[cellIndex].glyph = UInt8(random(0xa0) + 0x60)
            let age = random(0x74) + 5
            cells[cellIndex].age = Int32(age)
            cells[cellIndex].brightness = 1
            cells[cellIndex].waitTicks = Int32(1 + random(age))
        }
    }

    private func rebuildVisibleCells() {
        activeCellCount = 0
        for index in cells.indices {
            guard cells[index].phase >= 1, cells[index].phase <= 4 else {
                cells[index].color = SIMD4<Float>(0, 0, 0, 1)
                continue
            }

            let t = Float(cells[index].phaseTicks) / Float(phaseDuration(cells[index].phase))
            let color: MatrixColor
            switch cells[index].phase {
            case 1:
                color = colors[2]
            case 2:
                color = colors[1].blend(t, with: colors[2])
            case 3:
                color = colors[1]
            case 4:
                color = colors[0].blend(t, with: colors[1])
            default:
                color = MatrixColor(r: 0, g: 0, b: 0)
            }
            let alpha = cells[index].phase == 1 ? t : 1
            cells[index].color = SIMD4<Float>(color.r * cells[index].brightness, color.g * cells[index].brightness, color.b * cells[index].brightness, alpha)
            activeCellCount += 1
        }
    }

    private func resetCursors() {
        for index in cells.indices {
            cells[index].phase = 0
            cells[index].glyph = 0
        }
        for index in cursors.indices {
            cursors[index].row = random(Int(max(1, rows)))
            cursors[index].column = randomClosed(index * 4, min(columns - 1, index * 4 + 3))
            cursors[index].phase = 4
            cursors[index].active = false
        }
    }

    private func render() {
        guard let descriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        rebuildInstanceVertices()
        let vertexBytes = instanceVertices.count * MemoryLayout<CellVertex>.stride
        frameSemaphore.wait()
        commandBuffer.addCompletedHandler { [frameSemaphore] _ in
            frameSemaphore.signal()
        }

        guard ensureInstanceBufferCapacity(vertexBytes),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            commandBuffer.commit()
            return
        }

        let vertexBuffer = instanceBuffers[frameIndex]
        frameIndex = (frameIndex + 1) % instanceBuffers.count
        if vertexBytes > 0 {
            instanceVertices.withUnsafeBytes { bytes in
                guard let source = bytes.baseAddress else { return }
                memcpy(vertexBuffer.contents(), source, vertexBytes)
            }
        }
        var uniforms = makeUniforms()

        encoder.setCullMode(.none)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: pixelWidth, height: pixelHeight, znear: 0, zfar: 1))
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(glyphTexture, index: 0)
        encoder.setFragmentSamplerState(glyphSampler, index: 0)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setVertexBuffer(vertexOffsetsBuffer, offset: 0, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instanceVertices.count)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func ensureInstanceBufferCapacity(_ requiredBytes: Int) -> Bool {
        guard requiredBytes > instanceBufferCapacity || instanceBuffers.isEmpty else { return true }
        let capacity = max(4096, max(requiredBytes, instanceBufferCapacity * 2))
        let buffers = (0..<3).compactMap { _ in
            device?.makeBuffer(length: capacity, options: .storageModeShared)
        }
        guard buffers.count == 3 else { return false }
        instanceBuffers = buffers
        instanceBufferCapacity = capacity
        frameIndex = 0
        return true
    }

    private func rebuildInstanceVertices() {
        instanceVertices.removeAll(keepingCapacity: true)
        instanceVertices.reserveCapacity(activeCellCount)
        for row in 0..<rows {
            for column in 0..<columns {
                let cell = cells[row * columns + column]
                guard cell.phase != 0 else { continue }
                let glyph = Int(cell.glyph)
                let z = depthFor(cell)
                let color = byteColor(cell.color)
                instanceVertices.append(CellVertex(
                    x: UInt16(clamping: column),
                    y: UInt16(clamping: row),
                    z: z,
                    texX: UInt8((glyph >> 4) & 15),
                    texY: UInt8(glyph & 15),
                    r: color.0,
                    g: color.1,
                    b: color.2,
                    a: color.3
                ))
            }
        }
    }

    private func depthFor(_ cell: Cell) -> UInt16 {
        guard cell.phase == 1, threeDFade else { return 0 }
        let duration: Int32 = 32
        let progress = max(0, Float(duration - cell.phaseTicks) / Float(duration))
        let depth = Int((progress * 32) * (progress * 32) * 0.5)
        return UInt16(clamping: depth)
    }

    private func byteColor(_ color: SIMD4<Float>) -> (UInt8, UInt8, UInt8, UInt8) {
        func convert(_ value: Float) -> UInt8 {
            UInt8(clamping: Int(max(0, min(1, value)) * 255))
        }
        return (convert(color.x), convert(color.y), convert(color.z), convert(color.w))
    }

    private func makeUniforms() -> Uniforms {
        Uniforms(gridSize: SIMD2<Float>(max(1, Float(columns)), max(1, Float(rows))), depthScale: 1.0 / 8192.0)
    }

    private func phaseDuration(_ phase: Int32) -> Int32 {
        switch phase {
        case 1: return 32
        case 2: return 8
        case 3: return -1
        case 4: return 4
        default: return 1
        }
    }

    private func random(_ upperBound: Int) -> Int {
        guard upperBound > 1 else { return 0 }
        if deterministicRandomState != nil {
            let raw = nextDeterministicRandom()
            let value = raw % UInt32(upperBound)
            if deterministicRandomLogRemaining > 0 {
                fputs("rng \(deterministicRandomCallIndex) uniform(\(upperBound)) raw=\(raw) -> \(value)\n", stderr)
            }
            return Int(value)
        }
        return Int(arc4random_uniform(UInt32(upperBound)))
    }

    private func randomClosed(_ a: Int, _ b: Int) -> Int {
        let lo = min(a, b)
        let hi = max(a, b)
        return lo + random(hi - lo + 1)
    }

    private func randomUnit() -> Float {
        if deterministicRandomState != nil {
            return Float(nextDeterministicRandom()) * 2.3283064e-10
        }
        return Float(arc4random()) * 2.3283064e-10
    }

    private func nextDeterministicRandom() -> UInt32 {
        let next = (deterministicRandomState ?? 0)
            &* 6364136223846793005
            &+ 1442695040888963407
        deterministicRandomState = next
        let value = UInt32(truncatingIfNeeded: next >> 32)
        if deterministicRandomLogRemaining > 0 {
            deterministicRandomCallIndex += 1
            fputs("rng \(deterministicRandomCallIndex) arc4random -> \(value)\n", stderr)
            deterministicRandomLogRemaining -= 1
        }
        return value
    }
}

private let metalShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    ushort3 position [[attribute(0)]];
    float4 color [[attribute(1)]];
    uchar2 texCoord [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 uv;
};

struct Uniforms {
    float2 gridSize;
    float depthScale;
    float padding;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant Uniforms &uniforms [[buffer(1)]],
                             constant float2 *offsets [[buffer(2)]],
                             uint vertexID [[vertex_id]])
{
    float2 corner = offsets[vertexID & 3];
    float2 cellPosition = float2(in.position.xy) + corner;
    float2 clipPosition = float2((cellPosition.x / uniforms.gridSize.x) * 2.0 - 1.0,
                                 1.0 - (cellPosition.y / uniforms.gridSize.y) * 2.0);
    float depth = clamp(float(in.position.z) * uniforms.depthScale, 0.0, 0.99);

    VertexOut out;
    out.position = float4(clipPosition, depth, 1.0);
    out.color = in.color;
    out.uv = (float2(in.texCoord) + corner) / 16.0;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> glyphs [[texture(0)]],
                              sampler glyphSampler [[sampler(0)]])
{
    float alpha = glyphs.sample(glyphSampler, in.uv).r;
    if (alpha == 0.0) {
        discard_fragment();
    }
    return float4(in.color.rgb, in.color.a * alpha);
}
"""
