//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if canImport(FoundationEssentials)
@testable import FoundationEssentials
@testable import FoundationInternationalization
#elseif FOUNDATION_FRAMEWORK
@testable import Foundation
#endif

#if os(macOS)
import class Foundation.Bundle
#endif

/// A folder of the test resources (`Golden`, `Conformance`, `TestData`), found as FoundationEssentialsTests finds its resources (`testData(forResource:)`): through `Bundle.module` on macOS, and elsewhere in the resource folder that SwiftPM puts next to the test executable.
func collationTestFolder(_ name: String) -> URL? {
#if os(macOS)
    guard let url = Bundle.module.url(forResource: name, withExtension: nil) else { return nil }
    return URL(filePath: url.path, directoryHint: .isDirectory)
#else
    // On Linux the tests are built for the host, because there are macro tests; on Windows only for the target. So the `-tool` folder is tried first.
    let executableFolder = URL(filePath: ProcessInfo.processInfo.arguments[0]).deletingLastPathComponent()
    for resources in ["swift-foundation_FoundationInternationalizationTests-tool.resources", "swift-foundation_FoundationInternationalizationTests.resources"] {
        let folder = executableFolder.appending(component: resources, directoryHint: .isDirectory).appending(component: name, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: folder.path) { return folder }
    }
    return nil
#endif
}

/// Collation data that only the tests use, in the test bundle (`TestData/`); the library ships only the data it needs, compiled in.
enum CollationTestData {
    /// The NFD-only root data (genuca -X variant: no canonical closure, no Hangul syllable mappings; it needs the NFD front end), parsed once per test process. The conformance and differential tests run it next to the bundled root data.
    static func rootNFDOnly() throws -> CollationData { try nfdOnly.get() }

    private static let nfdOnly = Result { () throws -> CollationData in
        // The folder first, then the file, as the Golden and Conformance tests find theirs (a lookup with `subdirectory:` did not find it).
        guard let folder = collationTestFolder("TestData") else {
            throw CollationData.ParseError.missingPart("TestData in the test bundle")
        }
        return try CollationData(contentsOf: folder.appendingPathComponent("ucadata-nfd-only.icu"))
    }
}

extension StringProtocol {
    /// The string without leading and trailing white space: tab and the space separators (general category Zs), the set of `CharacterSet.whitespaces`.
    func trimmingWhitespace() -> String {
        func isWhitespace(_ s: Unicode.Scalar) -> Bool { s == "\t" || s.properties.generalCategory == .spaceSeparator }
        let scalars = unicodeScalars
        guard let first = scalars.firstIndex(where: { !isWhitespace($0) }),
              let last = scalars.lastIndex(where: { !isWhitespace($0) }) else { return "" }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: scalars[first...last])
        return String(result)
    }
}

extension Sequence where Element == UInt8 {
    /// The bytes as lowercase hex digits, two per byte.
    var lowercaseHex: String {
        let digits = Array("0123456789abcdef".unicodeScalars)
        var result = String.UnicodeScalarView()
        for byte in self {
            result.append(digits[Int(byte >> 4)])
            result.append(digits[Int(byte & 0xf)])
        }
        return String(result)
    }
}
