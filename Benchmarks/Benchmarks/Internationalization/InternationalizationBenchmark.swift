import Benchmark

#if os(macOS) && USE_PACKAGE
import FoundationEssentials
#else
import Foundation
#endif

#if os(macOS) && USE_PACKAGE
let benchmarks = {
    calendarBenchmarks()
    // localeBenchmarks()      // TEMP: skip locale benches during Hebrew perf work
    // timeZoneBenchmarks()    // TEMP: skip TZ benches during Hebrew perf work
}
#endif
