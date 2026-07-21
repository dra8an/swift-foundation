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

extension Calendar {
    /// Time unit constants shared across calendar implementations.
    static let _kSecondsInWeek = 604_800
    static let _kSecondsInDay = 86400
    static let _kSecondsInHour = 3600
    static let _kSecondsInMinute = 60

    // Upstream renamed these without the _k prefix (guideline PR #2091); aliases until this research base is resynced.
    static let _secondsInWeek = _kSecondsInWeek
    static let _secondsInDay = _kSecondsInDay
    static let _secondsInHour = _kSecondsInHour
    static let _secondsInMinute = _kSecondsInMinute

    /// Sentinel used by unbounded range loops in date arithmetic.
    static let _inf_ti: TimeInterval = 4398046511104.0
}
