import ApplicationServices
import AppKit

/// A thin, typed wrapper around `AXUIElement`.
///
/// Every element made through this type carries a messaging timeout, so a hung
/// target app can stall a read for at most `AXElement.timeout` seconds.
public struct AXElement {
    public static let timeout: Float = 0.5

    public let raw: AXUIElement

    public init(_ raw: AXUIElement) {
        self.raw = raw
        AXUIElementSetMessagingTimeout(raw, AXElement.timeout)
    }

    public static func application(pid: pid_t) -> AXElement {
        AXElement(AXUIElementCreateApplication(pid))
    }

    public static var systemWide: AXElement {
        AXElement(AXUIElementCreateSystemWide())
    }

    /// A timeout set on the system-wide element becomes the default for every element in
    /// this process, including those SelectedTextKit creates. Call once at launch.
    public static func applyGlobalTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), timeout)
    }

    // MARK: Reading

    /// The raw value of an attribute, or nil when the app does not provide it.
    public func value(_ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(raw, attribute as CFString, &result)
        return error == .success ? result : nil
    }

    public func value(_ attribute: String, parameter: CFTypeRef) -> CFTypeRef? {
        var result: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(raw, attribute as CFString, parameter, &result)
        return error == .success ? result : nil
    }

    public func string(_ attribute: String) -> String? {
        value(attribute) as? String
    }

    public func element(_ attribute: String) -> AXElement? {
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXElement(value as! AXUIElement)
    }

    public func url(_ attribute: String) -> URL? {
        switch value(attribute) {
        case let url as URL: return url
        case let string as String: return URL(string: string)
        default: return nil
        }
    }

    public func isSettable(_ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        let error = AXUIElementIsAttributeSettable(raw, attribute as CFString, &settable)
        return error == .success && settable.boolValue
    }

    @discardableResult
    public func set(_ attribute: String, to value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(raw, attribute as CFString, value) == .success
    }

    // MARK: Common attributes

    public var role: String? { string(kAXRoleAttribute) }
    public var subrole: String? { string(kAXSubroleAttribute) }
    public var title: String? { string(kAXTitleAttribute) }
    public var parent: AXElement? { element(kAXParentAttribute) }

    /// The element's frame in top-left-origin screen points.
    public var frame: CGRect? {
        guard
            let position = value(kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
            let size = value(kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    public var children: [AXElement] {
        (value(kAXChildrenAttribute) as? [AXUIElement])?.map(AXElement.init) ?? []
    }

    public var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(raw, &pid) == .success ? pid : nil
    }

    /// Walks up the parent chain, starting with this element, until `match` holds.
    public func firstAncestor(maxDepth: Int = 64, where match: (AXElement) -> Bool) -> AXElement? {
        var current: AXElement? = self
        var depth = 0
        while let element = current, depth < maxDepth {
            if match(element) { return element }
            current = element.parent
            depth += 1
        }
        return nil
    }
}

// MARK: AXValue conversions

extension AXElement {
    public static func range(from value: CFTypeRef?) -> CFRange? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    public static func rect(from value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    public static func value(of range: CFRange) -> AXValue {
        var copy = range
        return AXValueCreate(.cfRange, &copy)!
    }
}
