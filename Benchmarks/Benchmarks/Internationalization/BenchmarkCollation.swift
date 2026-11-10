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

import Benchmark
import func Benchmark.blackHole

#if os(macOS) && USE_PACKAGE
import FoundationEssentials
import FoundationInternationalization
#else
import Foundation
#endif

private struct CollationItem {
    let name: String
}

/// The collation APIs on five corpora: random ASCII words, random Latin words with accents, random CJK ideograph words, sorted file paths, and Thai dictionary words in random order.
///
/// One iteration is one pass over a corpus: a compare entry compares each line with the next one, a search entry searches each line for the first four characters of the second line, and a sort entry sorts all lines. The results go into one sum per pass, so that `blackHole` runs once per pass and not once per call.
func collationBenchmarks() {
    let configuration = Benchmark.Configuration(
        metrics: [.cpuTotal, .wallClock, .throughput],
        maxDuration: .seconds(1),
        maxIterations: 100_000)
    let locale = Locale(identifier: "en")

    for corpus in ["ascii", "latin", "cjk", "paths", "thai"] {
        guard let path = collationCorpusPath("collation-\(corpus)"),
              let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            fatalError("The collation corpus \(corpus) is missing from the resources")
        }
        let lines = text.split(separator: "\n").map(String.init)
        let needle = String(lines[1].prefix(4))
        let items = lines.map { CollationItem(name: $0) }

        // MARK: Compare

        Benchmark("Collation-localizedCompare-\(corpus)", configuration: configuration) { benchmark in
            var sum = 0
            for i in 1..<lines.count {
                sum &+= lines[i - 1].localizedCompare(lines[i]).rawValue
            }
            blackHole(sum)
        }

        Benchmark("Collation-localizedStandardCompare-\(corpus)", configuration: configuration) { benchmark in
            var sum = 0
            for i in 1..<lines.count {
                sum &+= lines[i - 1].localizedStandardCompare(lines[i]).rawValue
            }
            blackHole(sum)
        }

        Benchmark("Collation-localizedCaseInsensitiveCompare-\(corpus)", configuration: configuration) { benchmark in
            var sum = 0
            for i in 1..<lines.count {
                sum &+= lines[i - 1].localizedCaseInsensitiveCompare(lines[i]).rawValue
            }
            blackHole(sum)
        }

        Benchmark("Collation-compareLocale-\(corpus)", configuration: configuration) { benchmark in
            var sum = 0
            for i in 1..<lines.count {
                sum &+= lines[i - 1].compare(lines[i], locale: locale).rawValue
            }
            blackHole(sum)
        }

        Benchmark("Collation-compareOptionsLocale-\(corpus)", configuration: configuration) { benchmark in
            var sum = 0
            for i in 1..<lines.count {
                sum &+= lines[i - 1].compare(lines[i], options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: locale).rawValue
            }
            blackHole(sum)
        }

        // MARK: Search

        Benchmark("Collation-localizedStandardContains-\(corpus)", configuration: configuration) { benchmark in
            var sum = 0
            for line in lines {
                sum &+= line.localizedStandardContains(needle) ? 1 : 0
            }
            blackHole(sum)
        }

        Benchmark("Collation-localizedCaseInsensitiveContains-\(corpus)", configuration: configuration) { benchmark in
            var sum = 0
            for line in lines {
                sum &+= line.localizedCaseInsensitiveContains(needle) ? 1 : 0
            }
            blackHole(sum)
        }

        Benchmark("Collation-localizedStandardRange-\(corpus)", configuration: configuration) { benchmark in
            var sum = 0
            for line in lines {
                sum &+= line.localizedStandardRange(of: needle) == nil ? 0 : 1
            }
            blackHole(sum)
        }

        Benchmark("Collation-rangeLocale-\(corpus)", configuration: configuration) { benchmark in
            var sum = 0
            for line in lines {
                sum &+= line.range(of: needle, options: [], locale: locale) == nil ? 0 : 1
            }
            blackHole(sum)
        }

        Benchmark("Collation-rangeBackwardsLocale-\(corpus)", configuration: configuration) { benchmark in
            var sum = 0
            for line in lines {
                sum &+= line.range(of: needle, options: [.backwards], locale: locale) == nil ? 0 : 1
            }
            blackHole(sum)
        }

        // MARK: Sort

        Benchmark("Collation-sortStandardComparator-\(corpus)", configuration: configuration) { benchmark in
            blackHole(lines.sorted(using: String.StandardComparator.localizedStandard))
        }

        Benchmark("Collation-sortComparatorLocale-\(corpus)", configuration: configuration) { benchmark in
            blackHole(lines.sorted(using: String.Comparator(options: [], locale: locale)))
        }

        Benchmark("Collation-sortKeyPathComparator-\(corpus)", configuration: configuration) { benchmark in
            blackHole(items.sorted(using: KeyPathComparator(\CollationItem.name, comparator: String.StandardComparator.localizedStandard)))
        }

        Benchmark("Collation-sortSortDescriptor-\(corpus)", configuration: configuration) { benchmark in
            blackHole(items.sorted(using: SortDescriptor(\CollationItem.name, comparator: String.StandardComparator.localizedStandard)))
        }
    }
}
