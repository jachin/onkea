import Foundation

/// The minimum required Hugo version for compatibility checks.
/// e.g., "0.158.0"
public let minimumHugoVersion = HugoVersion(major: 0, minor: 158, patch: 0)

// Represents a semantic version for Hugo (e.g., v0.158.0)
public struct HugoVersion: Comparable, Equatable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: HugoVersion, rhs: HugoVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ string: String) {
        var str = string
        if str.hasPrefix("v") { str.removeFirst() }
        let comps = str.split(separator: ".", omittingEmptySubsequences: false)
        guard comps.count >= 3 else { return nil }
        self.major = Int(comps[0]) ?? 0
        self.minor = Int(comps[1]) ?? 0
        // Support trailing + or other build info after patch
        let patchPart = comps[2].split(separator: "+").first ?? comps[2]
        self.patch = Int(patchPart) ?? 0
    }
    
    public var versionString: String { description }
}

// Enum representing the state of Hugo on the system
public enum HugoStatus: Equatable {
    case checking
    case notInstalled
    case incompatibleVersion(found: HugoVersion)
    case compatible
}
