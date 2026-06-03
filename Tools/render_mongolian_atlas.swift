import AppKit
import CoreText

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/clean32.png"
let tileSize = 32
let atlasTiles = 16
let atlasSize = tileSize * atlasTiles
let bytesPerPixel = 4
let bytesPerRow = atlasSize * bytesPerPixel
var pixels = [UInt8](repeating: 0, count: atlasSize * bytesPerRow)

func mongolianGlyphCharacters() -> [String] {
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

func fontSupports(font: CTFont, string: String) -> Bool {
    var unichars = Array(string.utf16)
    var glyphs = Array(repeating: CGGlyph(), count: unichars.count)
    return CTFontGetGlyphsForCharacters(font, &unichars, &glyphs, unichars.count)
}

func fontFor(character: CFString, baseFont: CTFont, fallbackFont: CTFont) -> CTFont {
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

func glyphFor(character: String, font: CTFont) -> CGGlyph? {
    var unichars = Array(character.utf16)
    var glyphs = Array(repeating: CGGlyph(), count: unichars.count)
    guard CTFontGetGlyphsForCharacters(font, &unichars, &glyphs, unichars.count),
          let glyph = glyphs.first,
          glyph != 0 else { return nil }
    return glyph
}

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
                                  bitmapInfo: bitmapInfo) else { fatalError("unable to create CGContext") }

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
        let characterString = characters[index % characters.count]
        let character = characterString as CFString
        let selectedFont = fontFor(character: character, baseFont: baseFont, fallbackFont: fallbackFont)
        guard var glyph = glyphFor(character: characterString, font: selectedFont) else { continue }

        let bounds = CTFontGetBoundingRectsForGlyphs(selectedFont, .default, &glyph, nil, 1)
        guard bounds.width > 0, bounds.height > 0 else { continue }

        let centerX = CGFloat(x) + CGFloat(tileSize) * 0.5
        let centerY = CGFloat(y) + CGFloat(tileSize) * 0.5
        let inset: CGFloat = 1
        let available = CGFloat(tileSize) - inset * 2
        let rotatedWidth = bounds.height
        let rotatedHeight = bounds.width
        let scale = min(available / max(rotatedWidth, 1), available / max(rotatedHeight, 1), 1)

        context.saveGState()
        context.clip(to: CGRect(x: x, y: y, width: tileSize, height: tileSize).insetBy(dx: 1, dy: 1))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.translateBy(x: centerX, y: centerY)
        context.rotate(by: .pi * 1.5)
        context.scaleBy(x: scale, y: scale)
        context.textMatrix = .identity
        let basePosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        let boldOffsets: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0.45, y: 0),
            CGPoint(x: -0.45, y: 0),
            CGPoint(x: 0, y: 0.45),
            CGPoint(x: 0, y: -0.45)
        ]
        for offset in boldOffsets {
            var position = CGPoint(x: basePosition.x + offset.x, y: basePosition.y + offset.y)
            CTFontDrawGlyphs(selectedFont, &glyph, &position, 1, context)
        }
        context.restoreGState()
    }
}

let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                              pixelsWide: atlasSize,
                              pixelsHigh: atlasSize,
                              bitsPerSample: 8,
                              samplesPerPixel: 4,
                              hasAlpha: true,
                              isPlanar: false,
                              colorSpaceName: .deviceRGB,
                              bytesPerRow: bytesPerRow,
                              bitsPerPixel: 32)!
memcpy(bitmap.bitmapData!, pixels, pixels.count)
let data = bitmap.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: outputPath))
