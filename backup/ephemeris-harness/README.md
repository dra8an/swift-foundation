# Ephemeris comparison harness (research only, never ships)

Pairs with CHINESE_PLAN § 11.28d. swecheck.c reads "label jd_ut" lines
and prints the Swiss Ephemeris sun longitude and moon-sun elongation at
each instant. Build:

    cc -O2 -I <hindu-calendar>/lib/swisseph swecheck.c \
       <hindu-calendar>/cmake-build-debug/libswisseph.a -o swecheck

Run with the ephemeris path argument for real JPL data:

    ./swecheck <hindu-calendar>/ephe < instants.txt

The JPL files (44 .se1 files, 31 MB, full span -13,200..+17,191) live
in <hindu-calendar>/ephe, downloaded 2026-07-23 from the swisseph
GitHub mirror. The Swift-side instant dumper is
Tests/FoundationInternationalizationTests/ChineseHorizonDumpScratch.swift.
Licensing: Swiss Ephemeris is dual licensed, research use only here,
nothing ships (§ 11.28c).
