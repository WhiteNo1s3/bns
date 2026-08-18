import ApplicationServices
import AppKit
import Foundation

func kids(_ e: AXUIElement) -> [AXUIElement] {
    var raw: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &raw)
    if err != .success { return [] }
    return raw as? [AXUIElement] ?? []
}
func attr(_ e: AXUIElement, _ k: String) -> String {
    var raw: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(e, k as CFString, &raw)
    if err != .success { return "" }
    return String(describing: raw!)
}
func walk(_ e: AXUIElement, _ depth: Int) {
    let role = attr(e, kAXRoleAttribute as String)
    let title = attr(e, kAXTitleAttribute as String)
    let val = attr(e, kAXValueAttribute as String)
    let desc = attr(e, kAXDescriptionAttribute as String)
    let help = attr(e, kAXHelpAttribute as String)
    let pad = String(repeating: "  ", count: depth)
    var bits = [role]
    if !title.isEmpty && title != "Optional(nil)" { bits.append("t="+title) }
    if !val.isEmpty && val != "Optional(nil)" && val.count < 80 { bits.append("v="+val) }
    if !desc.isEmpty && desc != "Optional(nil)" { bits.append("d="+desc) }
    if !help.isEmpty && help != "Optional(nil)" { bits.append("h="+help) }
    print(pad + bits.joined(separator: " | "))
    if depth < 12 {
        for c in kids(e) { walk(c, depth+1) }
    }
}

let wanted = CommandLine.arguments.dropFirst().first ?? "bns"
let apps = NSWorkspace.shared.runningApplications
guard let app = apps.first(where: { ($0.localizedName ?? "").lowercased() == wanted.lowercased() || ($0.bundleIdentifier ?? "").contains(wanted) }) else {
    fputs("no app \(wanted)\n", stderr)
    for a in apps { print("APP", a.localizedName ?? "?", a.processIdentifier) }
    exit(2)
}
print("APP", app.localizedName ?? "?", app.processIdentifier, app.bundleIdentifier ?? "")
let ax = AXUIElementCreateApplication(app.processIdentifier)
walk(ax, 0)
