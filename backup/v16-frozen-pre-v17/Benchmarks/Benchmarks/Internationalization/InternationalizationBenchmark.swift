import Benchmark

#if os(macOS) && USE_PACKAGE
import FoundationEssentials
#else
import Foundation
#endif

#if os(macOS) && USE_PACKAGE
let benchmarks = {
    // Edit the identifier below to switch which calendar `calendarBenchmarks`
    // runs against (e.g., `.gregorian`, `.hebrew`). Run benchmarks, save the
    // numbers, edit, run again, compare. The benchmark NAMES stay the same
    // across calendars on purpose — distinguish runs by the saved baseline.
    calendarBenchmarks(.hebrew)
    // localeBenchmarks()      // TEMP: skip locale benches during Hebrew perf work
    // timeZoneBenchmarks()    // TEMP: skip TZ benches during Hebrew perf work
}
#endif
