import AppKit
import ApplicationServices

/// Private but long-stable API used by most window managers to map an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    func rawAttribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ name: String) -> String? {
        rawAttribute(name) as? String
    }

    func bool(_ name: String) -> Bool? {
        (rawAttribute(name) as? NSNumber)?.boolValue
    }

    func elements(_ name: String) -> [AXUIElement] {
        guard let value = rawAttribute(name), CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as! [AnyObject]).compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    func element(_ name: String) -> AXUIElement? {
        guard let value = rawAttribute(name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func url(_ name: String) -> URL? {
        guard let value = rawAttribute(name), CFGetTypeID(value) == CFURLGetTypeID() else { return nil }
        return (value as! CFURL) as URL
    }

    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var title: String? { string(kAXTitleAttribute) }

    /// Frame in AX coordinates (origin at the top-left of the primary screen).
    var axFrame: CGRect? {
        guard let posValue = rawAttribute(kAXPositionAttribute), CFGetTypeID(posValue) == AXValueGetTypeID(),
              let sizeValue = rawAttribute(kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(self, &id) == .success, id != 0 else { return nil }
        return id
    }

    @discardableResult
    func set(_ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, name as CFString, value) == .success
    }

    @discardableResult
    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(self, action as CFString) == .success
    }
}

enum ScreenGeometry {
    /// Converts a rect from AX/CoreGraphics coordinates (top-left origin) to Cocoa coordinates (bottom-left origin).
    static func cocoaRect(fromAX rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
