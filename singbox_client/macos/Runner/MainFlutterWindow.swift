import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let mobileSize = NSSize(width: 390, height: 844)
    let screenFrame = NSScreen.main?.visibleFrame ?? self.frame
    let origin = NSPoint(
      x: screenFrame.midX - (mobileSize.width / 2),
      y: screenFrame.midY - (mobileSize.height / 2)
    )
    let windowFrame = NSRect(origin: origin, size: mobileSize)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = mobileSize
    self.maxSize = mobileSize
    self.styleMask.remove(.resizable)
    self.delegate = self
    self.standardWindowButton(.zoomButton)?.isHidden = true
    self.standardWindowButton(.zoomButton)?.isEnabled = false

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.miniaturize(nil)
    return false
  }
}
