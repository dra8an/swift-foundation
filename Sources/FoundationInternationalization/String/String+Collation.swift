//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if FOUNDATION_COLLATION

#if canImport(FoundationEssentials)
import FoundationEssentials
#endif

import Collation

struct CollatorCache: Sendable {
    static let shared = CollatorCache()

    private let lock = LockedState(initialState: [String: RootCollator]())

    func collator(for locale: Locale?) -> RootCollator? {
        let tailoring = Self.tailoringName(for: locale)
        let key = tailoring ?? "_root_"
        return lock.withLock { cache in
            if let cached = cache[key] {
                return cached
            }
            let collator: RootCollator?
            if let tailoring {
                collator = try? RootCollator(tailoringNamed: tailoring)
            } else {
                collator = try? RootCollator()
            }
            if let collator {
                cache[key] = collator
            }
            return collator
        }
    }

    private static let tailoringMap: [String: String] = [
        "sv": "sv",
        "de": "de-phonebook",
        "fr_CA": "fr_CA",
        "fr-CA": "fr_CA",
        "ja": "ja",
        "zh": "zh",
        "zh-Hans": "zh",
        "ko": "ko",
        "th": "th",
        "ar": "ar",
        "he": "he",
        "da": "da",
        "fi": "fi",
        "nb": "nb",
        "nn": "nn",
        "no": "nb",
        "es": "es",
        "tr": "tr",
        "lt": "lt",
        "fr": "fr",
    ]

    static func tailoringName(for locale: Locale?) -> String? {
        guard let locale else { return nil }
        let id = locale.identifier
        if let name = tailoringMap[id] { return name }
        let language = locale.language.languageCode?.identifier ?? ""
        if let name = tailoringMap[language] { return name }
        if id.hasPrefix("de") && id.contains("phonebook") {
            return "de-phonebook"
        }
        if id.hasPrefix("zh") && id.contains("stroke") {
            return "zh-stroke"
        }
        return tailoringMap[language]
    }
}

extension CollationOptions {
    static func from(foundationOptions: String.CompareOptions) -> CollationOptions {
        var opts = CollationOptions()
        if foundationOptions.contains(.caseInsensitive) {
            opts.strength = .secondary
        }
        if foundationOptions.contains(.diacriticInsensitive) {
            opts.strength = .primary
        }
        if foundationOptions.contains(.numeric) {
            opts.numeric = true
        }
        if foundationOptions.contains(.forcedOrdering) {
            opts.strength = .identical
        }
        return opts
    }
}

extension RootCollator.Order {
    var comparisonResult: ComparisonResult {
        switch self {
        case .ascending: return .orderedAscending
        case .same: return .orderedSame
        case .descending: return .orderedDescending
        }
    }
}

#endif // FOUNDATION_COLLATION
