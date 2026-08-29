//
//  RuntimeWineBinary.swift
//  WhiskyKit
//

import Foundation

enum RuntimeWineBinary {
    /// Resolve the Wine launcher shipped by an installed runtime.
    ///
    /// The production BourbonWine archive exposes `wine`. Prefer that canonical
    /// launcher and fall back to `wine64` only for supported alternate runtimes.
    static func resolve(
        in binFolder: URL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        let wine = binFolder.appending(path: "wine")
        if fileExists(wine.path(percentEncoded: false)) {
            return wine
        }

        let wine64 = binFolder.appending(path: "wine64")
        if fileExists(wine64.path(percentEncoded: false)) {
            return wine64
        }

        return wine
    }
}
