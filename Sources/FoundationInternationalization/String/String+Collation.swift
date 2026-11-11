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
import FoundationEssentials
#endif
internal import Synchronization

#if FOUNDATION_FRAMEWORK
internal import _ForSwiftFoundation

internal func foundation_swift_collation_feature_enabled() -> Bool {
    false
}
#else
internal func foundation_swift_collation_feature_enabled() -> Bool { true }
#endif

struct CollatorCache: Sendable {
    static let shared = CollatorCache()

    private let lock = LockedState(initialState: [String: RootCollator]())

    /// Fast path for Locale.current — caches the collator for the current locale, revalidated against Foundation's locale generation count (LocaleNotifications) so a mid-process system locale change re-resolves on the next call — the same documented mechanism Calendar and TimeZone use. RootCollator is immutable and Sendable so sharing is safe.
    private struct CurrentSlot {
        let collator: RootCollator
        let generation: Int
    }
    /// Readers take NO lock: one acquiring load of the published slot. Writers serialize on `currentWriteLock`, put a new slot in memory and publish it with a releasing store. A published slot is never freed — a reader may still read it — so each locale change keeps one slot (16 bytes); collators are kept for the process anyway. A lock per read would be a large part of a short `localizedCompare`.
    // @unchecked Sendable: readers see only published slots, which are never changed or freed; writers are serialized by `currentWriteLock` and `lastLocaleSlots`. Lock-free reads of published raw memory have no safe equivalent today, so no migration is planned.
    private final class PublishedSlots: @unchecked Sendable {
        /// The current-locale slot, a `CurrentSlot`.
        let current = Atomic<UnsafeRawPointer?>(nil)
        /// The explicit-locale slot, a `LastLocale`.
        let lastLocale = Atomic<UnsafeRawPointer?>(nil)
        /// One `LastLocale` slot per identifier, the memory behind `lastLocale`; also the write lock of that slot.
        let lastLocaleSlots = LockedState(initialState: [String: UnsafeMutablePointer<LastLocale>]())
    }
    private let published = PublishedSlots()
    /// The writers' lock of the current-locale slot; its state counts the published slots. Not a `LockedState<Void>`: for a state of size zero, the Thread Sanitizer reports a "Swift access race" inside `LockedState.withLockUnchecked` when two threads take the lock.
    private let currentWriteLock = LockedState(initialState: 0)

    /// One-slot cache for the most recent explicit-locale resolution. Full resolution walks locale.identifier through prefix scans, a substring, and 2–3 string-keyed dictionary probes, most of a whole compare(_:locale:) call. Callers overwhelmingly pass the same Locale repeatedly; comparing its identifier against the slot is a pointer-equality fast path when the backing storage is shared, so a repeat resolves in one load + compare + return. Lock-free for readers, like the current-locale slot. Callers may switch between locales, so a new slot per miss would grow without limit: each identifier gets ONE slot, kept in `PublishedSlots.lastLocaleSlots` under its lock and published again when it comes back. The memory grows only with the number of distinct identifiers, like the collator dictionary.
    private struct LastLocale {
        let identifier: String
        let collator: RootCollator
    }

    /// The collator field of a published slot. Slots are never freed, so the pointer is valid for the whole process.
    @inline(__always)
    private static func collatorPointer<Slot>(in slot: UnsafeRawPointer, _ field: KeyPath<Slot, RootCollator>) -> UnsafePointer<RootCollator> {
        guard let offset = MemoryLayout<Slot>.offset(of: field) else {
            preconditionFailure("a slot's collator must be a stored property")
        }
        return (slot + offset).assumingMemoryBound(to: RootCollator.self)
    }

    /// The collator for the current locale, in place in its published slot (valid for the whole process). Callers call it through `pointee`, so a call needs no retain and release of the collator's storage, on a reference count that every thread shares. The lock-free read is force-inlined; the locked path is out of line, so the read can inline into the callers.
    @inline(__always)
    func currentLocaleCollator() -> UnsafePointer<RootCollator>? {
        // Generation first, resolution second: if a locale reset lands between the two, the fresh collator is stored under the OLD generation and the next call re-resolves — converging, never stale. The reverse order could pin a stale collator under the new generation.
        let generation = LocaleNotifications.cache.count()
        if let raw = published.current.load(ordering: .acquiring),
           raw.assumingMemoryBound(to: CurrentSlot.self).pointee.generation == generation {
            return Self.collatorPointer(in: raw, \CurrentSlot.collator)
        }
        return publishCurrentLocaleCollator(generation: generation)
    }

