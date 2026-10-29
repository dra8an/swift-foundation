import Testing
@testable import FoundationInternationalization

/// `RootCollator.order(fromFastResult:)` maps a fast-path result to its Order by the enum's storage tag (technique log §51 (ah)). If the declaration order of `Order` ever changes, this fails.
@Suite struct FastResultOrderTests {
    @Test func mapsEachResult() {
        #expect(RootCollator.order(fromFastResult: -1) == .ascending)
        #expect(RootCollator.order(fromFastResult: 0) == .same)
        #expect(RootCollator.order(fromFastResult: 1) == .descending)
        #expect(MemoryLayout<RootCollator.Order>.size == 1)
    }
}
