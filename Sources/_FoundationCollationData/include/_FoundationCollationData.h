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

#ifndef _FOUNDATION_COLLATION_DATA_H
#define _FOUNDATION_COLLATION_DATA_H

#include <stddef.h>

/// The bytes of a bundled collation resource — "ucadata" (the root data), "nfd" (the normalization data) or
/// "tailorings/<name>" (a compiled tailoring) — and their count in `length`; NULL (and length 0) for an unknown name.
/// The memory is static and immutable.
const unsigned char * _Nullable _foundation_collation_resource(const char * _Nonnull name, size_t * _Nonnull length);

#endif
