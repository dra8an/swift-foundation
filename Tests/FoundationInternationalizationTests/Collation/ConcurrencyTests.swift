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

import Dispatch
import Testing
import FoundationEssentials
@testable import FoundationInternationalization

/// Collators are shared across threads: CollatorCache hands the same RootCollator to every thread. These tests run compare, sortKey and search on shared collators from many threads at once — with the threads using different option sets in different orders, so the single-slot fast-Latin cache for non-default options changes under them — and check every answer against one computed on a single thread first. They also create collators concurrently. Run them under Thread Sanitizer too: `swift test --sanitize=thread --filter CollationConcurrencyTests` (technique log §51).
@Suite struct CollationConcurrencyTests {
    /// One failure counter per iteration; each iteration writes only its own slot.
    final class Counters: @unchecked Sendable {
        let slots: UnsafeMutableBufferPointer<Int>
        init(_ count: Int) {
            slots = .allocate(capacity: count)
            slots.initialize(repeating: 0)
        }
        deinit { slots.deallocate() }
        var total: Int { slots.reduce(0, +) }
    }

    static let strings: [String] = [
        "apple", "Apple", "APPLE", "apples", "applesauce", "banana", "bañana", "Banana",
        "co-op", "coop", "co op", "résumé", "resume", "re\u{301}sume\u{301}", "Résumé",
        "naïve", "naive", "straße", "strasse", "Æsir", "aesir", "ångström", "angstrom",
        "item9", "item10", "item010", "v1.2.10", "v1.2.9", "/usr/lib/libc.dylib", "/usr/lib/libz.1.dylib",
        "/usr/local/bin/swift", "/usr/local/bin/swiftc", "東京", "京都", "大阪", "東京都", "中文",
        "กข", "กค", "เก", "แก", "กา", "ก่า", "ภาษาไทย", "ภาษาอังกฤษ",
        "한국어", "한글", "Ελληνικά", "ελληνικα", "Русский", "русский", "Ёлка", "елка",
        "a\u{0323}\u{0302}", "a\u{0302}\u{0323}", "ệ", "l·l", "L·L", "", " ", "!", "123", "１２３",
    ]

    static let optionSets: [CollationOptions] = {
        var sets: [CollationOptions] = [CollationOptions()]
        var numeric = CollationOptions(); numeric.numeric = true; sets.append(numeric)
        var shifted = CollationOptions(); shifted.alternate = .shifted; sets.append(shifted)
        var primary = CollationOptions(); primary.strength = .primary; sets.append(primary)
        var identical = CollationOptions(); identical.strength = .identical; sets.append(identical)
        var upper = CollationOptions(); upper.caseFirst = .upperFirst; upper.caseLevel = true; sets.append(upper)
        var backwards = CollationOptions(); backwards.backwardSecondary = true; sets.append(backwards)
        return sets
    }()

    static let tailorings = ["th", "sv", "ja", "fr_CA"]

    /// Every answer one (collator, option set) pair gives: compares of adjacent and strided pairs, sort keys, contains.
    struct Answers: Equatable {
        var compares: [RootCollator.Order] = []
        var keys: [[UInt8]] = []
        var contains: [Bool] = []
    }

    static func answers(_ collator: RootCollator, _ options: CollationOptions) throws -> Answers {
        var a = Answers()
        let n = strings.count
        for i in 0..<n {
            a.compares.append(try collator.compare(strings[i], strings[(i + 1) % n], options: options))
            a.compares.append(try collator.compare(strings[i], strings[(i * 7 + 3) % n], options: options))
            a.keys.append(try collator.sortKey(for: strings[i], options: options))
            let text = strings[i] + " " + strings[(i + 5) % n]
            a.contains.append(collator.contains(pattern: strings[(i + 5) % n], in: text, options: options))
        }
        return a
    }

    static func makeCollators() throws -> [RootCollator] {
        try [RootCollator()] + tailorings.map { try RootCollator(tailoringNamed: $0) }
    }

