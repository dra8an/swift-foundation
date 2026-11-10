import Benchmark


#if os(macOS) && USE_PACKAGE
let benchmarks = {
    calendarBenchmarks()
    localeBenchmarks()
    timeZoneBenchmarks()
    collationBenchmarks()
}
#endif
