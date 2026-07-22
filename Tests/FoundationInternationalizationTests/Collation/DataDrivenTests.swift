import Foundation
import Testing
@testable import FoundationInternationalization

/// Runner for ICU's data-driven collation test file
/// (test/testdata/collationtest.txt), following CollationTest::TestDataDriven:
///
/// - `@ root` / `@ locale <id>` select a collator; `% attribute=value` lines
///   modify options; `* compare` blocks list strings with relations
///   `=`, `<`, `<1`, `<2`, `<c`, `<3`, `<4`, `<i` against the previous string.
/// - Each line is checked in both directions, by sort keys (including the
///   level of the first difference, counted by 01 separators), and again with
///   NFD-normalized inputs.
///
/// Sections this port cannot run are skipped and counted:
/// - `@ rules` (109 sections): requires the runtime rule builder, which is
///   deliberately not ported (tailorings are compiled offline).
/// - `% reorder ...`: requires generating reorder tables from reorder codes
///   (only data-supplied reorderings are supported).
/// - locales not bundled, and locale tags with unsupported keywords
///   (e.g. kk-false: normalization cannot be turned off in this design).
/// - lines whose strings contain unpaired surrogates (not representable in
///   Swift Strings).
@Suite struct DataDrivenTests {
    enum Relation {
        case equal
        case less(level: Int?)  // level 1=primary 2=secondary 3=case 4=tertiary 5=quaternary 6=identical
    }

    static let root = try! RootCollator()

    /// Locale tags appearing in collationtest.txt, mapped to bundled
    /// tailorings (with optional option overrides) or nil (skip section).
    static func collator(forLocale tag: String) -> (RootCollator, CollationOptions)? {
        func tailored(_ name: String) -> (RootCollator, CollationOptions)? {
            let c = try! RootCollator(tailoringNamed: name)
            return (c, c.defaultOptions)
        }
        switch tag.lowercased() {
        case "en", "de":  // standard collation == root
            return (root, CollationOptions())
        case "da":
            return tailored("da")
        case "de@collation=phonebook", "de-u-co-phonebk":
            return tailored("de-phonebook")
        case "fr-ca-u-co-phonebk":  // no phonebook for fr -> falls back to fr-CA standard
            return tailored("fr_CA")
        case "lt":
            return tailored("lt")
        case "th-th":
            return tailored("th")
        case "zh", "zh-u-co-pinyin":
            return tailored("zh")
        case "zh-u-co-stroke":
            return tailored("zh-stroke")
        case "fr@colbackwards=yes;colstrength=quaternary;kv=currency;colalternate=shifted":
            // fr standard is a settings-only tailoring; apply the keyword overrides.
            guard var (c, o) = tailored("fr") else { return nil }
            o.backwardSecondary = true
            o.strength = .quaternary
            o.maxVariable = .currency
            o.alternate = .shifted
            return (c, o)
        default:
            return nil  // not bundled / unsupported keywords
        }
    }

    @Test func runCollationTestFile() throws {
        let url = Bundle.module.url(forResource: "Conformance", withExtension: nil)!
            .appendingPathComponent("collationtest.txt")
        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)

        var collator: RootCollator?
        var options = CollationOptions()
        var skippingRules = false
        var prev: String? = ""  // nil right after a skipped line
        var testName = ""

        var checkedLines = 0
        var skippedSections = 0
        var skippedAttrSections = 0
        var skippedSurrogateLines = 0
        var failures = 0

