//
//  HostArchitecture.swift
//  WhiskyKit
//

import Darwin

/// The physical Mac architecture, intentionally independent of this process's slice.
///
/// A Universal Bourbon process can itself be running under Rosetta, so `#if arch(...)`
/// cannot answer whether an x86_64 BourbonWine needs Rosetta. `hw.optional.arm64`
/// describes the hardware instead.
public enum HostArchitecture: Equatable, Sendable {
    case appleSilicon
    case intel

    public static let current = detect(arm64Hardware: readArm64HardwareCapability())

    public var requiresRosettaForX86Runtime: Bool {
        self == .appleSilicon
    }

    static func detect(arm64Hardware: Int32?) -> HostArchitecture {
        arm64Hardware == 1 ? .appleSilicon : .intel
    }

    private static func readArm64HardwareCapability() -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 ? value : nil
    }
}