    @inline(never)
    private func publishCurrentLocaleCollator(generation: Int) -> UnsafePointer<RootCollator>? {
        currentWriteLock.withLock { publishedSlots in
            // Another thread may have published this generation since this one missed.
            if let raw = published.current.load(ordering: .acquiring),
               raw.assumingMemoryBound(to: CurrentSlot.self).pointee.generation == generation {
                return Self.collatorPointer(in: raw, \CurrentSlot.collator)
            }
            // A failed resolution publishes nothing: the next call tries again.
            guard let c = collator(forLanguage: Self.resolveLanguage(for: Locale.current)) else { return nil }
            let slot = UnsafeMutablePointer<CurrentSlot>.allocate(capacity: 1)
            slot.initialize(to: CurrentSlot(collator: c, generation: generation))
            published.current.store(UnsafeRawPointer(slot), ordering: .releasing)
            publishedSlots += 1
            return Self.collatorPointer(in: UnsafeRawPointer(slot), \CurrentSlot.collator)
        }
    }

    func collatorForCurrentLocale() -> RootCollator? {
        currentLocaleCollator()?.pointee
    }

    /// The collator for `locale`, in place in its published slot (valid for the whole process), like `currentLocaleCollator()`.
    func collator(in locale: Locale) -> UnsafePointer<RootCollator>? {
        let id = locale.identifier
        if let raw = published.lastLocale.load(ordering: .acquiring),
           raw.assumingMemoryBound(to: LastLocale.self).pointee.identifier == id {
            return Self.collatorPointer(in: raw, \LastLocale.collator)
        }
        guard let resolved = collator(forLanguage: Self.resolveLanguage(for: locale)) else { return nil }
        return published.lastLocaleSlots.withLock { slots in
            let slot: UnsafeMutablePointer<LastLocale>
            if let existing = slots[id] {
                slot = existing
            } else {
                slot = .allocate(capacity: 1)
                slot.initialize(to: LastLocale(identifier: id, collator: resolved))
                slots[id] = slot
            }
            published.lastLocale.store(UnsafeRawPointer(slot), ordering: .releasing)
            return Self.collatorPointer(in: UnsafeRawPointer(slot), \LastLocale.collator)
        }
    }

    func collator(for locale: Locale?) -> RootCollator? {
        guard let locale else { return collator(forLanguage: nil) }
        return collator(in: locale)?.pointee
    }

    private func collator(forLanguage lang: String?) -> RootCollator? {
        let tailoring = lang.flatMap { Self.tailoringMap[$0] }
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

    private static func resolveLanguage(for locale: Locale) -> String? {
        let id = locale.identifier
        if tailoringMap[id] != nil { return id }
        if id.hasPrefix("de") && id.contains("phonebook") { return "de" }
        if id.hasPrefix("zh") && id.contains("stroke") { return "zh-stroke" }
        if id.hasPrefix("fr") && (id.contains("CA") || id.contains("_CA")) { return "fr_CA" }
        let lang: String
        if let sep = id.firstIndex(where: { $0 == "_" || $0 == "-" }) {
            lang = String(id[id.startIndex..<sep])
        } else {
            lang = id
        }
        return tailoringMap[lang] != nil ? lang : nil
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
        "zh-stroke": "zh-stroke",
        "zu": "zu",
    ]
}

extension CollationOptions {
    /// Translates CompareOptions onto `base` — the resolved collator's defaultOptions, so tailoring default settings (fr_CA backwards secondary, da upper-first) survive the translation; each Foundation option overrides just its own attribute, like setting attributes on an opened ICU collator. `base` is deliberately required: a fresh CollationOptions() base silently drops tailoring defaults.
    static func from(foundationOptions: String.CompareOptions, base: CollationOptions) -> CollationOptions {
        var opts = base
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