        var lineNumber = 0
        for rawLine in lines {
            lineNumber += 1
            // Strip comment and trailing whitespace (readNonEmptyLine).
            var line = Substring(rawLine)
            if let hash = line.firstIndex(of: "#") { line = line[..<hash] }
            while let last = line.last, last == " " || last == "\t" || last == "\r" {
                line = line.dropLast()
            }
            if line.isEmpty { continue }

            if line.hasPrefix("** test:") {
                testName = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("@ rules") {
                collator = nil
                skippingRules = true
                skippedSections += 1
                continue
            }
            if line.hasPrefix("@ root") {
                collator = Self.root
                options = CollationOptions()
                skippingRules = false
                continue
            }
            if line.hasPrefix("@ locale ") {
                skippingRules = false
                let tag = String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                if let (c, o) = Self.collator(forLocale: tag) {
                    collator = c
                    options = o
                } else {
                    collator = nil
                    skippedSections += 1
                }
                continue
            }
            if line.hasPrefix("%") {
                let attr = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !apply(attribute: attr, to: &options) {
                    collator = nil
                    skippedAttrSections += 1
                }
                continue
            }
            if line.hasPrefix("*") {  // "* compare"
                prev = ""
                continue
            }
            if skippingRules { continue }  // tailoring rule lines

            // Relation line.
            guard line.hasPrefix("<") || line.hasPrefix("=") else { continue }
            guard let (relation, token) = parseRelation(line) else { continue }
            guard let current = unescape(token) else {
                skippedSurrogateLines += 1
                prev = nil  // break the comparison chain for one line
                continue
            }
            guard let coll = collator else { continue }
            guard let previous = prev else {
                prev = current
                continue
            }
            prev = current
            checkedLines += 1

            do {
                if try !check(coll, options, previous, current, relation) {
                    failures += 1
                    if failures <= 5 {
                        Issue.record(
                            "[\(testName)] line \(lineNumber): \(rawLine.trimmingCharacters(in: .whitespaces))"
                        )
                    }
                }
            } catch {
                failures += 1
                Issue.record("[\(testName)] line \(lineNumber) threw: \(error)")
            }
        }

        #expect(failures == 0, "\(failures) of \(checkedLines) checked lines failed")
        // Coverage accounting: the file has 109 rules sections and a handful
        // of unsupported locale/attribute sections.
        // Skip accounting stays visible on failure (the guideline bans print in tests): the counts ride the assertion message.
        #expect(checkedLines >= 300, "ran only \(checkedLines) lines (skipped \(skippedSections) rules/locale sections, \(skippedAttrSections) attribute sections, \(skippedSurrogateLines) unpaired-surrogate lines) — parsing regression?")
    }

    // MARK: Checks (CollationTest::checkCompareTwo)

    private func check(
        _ coll: RootCollator, _ options: CollationOptions,
        _ previous: String, _ current: String, _ relation: Relation
    ) throws -> Bool {
        let expected: RootCollator.Order
        let expectedLevel: Int?
        switch relation {
        case .equal:
            expected = .same
            expectedLevel = nil
        case .less(let level):
            expected = .ascending
            expectedLevel = level
        }

        // Both directions.
        guard try coll.compare(previous, current, options: options) == expected else { return false }
        let reversed: RootCollator.Order = expected == .same ? .same : .descending
        guard try coll.compare(current, previous, options: options) == reversed else { return false }

        // Sort keys: same order, and the level of the first difference.
        let k1 = try coll.sortKey(for: previous, options: options)
        let k2 = try coll.sortKey(for: current, options: options)
        let keyOrder: RootCollator.Order =
            k1 == k2 ? .same : (k1.lexicographicallyPrecedes(k2) ? .ascending : .descending)
        guard keyOrder == expected else { return false }
        if let expectedLevel {
            guard differenceLevel(k1, k2, caseLevel: options.caseLevel) == expectedLevel else {
                return false
            }
        }

        // NFD inputs must behave identically.
        let p = coll.nfd(previous)
        let c = coll.nfd(current)
        if p != previous || c != current {
            guard try coll.compare(p, c, options: options) == expected else { return false }
            let nk1 = try coll.sortKey(for: p, options: options)
            let nk2 = try coll.sortKey(for: c, options: options)
            guard nk1 == k1 && nk2 == k2 else { return false }
        }
        return true
    }

    /// Level of the first sort key difference: 1 + number of 01 separators
    /// before the first differing byte; the case level slot is skipped when
    /// caseLevel is off. (getDifferenceLevel.)
    private func differenceLevel(_ k1: [UInt8], _ k2: [UInt8], caseLevel: Bool) -> Int {
        var level = 1
        for i in 0..<min(k1.count, k2.count) {
            if k1[i] != k2[i] { break }
            if k1[i] == 1 {
                level += 1
                if level == 3 && !caseLevel { level += 1 }
            }
        }
        return level
    }

    // MARK: Parsing

    private func parseRelation(_ line: Substring) -> (Relation, Substring)? {
        var rest: Substring
        let relation: Relation
        if line.hasPrefix("=") {
            relation = .equal
            rest = line.dropFirst()
        } else {
            let second = line.dropFirst().first
            switch second {
            case "1": relation = .less(level: 1); rest = line.dropFirst(2)
            case "2": relation = .less(level: 2); rest = line.dropFirst(2)
            case "c": relation = .less(level: 3); rest = line.dropFirst(2)
            case "3": relation = .less(level: 4); rest = line.dropFirst(2)
            case "4": relation = .less(level: 5); rest = line.dropFirst(2)
            case "i": relation = .less(level: 6); rest = line.dropFirst(2)
            default: relation = .less(level: nil); rest = line.dropFirst()
            }
        }
        while rest.first == " " || rest.first == "\t" { rest = rest.dropFirst() }
        // The string is the whitespace-delimited token.
        let token = rest.prefix { $0 != " " && $0 != "\t" }
        return token.isEmpty ? nil : (relation, token)
    }

