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

import Foundation
@testable import FoundationInternationalization

/// Collation data that only the tests use, in the test bundle (`TestData/`); the library ships only the data it needs, compiled in.
enum CollationTestData {
    /// The NFD-only root data (genuca -X variant: no canonical closure, no Hangul syllable mappings; it needs the NFD front end), parsed once per test process. The conformance and differential tests run it next to the bundled root data.
    static func rootNFDOnly() throws -> CollationData { try nfdOnly.get() }

    private static let nfdOnly = Result { () throws -> CollationData in
        // The folder first, then the file, as the Golden and Conformance tests find theirs (a lookup with `subdirectory:` did not find it).
        guard let folder = Bundle.module.url(forResource: "TestData", withExtension: nil) else {
            throw CollationData.ParseError.missingPart("TestData in the test bundle")
        }
        return try CollationData(contentsOf: folder.appendingPathComponent("ucadata-nfd-only.icu"))
    }
}
