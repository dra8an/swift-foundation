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

// The system Foundation, for `Bundle`. This import stays out of BenchmarkCollation.swift: there, it would let the collation calls resolve to the system implementation instead of the package's.
import Foundation

/// The path of a collation corpus (one string per line) in the target's resources.
func collationCorpusPath(_ name: String) -> String? {
    Bundle.module.url(forResource: name, withExtension: "txt")?.path
}