    private func apply(attribute: String, to options: inout CollationOptions) -> Bool {
        if attribute.hasPrefix("reorder") { return false }  // table generation unsupported
        let parts = attribute.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return false }
        let value = String(parts[1])
        switch parts[0] {
        case "strength":
            switch value {
            case "primary": options.strength = .primary
            case "secondary": options.strength = .secondary
            case "tertiary": options.strength = .tertiary
            case "quaternary": options.strength = .quaternary
            case "identical": options.strength = .identical
            default: return false
            }
        case "alternate":
            switch value {
            case "non-ignorable": options.alternate = .nonIgnorable
            case "shifted": options.alternate = .shifted
            default: return false
            }
        case "maxVariable":
            switch value {
            case "space": options.maxVariable = .space
            case "punct": options.maxVariable = .punctuation
            case "symbol": options.maxVariable = .symbol
            case "currency": options.maxVariable = .currency
            default: return false
            }
        case "caseFirst":
            switch value {
            case "off": options.caseFirst = .off
            case "lower": options.caseFirst = .lowerFirst
            case "upper": options.caseFirst = .upperFirst
            default: return false
            }
        case "caseLevel": options.caseLevel = value == "on"
        case "backwards": options.backwardSecondary = value == "on"
        case "numeric": options.numeric = value == "on"
        default: return false
        }
        return true
    }

    /// ICU UnicodeString::unescape subset: \uXXXX, \UXXXXXXXX, \xHH, \\, \t.
    /// Combines surrogate pairs from consecutive \u escapes; returns nil for
    /// unpaired surrogates (not representable in Swift Strings).
    private func unescape(_ token: Substring) -> String? {
        var units: [UInt32] = []  // code points, possibly UTF-16 units from \u
        var i = token.startIndex
        while i < token.endIndex {
            let ch = token[i]
            if ch != "\\" {
                units.append(contentsOf: String(ch).unicodeScalars.map(\.value))
                i = token.index(after: i)
                continue
            }
            i = token.index(after: i)
            guard i < token.endIndex else { return nil }
            let kind = token[i]
            i = token.index(after: i)
            func hex(_ n: Int) -> UInt32? {
                guard let end = token.index(i, offsetBy: n, limitedBy: token.endIndex) else { return nil }
                guard let v = UInt32(token[i..<end], radix: 16) else { return nil }
                i = end
                return v
            }
            switch kind {
            case "u":
                guard let v = hex(4) else { return nil }
                units.append(v)
            case "U":
                guard let v = hex(8) else { return nil }
                units.append(v)
            case "x":
                guard let v = hex(2) else { return nil }
                units.append(v)
            case "\\": units.append(0x5c)
            case "t": units.append(0x9)
            case "r": units.append(0xd)
            case "n": units.append(0xa)
            default: return nil
            }
        }
        // Combine surrogate pairs; reject unpaired surrogates.
        var s = ""
        var j = 0
        while j < units.count {
            let u = units[j]
            if (0xd800...0xdbff).contains(u), j + 1 < units.count,
               (0xdc00...0xdfff).contains(units[j + 1]) {
                let cp = 0x10000 + ((u - 0xd800) << 10) + (units[j + 1] - 0xdc00)
                s.unicodeScalars.append(Unicode.Scalar(cp)!)
                j += 2
                continue
            }
            guard let scalar = Unicode.Scalar(u) else { return nil }  // unpaired surrogate
            s.unicodeScalars.append(scalar)
            j += 1
        }
        return s
    }
}

/// Thai dictionary order test (CollationThaiTest::TestDictionary): riwords.txt
/// lists ~31k Thai words in dictionary order; each adjacent pair must compare
/// ascending (or equal) under the th tailoring.
@Suite struct ThaiDictionaryTests {
    @Test func riwords() throws {
        let collator = try RootCollator(tailoringNamed: "th")
        let options = collator.defaultOptions
        let url = Bundle.module.url(forResource: "Conformance", withExtension: nil)!
            .appendingPathComponent("riwords.txt")
        let words = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map { line -> Substring in
                if let hash = line.firstIndex(of: "#") { return line[..<hash] }
                return line
            }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        try #require(words.count > 30000)

        var failures = 0
        var prevKey = try collator.sortKey(for: words[0], options: options)
        for i in 1..<words.count {
            let key = try collator.sortKey(for: words[i], options: options)
            let order = try collator.compare(words[i - 1], words[i], options: options)
            if order == .descending || (!prevKey.lexicographicallyPrecedes(key) && prevKey != key) {
                failures += 1
                if failures <= 5 {
                    Issue.record("riwords line \(i): \(words[i - 1]) !<= \(words[i])")
                }
            }
            prevKey = key
        }
        #expect(failures == 0, "\(failures) of \(words.count - 1) adjacent Thai pairs out of order")
    }
}
