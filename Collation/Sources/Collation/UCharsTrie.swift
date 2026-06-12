// Read-only UCharsTrie: matches strings of UTF-16 units against a serialized
// trie and yields 32-bit values. Ported from ICU4C common/unicode/ucharstrie.h
// and common/ucharstrie.cpp. Used for the collation contexts data
// (contraction suffixes and prefix conditions).
//
// This is a value type: copying the struct snapshots the traversal state,
// which replaces ICU's SkippedState save/restore in discontiguous contraction
// matching.

struct UCharsTrie {
    enum Result: Int32 {
        case noMatch = 0
        case noValue = 1
        case finalValue = 2
        case intermediateValue = 3

        /// The string so far has a value (final or intermediate).
        var hasValue: Bool { rawValue >= 2 }
        /// Another input unit can continue a match.
        var hasNext: Bool { (rawValue & 1) != 0 }
    }

    // Node and value encoding constants (ucharstrie.h).
    private static let maxBranchLinearSubNodeLength = 5
    private static let minLinearMatch: Int32 = 0x30
    private static let minValueLead: Int32 = 0x40
    private static let nodeTypeMask: Int32 = 0x3f
    private static let valueIsFinal: Int32 = 0x8000
    private static let minTwoUnitValueLead: Int32 = 0x4000
    private static let threeUnitValueLead: Int32 = 0x7fff
    private static let minTwoUnitNodeValueLead: Int32 = 0x4040
    private static let threeUnitNodeValueLead: Int32 = 0x7fc0
    private static let minTwoUnitDeltaLead: Int32 = 0xfc00
    private static let threeUnitDeltaLead: Int32 = 0xffff

    /// The backing units (the collation contexts array).
    let units: [UInt16]
    /// Offset of the trie root within `units`.
    let root: Int
    /// Current position, or nil after a mismatch.
    private var pos: Int?
    /// Remaining length of a partially-consumed linear-match node, minus 1.
    private var remainingMatchLength: Int = -1

    init(units: [UInt16], offset: Int) {
        self.units = units
        self.root = offset
        self.pos = offset
    }

    private mutating func stop() {
        pos = nil
    }

    mutating func reset() {
        pos = root
        remainingMatchLength = -1
    }

    @inline(__always)
    private func unit(_ i: Int) -> Int32 {
        Int32(units[i])
    }

    /// Traverses from the initial state. (UCharsTrie::first.)
    mutating func first(_ uchar: Int32) -> Result {
        remainingMatchLength = -1
        return nextImpl(pos: root, uchar: uchar)
    }

    /// Traverses from the initial state for 1–2 UTF-16 units of a code point.
    mutating func firstForCodePoint(_ cp: UInt32) -> Result {
        if cp <= 0xffff {
            return first(Int32(cp))
        }
        let lead = first(Int32(0xd7c0 + (cp >> 10)))
        if lead.hasNext {
            return next(Int32(0xdc00 + (cp & 0x3ff)))
        }
        stop()
        return .noMatch
    }

    /// Traverses from the current state. (UCharsTrie::next.)
    mutating func next(_ uchar: Int32) -> Result {
        guard var p = pos else { return .noMatch }
        let length = remainingMatchLength  // actual remaining match length minus 1
        if length >= 0 {
            // Remaining part of a linear-match node.
            if uchar == unit(p) {
                p += 1
                remainingMatchLength = length - 1
                pos = p
                if length - 1 < 0 {
                    let node = unit(p)
                    if node >= Self.minValueLead { return Self.valueResult(node) }
                }
                return .noValue
            }
            stop()
            return .noMatch
        }
        return nextImpl(pos: p, uchar: uchar)
    }

    /// Traverses from the current state for 1–2 UTF-16 units of a code point.
    mutating func nextForCodePoint(_ cp: UInt32) -> Result {
        if cp <= 0xffff {
            return next(Int32(cp))
        }
        let lead = next(Int32(0xd7c0 + (cp >> 10)))
        if lead.hasNext {
            return next(Int32(0xdc00 + (cp & 0x3ff)))
        }
        stop()
        return .noMatch
    }

    /// Value for the string so far. Only valid after a result with hasValue.
    func getValue() -> Int32 {
        let p = pos!
        let leadUnit = unit(p)
        if (leadUnit & Self.valueIsFinal) != 0 {
            return Self.readValue(units, p + 1, leadUnit & 0x7fff)
        }
        return Self.readNodeValue(units, p + 1, leadUnit)
    }

    // MARK: Internal traversal (ucharstrie.cpp)

