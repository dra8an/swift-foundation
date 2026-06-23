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

#if FOUNDATION_FRAMEWORK
internal import _ForSwiftFoundation

internal func foundation_swift_collation_feature_enabled() -> Bool {
    // System feature flag — Apple can flip this to route Darwin string
    // comparison through the Swift collator instead of the ObjC/ICU bridge.
    // Until _foundation_swift_collation_feature_enabled() exists in
    // _ForSwiftFoundation, this defaults to false.
    // _foundation_swift_collation_feature_enabled()
    false
}
#else
internal func foundation_swift_collation_feature_enabled() -> Bool { true }
#endif

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
        "af": "af",
        "am": "am",
        "ar": "ar",
        "as": "as",
        "az": "az",
        "be": "be",
        "bg": "bg",
        "bn": "bn",
        "bo": "bo",
        "bs": "bs",
        "cs": "cs",
        "cy": "cy",
        "da": "da",
        "de": "de-phonebook",
        "el": "el",
        "es": "es",
        "et": "et",
        "fa": "fa",
        "fi": "fi",
        "fil": "fil",
        "fo": "fo",
        "fr": "fr",
        "fr_CA": "fr_CA",
        "fr-CA": "fr_CA",
        "ga": "ga",
        "gl": "gl",
        "gu": "gu",
        "ha": "ha",
        "haw": "haw",
        "he": "he",
        "hi": "hi",
        "hr": "hr",
        "hu": "hu",
        "hy": "hy",
        "id": "id",
        "ig": "ig",
        "is": "is",
        "it": "it",
        "ja": "ja",
        "ka": "ka",
        "kk": "kk",
        "kl": "kl",
        "km": "km",
        "kn": "kn",
        "ko": "ko",
        "kok": "kok",
        "ku": "ku",
        "ky": "ky",
        "lb": "lb",
        "lo": "lo",
        "lt": "lt",
        "lv": "lv",
        "mk": "mk",
        "ml": "ml",
        "mn": "mn",
        "mr": "mr",
        "ms": "ms",
        "mt": "mt",
        "my": "my",
        "nb": "nb",
        "ne": "ne",
        "nl": "nl",
        "nn": "nn",
        "no": "nb",
        "or": "or",
        "pa": "pa",
        "pl": "pl",
        "ps": "ps",
        "pt": "pt",
        "ro": "ro",
        "ru": "ru",
        "se": "se",
        "si": "si",
        "sk": "sk",
        "sl": "sl",
        "sq": "sq",
        "sr": "sr",
        "sv": "sv",
        "sw": "sw",
        "ta": "ta",
        "te": "te",
        "th": "th",
        "ti": "ti",
        "tk": "tk",
        "to": "to",
        "tr": "tr",
        "tt": "tt",
        "ug": "ug",
        "uk": "uk",
        "ur": "ur",
        "uz": "uz",
        "vi": "vi",
        "wae": "wae",
        "wo": "wo",
        "xh": "xh",
        "yo": "yo",
        "zh": "zh",
        "zh-Hans": "zh",
        "zu": "zu",
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
