// Collation options, mirroring ICU4C's CollationSettings options word
// (i18n/collationsettings.h) so the ported comparison code can use the same
// bit tests as the original.

public struct CollationOptions: Sendable, Equatable {
    public enum Strength: Int32, Sendable {
        case primary = 0
        case secondary = 1
        case tertiary = 2
        case quaternary = 3
        /// Quaternary plus an NFD code-point-order tiebreaker.
        case identical = 15
    }

    public enum Alternate: Sendable {
        /// Variable characters (spaces, punctuation, ...) are regular CEs.
        case nonIgnorable
        /// Variable characters are shifted down to the quaternary level.
        case shifted
    }

    public enum CaseFirst: Sendable {
        case off
        case lowerFirst
        case upperFirst
    }

    /// Which reorder groups count as "variable" under alternate=shifted.
    public enum MaxVariable: Int32, Sendable {
        case space = 0
        case punctuation = 1
        case symbol = 2
        case currency = 3
    }

    public var strength: Strength = .tertiary
    public var alternate: Alternate = .nonIgnorable
    public var maxVariable: MaxVariable = .punctuation
    public var caseFirst: CaseFirst = .off
    /// Insert a separate case level between the secondary and tertiary levels.
    public var caseLevel = false
    /// Compare secondary weights backwards ("French" accent ordering).
    public var backwardSecondary = false
    /// Compare digit runs numerically (CODAN): "item9" < "item10".
    public var numeric = false

    public init() {}

    /// Decodes a CollationSettings options word (e.g. a tailoring's defaults
    /// from the data's IX_OPTIONS).
    init(icuOptionsWord word: Int32) {
        strength = Strength(rawValue: word >> Bits.strengthShift) ?? .tertiary
        alternate = (word & Bits.alternateMask) != 0 ? .shifted : .nonIgnorable
        maxVariable = MaxVariable(rawValue: (word >> 4) & 7) ?? .punctuation
        switch word & Bits.caseFirstAndUpperMask {
        case Bits.caseFirst: caseFirst = .lowerFirst
        case Bits.caseFirstAndUpperMask: caseFirst = .upperFirst
        default: caseFirst = .off
        }
        caseLevel = (word & Bits.caseLevel) != 0
        backwardSecondary = (word & Bits.backwardSecondary) != 0
        numeric = (word & 2) != 0
    }

    // MARK: ICU options word (CollationSettings bit layout)

    enum Bits {
        static let numeric: Int32 = 2
        static let shifted: Int32 = 4
        static let alternateMask: Int32 = 0xc
        static let maxVariableShift: Int32 = 4
        static let upperFirst: Int32 = 0x100
        static let caseFirst: Int32 = 0x200
        static let caseFirstAndUpperMask: Int32 = 0x300
        static let caseLevel: Int32 = 0x400
        static let backwardSecondary: Int32 = 0x800
        static let strengthShift: Int32 = 12
    }

    /// The equivalent CollationSettings::options word (complete: numeric and
    /// maxVariable included, so the word fully determines compare behavior —
    /// the fast Latin path uses it as a cache key).
    var icuOptions: Int32 {
        var options: Int32 = strength.rawValue << Bits.strengthShift
        options |= maxVariable.rawValue << Bits.maxVariableShift
        if numeric { options |= Bits.numeric }
        if alternate == .shifted { options |= Bits.shifted }
        switch caseFirst {
        case .off: break
        case .lowerFirst: options |= Bits.caseFirst
        case .upperFirst: options |= Bits.caseFirstAndUpperMask
        }
        if caseLevel { options |= Bits.caseLevel }
        if backwardSecondary { options |= Bits.backwardSecondary }
        return options
    }

    // Static helpers matching CollationSettings, operating on the options word.

    static func strength(of options: Int32) -> Int32 {
        options >> Bits.strengthShift
    }

    static func isTertiaryWithCaseBits(_ options: Int32) -> Bool {
        (options & (Bits.caseLevel | Bits.caseFirst)) == Bits.caseFirst
    }

    /// Tertiary-level mask: keep case bits only when caseFirst is on and
    /// caseLevel is off.
    static func tertiaryMask(of options: Int32) -> UInt32 {
        isTertiaryWithCaseBits(options)
            ? CollationConstants.caseAndTertiaryMask : CollationConstants.onlyTertiaryMask
    }

    static func sortsTertiaryUpperCaseFirst(_ options: Int32) -> Bool {
        (options & (Bits.caseLevel | Bits.caseFirstAndUpperMask)) == Bits.caseFirstAndUpperMask
    }
}
