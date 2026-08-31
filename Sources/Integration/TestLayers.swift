import Foundation

/// Recommended autotest pyramid layer names (not enforced; any non-empty string is valid).
public enum TestLayers {
    public static let E2E = "E2E"
    public static let UI = "UI"
    public static let API = "API"
    public static let CONTRACT = "Contract"
    public static let INTEGRATION = "Integration"
    public static let COMPONENT = "Component"
    public static let UNIT = "Unit"
}
