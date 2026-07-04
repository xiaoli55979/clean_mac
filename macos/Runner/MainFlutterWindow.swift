import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 1080, height: 700))
    self.minSize = NSSize(width: 880, height: 560)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    setUpIconChannel(flutterViewController)

    super.awakeFromNib()
  }

  // 返回指定路径的 Finder 图标 PNG 数据
  private func setUpIconChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "clean_mac/icons", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "appIcon",
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      let dimension = (args["size"] as? NSNumber)?.intValue ?? 64
      let icon = NSWorkspace.shared.icon(forFile: path)
      guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: dimension, pixelsHigh: dimension,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        result(nil)
        return
      }
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
      icon.draw(
        in: NSRect(x: 0, y: 0, width: dimension, height: dimension),
        from: .zero, operation: .copy, fraction: 1.0)
      NSGraphicsContext.restoreGraphicsState()
      if let png = rep.representation(using: .png, properties: [:]) {
        result(FlutterStandardTypedData(bytes: png))
      } else {
        result(nil)
      }
    }
  }
}
