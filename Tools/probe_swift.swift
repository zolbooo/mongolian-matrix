import Cocoa
import ScreenSaver

let args = CommandLine.arguments
let bundlePath = args.count > 1 ? args[1] : "build/Matrix.saver"
let ticks = args.count > 2 ? Int(args[2]) ?? 1 : 1
let width = args.count > 3 ? Double(args[3]) ?? 320 : 320
let height = args.count > 4 ? Double(args[4]) ?? 200 : 200
let scale = args.count > 5 ? Double(args[5]) ?? 1 : 1
let seedText = args.count > 6 ? args[6] : "0x1234"
let seed: UInt64
if seedText.hasPrefix("0x") || seedText.hasPrefix("0X") {
    seed = UInt64(seedText.dropFirst(2), radix: 16) ?? 0x1234
} else {
    seed = UInt64(seedText, radix: 10) ?? 0x1234
}

guard let bundle = Bundle(path: bundlePath), bundle.load(),
      let saverClass = bundle.principalClass as? ScreenSaverView.Type,
      let saver = saverClass.init(frame: NSRect(x: 0, y: 0, width: width, height: height), isPreview: true) else {
    fatalError("unable to load saver at \(bundlePath)")
}

saver.window?.setFrame(NSRect(x: 0, y: 0, width: width * scale, height: height * scale), display: false)
guard let metalView = saver.subviews.first else {
    fatalError("saver has no render subview")
}

let seedSelector = Selector(("debugSetDeterministicSeed:"))
let runSelector = Selector(("debugRunTicks:"))
let snapshotSelector = Selector(("debugSnapshot"))
guard metalView.responds(to: seedSelector),
      metalView.responds(to: runSelector),
      metalView.responds(to: snapshotSelector) else {
    fatalError("render subview does not expose debug probe selectors")
}

_ = metalView.perform(seedSelector, with: NSNumber(value: seed))
_ = metalView.perform(runSelector, with: NSNumber(value: ticks))
if let result = metalView.perform(snapshotSelector)?.takeUnretainedValue() as? NSString {
    print(result)
} else {
    fatalError("debug snapshot returned no text")
}
