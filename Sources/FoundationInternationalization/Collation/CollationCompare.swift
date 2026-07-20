// Level-by-level CE comparison, a faithful port of CollationCompare::compareUpToQuaternary (i18n/collationcompare.cpp).
//
// Operates on lazily-filled CE buffers terminated by NO_CE (like ICU's CollationIterator/CEBuffer): the primary loop pulls CEs on demand and usually decides without generating the rest; the deeper levels run only when all primaries were equal, i.e. when the buffers are already complete. The primary loop may rewrite variable CEs in place (shifting them to the quaternary level). Script reordering is not yet supported (milestone 7); the corresponding hooks are omitted.

enum CollationCompare {
    /// Returns -1 / 0 / +1. `variableTopValue` is the highest variable primary (used only when options has alternate=shifted).
    static func compareUpToQuaternary(
        _ left: inout CEIterator, _ right: inout CEIterator,
        options: Int32, variableTopValue: UInt32, reordering: Reordering? = nil
    ) throws -> Int {
        let variableTop: UInt32
        if (options & CollationOptions.Bits.alternateMask) == 0 {
            variableTop = 0
        } else {
            // +1 so that we can use "<" and primary ignorables test out early.
            variableTop = variableTopValue + 1
        }
        var anyVariable = false

        // Fetch CEs, compare primaries, store secondary & tertiary weights. Variable CEs are shifted to quaternary: only their primary is kept (lower 32 bits zeroed); following primary ignorables are zeroed out.
        func nextPrimary(_ ces: inout CEIterator, _ i: inout Int) throws -> UInt32 {
            var primary: UInt32
            repeat {
                var ce = try ces.ce(at: i)
                i += 1
                primary = UInt32(truncatingIfNeeded: ce >> 32)
                if primary < variableTop && primary > CollationConstants.mergeSeparatorPrimary {
                    // Variable CE, shift it to quaternary level. Ignore all following primary ignorables, and shift further variable CEs.
                    anyVariable = true
                    repeat {
                        // Store only the primary of the variable CE.
                        ces.ces[i - 1] = ce & Int64(bitPattern: 0xffff_ffff_0000_0000)
                        while true {
                            ce = try ces.ce(at: i)
                            i += 1
                            primary = UInt32(truncatingIfNeeded: ce >> 32)
                            if primary == 0 {
                                ces.ces[i - 1] = 0
                            } else {
                                break
                            }
                        }
                    } while primary < variableTop && primary > CollationConstants.mergeSeparatorPrimary
                }
            } while primary == 0
            return primary
        }

        var li = 0
        var ri = 0
        while true {
            var leftPrimary = try nextPrimary(&left, &li)
            var rightPrimary = try nextPrimary(&right, &ri)
            if leftPrimary != rightPrimary {
                // Return the primary difference, with script reordering.
                if let reordering {
                    leftPrimary = reordering.reorder(leftPrimary)
                    rightPrimary = reordering.reorder(rightPrimary)
                }
                return leftPrimary < rightPrimary ? -1 : 1
            }
            if leftPrimary == CollationConstants.noCEPrimary { break }
        }

        // Compare the buffered secondary & tertiary weights. We might skip the secondary level but continue with the case level which is turned on separately.
        let strength = CollationOptions.strength(of: options)
        if strength >= CollationOptions.Strength.secondary.rawValue {
            if (options & CollationOptions.Bits.backwardSecondary) == 0 {
                var leftIndex = 0
                var rightIndex = 0
                while true {
                    var leftSecondary: UInt32
                    repeat {
                        leftSecondary = UInt32(truncatingIfNeeded: left.ces[leftIndex]) >> 16
                        leftIndex += 1
                    } while leftSecondary == 0

                    var rightSecondary: UInt32
                    repeat {
                        rightSecondary = UInt32(truncatingIfNeeded: right.ces[rightIndex]) >> 16
                        rightIndex += 1
                    } while rightSecondary == 0

                    if leftSecondary != rightSecondary {
                        return leftSecondary < rightSecondary ? -1 : 1
                    }
                    if leftSecondary == CollationConstants.noCEWeight16 { break }
                }
            } else {
                // The backwards secondary level compares secondary weights backwards within segments separated by the merge separator (U+FFFE, weight 02).
                var leftStart = 0
                var rightStart = 0
                while true {
                    // Find the merge separator or the NO_CE terminator.
                    var p: UInt32
                    var leftLimit = leftStart
                    while true {
                        p = UInt32(truncatingIfNeeded: left.ces[leftLimit] >> 32)
                        if !(p > CollationConstants.mergeSeparatorPrimary || p == 0) { break }
                        leftLimit += 1
                    }
                    var rightLimit = rightStart
                    while true {
                        p = UInt32(truncatingIfNeeded: right.ces[rightLimit] >> 32)
                        if !(p > CollationConstants.mergeSeparatorPrimary || p == 0) { break }
                        rightLimit += 1
                    }

                    // Compare the segments.
                    var leftIndex = leftLimit
                    var rightIndex = rightLimit
                    while true {
                        var leftSecondary: UInt32 = 0
                        while leftSecondary == 0 && leftIndex > leftStart {
                            leftIndex -= 1
                            leftSecondary = UInt32(truncatingIfNeeded: left.ces[leftIndex]) >> 16
                        }

                        var rightSecondary: UInt32 = 0
                        while rightSecondary == 0 && rightIndex > rightStart {
                            rightIndex -= 1
                            rightSecondary = UInt32(truncatingIfNeeded: right.ces[rightIndex]) >> 16
                        }

                        if leftSecondary != rightSecondary {
                            return leftSecondary < rightSecondary ? -1 : 1
                        }
                        if leftSecondary == 0 { break }
                    }

                    // Both strings have the same number of merge separators, or else there would have been a primary-level difference.
                    if p == CollationConstants.noCEPrimary { break }
                    // Skip both merge separators and continue.
                    leftStart = leftLimit + 1
                    rightStart = rightLimit + 1
                }
            }
        }

        if (options & CollationOptions.Bits.caseLevel) != 0 {
            var leftIndex = 0
            var rightIndex = 0
            while true {
                var leftCase: UInt32
                var leftLower32: UInt32
                var rightCase: UInt32
                if strength == CollationOptions.Strength.primary.rawValue {
                    // Primary+caseLevel: Ignore case level weights of primary ignorables. Otherwise we would get a-umlaut > a which is not desirable for accent-insensitive sorting. Check for (lower 32 bits) == 0 as well because variable CEs are stored with only primary weights.
                    var ce: Int64
                    repeat {
                        ce = left.ces[leftIndex]
                        leftIndex += 1
                        leftCase = UInt32(truncatingIfNeeded: ce)
                    } while UInt32(truncatingIfNeeded: ce >> 32) == 0 || leftCase == 0
                    leftLower32 = leftCase
                    leftCase &= 0xc000

                    repeat {
                        ce = right.ces[rightIndex]
                        rightIndex += 1
                        rightCase = UInt32(truncatingIfNeeded: ce)
                    } while UInt32(truncatingIfNeeded: ce >> 32) == 0 || rightCase == 0
                    rightCase &= 0xc000
                } else {
                    // Secondary+caseLevel and Tertiary+caseLevel: Ignore case level weights of secondary ignorables. (Otherwise a tertiary CE's uppercase would be no greater than a primary/secondary CE's uppercase; see UCA well-formedness condition 2 and LDML Collation, Case Parameters.)
                    repeat {
                        leftCase = UInt32(truncatingIfNeeded: left.ces[leftIndex])
                        leftIndex += 1
                    } while leftCase <= 0xffff
                    leftLower32 = leftCase
                    leftCase &= 0xc000

                    repeat {
                        rightCase = UInt32(truncatingIfNeeded: right.ces[rightIndex])
                        rightIndex += 1
                    } while rightCase <= 0xffff
                    rightCase &= 0xc000
                }

                // No need to handle NO_CE and MERGE_SEPARATOR specially: There is one case weight for each previous-level weight, so level length differences were handled there.
                if leftCase != rightCase {
                    if (options & CollationOptions.Bits.upperFirst) == 0 {
                        return leftCase < rightCase ? -1 : 1
                    } else {
                        return leftCase < rightCase ? 1 : -1
                    }
                }
                if (leftLower32 >> 16) == CollationConstants.noCEWeight16 { break }
            }
        }
        if strength <= CollationOptions.Strength.secondary.rawValue { return 0 }

        let tertiaryMask = CollationOptions.tertiaryMask(of: options)

        var leftIndex = 0
        var rightIndex = 0
        var anyQuaternaries: UInt32 = 0
        while true {
            var leftLower32: UInt32
            var leftTertiary: UInt32
            repeat {
                leftLower32 = UInt32(truncatingIfNeeded: left.ces[leftIndex])
                leftIndex += 1
                anyQuaternaries |= leftLower32
                assert((leftLower32 & CollationConstants.onlyTertiaryMask) != 0 || (leftLower32 & 0xc0c0) == 0)
                leftTertiary = leftLower32 & tertiaryMask
            } while leftTertiary == 0

            var rightLower32: UInt32
            var rightTertiary: UInt32
            repeat {
                rightLower32 = UInt32(truncatingIfNeeded: right.ces[rightIndex])
                rightIndex += 1
                anyQuaternaries |= rightLower32
                assert((rightLower32 & CollationConstants.onlyTertiaryMask) != 0 || (rightLower32 & 0xc0c0) == 0)
                rightTertiary = rightLower32 & tertiaryMask
            } while rightTertiary == 0

            if leftTertiary != rightTertiary {
                if CollationOptions.sortsTertiaryUpperCaseFirst(options) {
                    // Pass through NO_CE and keep real tertiary weights larger than that. Do not change the artificial uppercase weight of a tertiary CE (0.0.ut), to keep tertiary CEs well-formed. Their case+tertiary weights must be greater than those of primary and secondary CEs.
                    if leftTertiary > CollationConstants.noCEWeight16 {
                        if leftLower32 > 0xffff {
                            leftTertiary ^= 0xc000
                        } else {
                            leftTertiary += 0x4000
                        }
                    }
                    if rightTertiary > CollationConstants.noCEWeight16 {
                        if rightLower32 > 0xffff {
                            rightTertiary ^= 0xc000
                        } else {
                            rightTertiary += 0x4000
                        }
                    }
                }
                return leftTertiary < rightTertiary ? -1 : 1
            }
            if leftTertiary == CollationConstants.noCEWeight16 { break }
        }
        if strength <= CollationOptions.Strength.tertiary.rawValue { return 0 }

        if !anyVariable && (anyQuaternaries & 0xc0) == 0 {
            // If there are no "variable" CEs and no non-zero quaternary weights, then there are no quaternary differences.
            return 0
        }

        leftIndex = 0
        rightIndex = 0
        while true {
            var leftQuaternary: UInt32
            repeat {
                let ce = left.ces[leftIndex]
                leftIndex += 1
                leftQuaternary = UInt32(truncatingIfNeeded: ce) & 0xffff
                if leftQuaternary <= CollationConstants.noCEWeight16 {
                    // Variable primary or completely ignorable or NO_CE.
                    leftQuaternary = UInt32(truncatingIfNeeded: ce >> 32)
                } else {
                    // Regular CE, not tertiary ignorable. Preserve the quaternary weight in bits 7..6.
                    leftQuaternary |= 0xffff_ff3f
                }
            } while leftQuaternary == 0

            var rightQuaternary: UInt32
            repeat {
                let ce = right.ces[rightIndex]
                rightIndex += 1
                rightQuaternary = UInt32(truncatingIfNeeded: ce) & 0xffff
                if rightQuaternary <= CollationConstants.noCEWeight16 {
                    rightQuaternary = UInt32(truncatingIfNeeded: ce >> 32)
                } else {
                    rightQuaternary |= 0xffff_ff3f
                }
            } while rightQuaternary == 0

            if leftQuaternary != rightQuaternary {
                // Return the difference, with script reordering.
                if let reordering {
                    leftQuaternary = reordering.reorder(leftQuaternary)
                    rightQuaternary = reordering.reorder(rightQuaternary)
                }
                return leftQuaternary < rightQuaternary ? -1 : 1
            }
            if leftQuaternary == CollationConstants.noCEPrimary { break }
        }
        return 0
    }
}
