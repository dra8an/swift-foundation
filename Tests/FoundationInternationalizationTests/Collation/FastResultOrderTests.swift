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
@testable import FoundationInternationalization

/// `RootCollator.order(fromFastResult:)` maps a fast-path result to its Order by the enum's storage tag. If the declaration order of `Order` ever changes, this fails.
@Suite struct FastResultOrderTests {
    @Test func mapsEachResult() {
        #expect(RootCollator.order(fromFastResult: -1) == .ascending)
        #expect(RootCollator.order(fromFastResult: 0) == .same)
        #expect(RootCollator.order(fromFastResult: 1) == .descending)
        #expect(MemoryLayout<RootCollator.Order>.size == 1)
    }
}
