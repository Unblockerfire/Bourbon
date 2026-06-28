//
//  InstallerAnalysis.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation

public enum InstallerTechnology: String, Codable, Hashable, Sendable {
    case nsis = "NSIS"
    case innoSetup = "Inno Setup"
    case msi = "MSI"
    case installShield = "InstallShield"
    case squirrel = "Squirrel"
    case electron = "Electron"
    case chromium = "Chromium"
    case cef = "CEF"
    case steamWebView = "Steam webview"
    case portableExecutable = "Portable executable"
    case unknown = "Unknown"
}
public struct InstallerAnalysis: Sendable {
    public let url: URL
    public let technologies: Set<InstallerTechnology>
    public let architecture: Architecture
    public let peType: String
    public let payloadHints: Set<String>
    public let cacheKey: String

    public var isWindowsInstaller: Bool {
        technologies.contains(.msi)
            || technologies.contains(.nsis)
            || technologies.contains(.innoSetup)
            || technologies.contains(.installShield)
            || technologies.contains(.squirrel)
    }

    public var isPortableExecutable: Bool {
        technologies.contains(.portableExecutable)
    }
}