    @Test func sharedCollatorsGiveTheSameAnswersOnEveryThread() throws {
        let collators = try Self.makeCollators()
        let combos = collators.indices.flatMap { c in Self.optionSets.indices.map { (c, $0) } }
        let expected = try combos.map { try Self.answers(collators[$0.0], Self.optionSets[$0.1]) }

        let iterations = 64
        let failures = Counters(iterations)
        DispatchQueue.concurrentPerform(iterations: iterations) { it in
            // A different order per thread, so neighboring threads use different option words at the same time.
            for k in combos.indices {
                let index = (k * (it % 2 == 0 ? 1 : combos.count - 1) + it) % combos.count
                let (c, o) = combos[index]
                let got = try? Self.answers(collators[c], Self.optionSets[o])
                if got != expected[index] { failures.slots[it] += 1 }
            }
        }
        #expect(failures.total == 0, "\(Array(failures.slots)) mismatching (collator, options) pairs per thread")
    }

    @Test func collatorsCreatedConcurrentlyGiveTheSameAnswers() throws {
        let names = [""] + Self.tailorings
        let expected = try Self.makeCollators().map { try Self.answers($0, CollationOptions()) }

        let iterations = 64
        let failures = Counters(iterations)
        DispatchQueue.concurrentPerform(iterations: iterations) { it in
            let k = it % names.count
            let collator = try? (names[k].isEmpty ? RootCollator() : RootCollator(tailoringNamed: names[k]))
            guard let collator, let got = try? Self.answers(collator, CollationOptions()) else {
                failures.slots[it] += 1
                return
            }
            if got != expected[k] { failures.slots[it] += 1 }
        }
        #expect(failures.total == 0, "\(Array(failures.slots)) failures per thread")
    }

    /// The explicit-locale slot of CollatorCache is lock-free for readers and switches to another identifier's slot on a miss (technique log §51 (aj)). Threads ask for collators of different locales in different orders, so the published slot changes under them all the time; every compare must still use the collator of its own locale.
    @Test func explicitLocaleCacheGivesEachLocaleItsOwnCollator() throws {
        let identifiers = ["en_US", "sv_SE", "de_DE", "fr_CA", "th_TH", "ja_JP", "da_DK", "en_GB"]
        // Pairs whose order depends on the tailoring: å/ä/ö after z (sv, da), backward secondary (fr_CA), Thai prefix vowels, kana.
        let pairs: [(String, String)] = [
            ("\u{E4}r", "zon"), ("\u{E5}r", "\u{E4}r"), ("\u{F6}l", "zon"), ("cot\u{E9}", "c\u{F4}te"),
            ("c\u{F4}te", "cot\u{E9}"), ("เก", "กา"), ("แก", "เก"), ("カ", "か"), ("aa", "zz"), ("Ab", "ab"),
        ]
        func answers(_ id: String) throws -> [RootCollator.Order] {
            let collator = try #require(CollatorCache.shared.collator(for: Locale(identifier: id)))
            return try pairs.map { try collator.compare($0.0, $0.1) }
        }
        let expected = try identifiers.map { try answers($0) }
        #expect(Set(expected.map { "\($0)" }).count > 2, "the pairs must tell the tailorings apart")

        let iterations = 64
        let failures = Counters(iterations)
        DispatchQueue.concurrentPerform(iterations: iterations) { it in
            for round in 0..<50 {
                let k = (round * (it % 2 == 0 ? 1 : identifiers.count - 1) + it) % identifiers.count
                guard let collator = CollatorCache.shared.collator(for: Locale(identifier: identifiers[k])),
                      let got = try? pairs.map({ try collator.compare($0.0, $0.1) }) else {
                    failures.slots[it] += 1
                    continue
                }
                if got != expected[k] { failures.slots[it] += 1 }
            }
        }
        #expect(failures.total == 0, "\(Array(failures.slots)) failures per thread")
    }
}
