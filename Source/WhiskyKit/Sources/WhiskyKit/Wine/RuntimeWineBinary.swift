//
//  RuntimeWineBinary.swift
//  WhiskyKit
//

import Foundation

enum RuntimeWineBinary {
    /// Resolve the Wine launcher shipped by an installed runtime.
    ///
    /// Some Wine distributions expose `wine64`, while the current BourbonWine
    /// archive exposes `wine`. Prefer `wine64` when both exist, but never point
    /// the application at a launcher that is absent from the installed archive.
    static func resolve(
        in binFolder: URL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        let wine64 = binFolder.appending(path: "wine64")
        if fileExists(wine64.path(percentEncoded: false)) {
            return wine64
        }

        return binFolder.appending(path: "wine")
    }
}
