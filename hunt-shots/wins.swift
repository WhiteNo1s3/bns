import Cocoa
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in info {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let num = w[kCGWindowNumber as String] as? Int ?? 0
    let name = w[kCGWindowName as String] as? String ?? ""
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print("\(owner)\t\(num)\t\(name)\t\(b)")
}
