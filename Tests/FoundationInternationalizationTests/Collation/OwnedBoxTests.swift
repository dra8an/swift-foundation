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

/// `OwnedBox` holds the setup values of a collator. It must keep its value for its whole life and end the value's life exactly once, when the box ends.
@Suite struct OwnedBoxTests {
    final class Counter { var ended = 0 }

    struct Tracked: ~Copyable {
        let counter: Counter
        var payload: Int
        deinit { counter.ended += 1 }
    }

    final class Holder {
        let box: OwnedBox<Tracked>
        init(_ counter: Counter) { box = OwnedBox(Tracked(counter: counter, payload: 7)) }
    }

    @Test func keepsItsValueAndChangesItInPlace() {
        let box = OwnedBox((a: UInt32(1), b: UInt32(2)))
        #expect(box.pointer.pointee.a == 1 && box.pointer.pointee.b == 2)
        box.pointer.pointee.b = 5
        #expect(box.pointer.pointee.a == 1 && box.pointer.pointee.b == 5)
    }

    @Test func endsItsValueOnceWhenTheBoxEnds() {
        let counter = Counter()
        do {
            let box = OwnedBox(Tracked(counter: counter, payload: 3))
            box.pointer.pointee.payload += 1
            #expect(box.pointer.pointee.payload == 4)
            #expect(counter.ended == 0)
        }
        #expect(counter.ended == 1)
    }

    @Test func endsItsValueOnceWhenItsOwnerEnds() {
        let counter = Counter()
        var holder: Holder? = Holder(counter)
        #expect(holder?.box.pointer.pointee.payload == 7)
        #expect(counter.ended == 0)
        holder = nil
        #expect(holder == nil && counter.ended == 1)
    }
}