    private mutating func nextImpl(pos p: Int, uchar: Int32) -> Result {
        var p = p
        var node = unit(p)
        p += 1
        while true {
            if node < Self.minLinearMatch {
                return branchNext(pos: p, length: Int(node), uchar: uchar)
            } else if node < Self.minValueLead {
                // Match the first of length+1 units.
                let length = node - Self.minLinearMatch  // match length minus 1
                if uchar == unit(p) {
                    p += 1
                    remainingMatchLength = Int(length) - 1
                    pos = p
                    if length - 1 < 0 {
                        let n = unit(p)
                        if n >= Self.minValueLead { return Self.valueResult(n) }
                    }
                    return .noValue
                }
                break  // no match
            } else if (node & Self.valueIsFinal) != 0 {
                break  // no further matching units
            } else {
                // Skip intermediate value.
                p = Self.skipNodeValue(p, leadUnit: node)
                node &= Self.nodeTypeMask
            }
        }
        stop()
        return .noMatch
    }

    private mutating func branchNext(pos p: Int, length lengthIn: Int, uchar: Int32) -> Result {
        var p = p
        var length = lengthIn
        if length == 0 {
            length = Int(unit(p))
            p += 1
        }
        length += 1
        // The length of the branch is the number of units to select from.
        // The data structure encodes a binary search.
        while length > Self.maxBranchLinearSubNodeLength {
            if uchar < unit(p) {
                p += 1
                length >>= 1
                p = jumpByDelta(p)
            } else {
                p += 1
                length = length - (length >> 1)
                p = skipDelta(p)
            }
        }
        // Drop down to linear search for the last few units.
        repeat {
            if uchar == unit(p) {
                p += 1
                var node = unit(p)
                if (node & Self.valueIsFinal) != 0 {
                    // Leave the final value for getValue() to read.
                    pos = p
                    return .finalValue
                }
                // Use the non-final value as the jump delta.
                p += 1
                let delta: Int32
                if node < Self.minTwoUnitValueLead {
                    delta = node
                } else if node < Self.threeUnitValueLead {
                    delta = ((node - Self.minTwoUnitValueLead) << 16) | unit(p)
                    p += 1
                } else {
                    delta = (unit(p) << 16) | unit(p + 1)
                    p += 2
                }
                p += Int(delta)
                node = unit(p)
                pos = p
                return node >= Self.minValueLead ? Self.valueResult(node) : .noValue
            }
            length -= 1
            p = skipValueAt(p + 1)
        } while length > 1
        if uchar == unit(p) {
            p += 1
            pos = p
            let node = unit(p)
            return node >= Self.minValueLead ? Self.valueResult(node) : .noValue
        }
        stop()
        return .noMatch
    }

    // MARK: Compact value helpers (ucharstrie.h)

    private static func valueResult(_ node: Int32) -> Result {
        Result(rawValue: Result.intermediateValue.rawValue - (node >> 15))!
    }

    private static func readValue(_ units: [UInt16], _ p: Int, _ leadUnit: Int32) -> Int32 {
        if leadUnit < minTwoUnitValueLead {
            return leadUnit
        } else if leadUnit < threeUnitValueLead {
            return ((leadUnit - minTwoUnitValueLead) << 16) | Int32(units[p])
        }
        return (Int32(units[p]) << 16) | Int32(units[p + 1])
    }

    private static func readNodeValue(_ units: [UInt16], _ p: Int, _ leadUnit: Int32) -> Int32 {
        if leadUnit < minTwoUnitNodeValueLead {
            return (leadUnit >> 6) - 1
        } else if leadUnit < threeUnitNodeValueLead {
            return (((leadUnit & 0x7fc0) - minTwoUnitNodeValueLead) << 10) | Int32(units[p])
        }
        return (Int32(units[p]) << 16) | Int32(units[p + 1])
    }

    private static func skipNodeValue(_ p: Int, leadUnit: Int32) -> Int {
        if leadUnit >= minTwoUnitNodeValueLead {
            return leadUnit < threeUnitNodeValueLead ? p + 1 : p + 2
        }
        return p
    }

    /// Skips a value whose lead unit is at `leadPos`; returns the position
    /// after the value. (UCharsTrie::skipValue.)
    private func skipValueAt(_ leadPos: Int) -> Int {
        let leadUnit = unit(leadPos) & 0x7fff
        var p = leadPos + 1
        if leadUnit >= Self.minTwoUnitValueLead {
            p += leadUnit < Self.threeUnitValueLead ? 1 : 2
        }
        return p
    }

    private func jumpByDelta(_ p: Int) -> Int {
        var p = p
        var delta = unit(p)
        p += 1
        if delta >= Self.minTwoUnitDeltaLead {
            if delta == Self.threeUnitDeltaLead {
                delta = (unit(p) << 16) | unit(p + 1)
                p += 2
            } else {
                delta = ((delta - Self.minTwoUnitDeltaLead) << 16) | unit(p)
                p += 1
            }
        }
        return p + Int(delta)
    }

    private func skipDelta(_ p: Int) -> Int {
        let delta = unit(p)
        var p = p + 1
        if delta >= Self.minTwoUnitDeltaLead {
            p += delta == Self.threeUnitDeltaLead ? 2 : 1
        }
        return p
    }
}
