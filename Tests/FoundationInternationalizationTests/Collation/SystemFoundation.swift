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

// What the tests take from the system Foundation: the NFD reference of NormalizationTests and bridged strings for the fallback input of the NFD front end. Only on macOS: on the other platforms, Foundation is built on top of this package, so its tests cannot import it. In its own file, so that no other test file sees the system Foundation.
#if os(macOS)
import Foundation

func systemNFD(_ s: String) -> String {
    s.decomposedStringWithCanonicalMapping
}

/// A bridged copy of `s`: an NSString-backed String whose UTF-8 is not contiguous.
func bridgedCopy(_ s: String) -> String {
    NSString(string: s) as String
}
#else
/// Without the Objective-C bridge every String is native and contiguous: there is no second input form, so the copy is the string itself.
func bridgedCopy(_ s: String) -> String {
    s
}
#endif
