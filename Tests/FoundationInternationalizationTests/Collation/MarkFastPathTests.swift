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

import Testing
#if canImport(FoundationEssentials)
@testable import FoundationEssentials
@testable import FoundationInternationalization
#elseif FOUNDATION_FRAMEWORK
@testable import Foundation
#endif

/// The combining-mark fast path of CE production against the full path: an iterator with the fast tables takes the mark table, one without tables takes `lookup` + `appendCEs`. For every code point U+0300–037F after a set of base letters, alone, and followed by a second mark (which NFD may reorder), both must give the same CEs and scalar count — on root and on every bundled tailoring, where some marks are tailored or start contractions.
@Suite struct MarkFastPathTests {
    static let bases = ["", "a", "e", "o", "u", "c", "s", "z", "A", "ø", "α", "ä"]

    static func strings() -> [String] {
        var all: [String] = []
        for m: UInt32 in 0x0300...0x037F {
            guard let mark = Unicode.Scalar(m) else { continue }
            for b in bases {
                all.append(b + String(Character(mark)))
                all.append(b + String(mark) + "\u{0323}")  // dot below, ccc 220: reorders before ccc 230 marks
                all.append(b + String(mark) + "x")
            }
        }
        return all
    }

    static func mismatches(_ collator: RootCollator, _ strings: [String]) throws -> [String] {
        var fast = CEIterator(
            data: collator.data, base: collator.base, norm: collator.norm, numeric: false, scalars: "".unicodeScalars,
            simpleCEs: collator.simpleCEs, thaiCEs: collator.thaiCEs,
            simpleCEsWithDigits: collator.simpleCEsWithDigits, thaiCEsWithDigits: collator.thaiCEsWithDigits,
            markCEs: collator.markCEs)
        var full = CEIterator(
            data: collator.data, base: collator.base, norm: collator.norm, numeric: false, scalars: "".unicodeScalars)
        var found: [String] = []
        for s in strings {
            fast.reset(numeric: false, scalars: s.unicodeScalars)
            full.reset(numeric: false, scalars: s.unicodeScalars)
            try fast.collectAll()
            try full.collectAll()
            if fast.ces.toArray() != full.ces.toArray() || fast.scalarsConsumed != full.scalarsConsumed {
                found.append(s.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "))
            }
        }
        return found
    }

    @Test func rootAgreesWithTheFullPath() throws {
        let collator = try RootCollator()
        try #require(!collator.markCEs.isEmpty)
        let found = try Self.mismatches(collator, Self.strings() + (try ASCIIRunTests.strings()))
        #expect(found.isEmpty, "\(found.count) mismatches, first: \(found.prefix(8))")
    }

    @Test(arguments: RestartSafetyTests.tailorings)
    func tailoringAgreesWithTheFullPath(name: String) throws {
        let found = try Self.mismatches(try RootCollator(tailoringNamed: name), Self.strings())
        #expect(found.isEmpty, "\(name): \(found.count) mismatches, first: \(found.prefix(8))")
    }
}
