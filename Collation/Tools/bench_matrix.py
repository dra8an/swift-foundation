#!/usr/bin/env python3
# Benchmark matrix runner — see Docs/27-benchmark-runbook.md.
#
# Runs the three harnesses over the standard corpora and prints two tables:
#   Table 1  pure collator engine: ours (RootCollator) vs ICU C library
#   Table 2  Foundation APIs:      ours vs system ICU (NSString -> ICU)
# Reports the MIN ns/op over K interleaved runs (min = least OS-perturbed pass;
# BenchFoundation/bench_system also take the min over 9 internal passes).
#
# Usage:   python3 Collation/Tools/bench_matrix.py <BenchFoundation-binary> [K]
# Run from the repo root (the dir containing Collation/). Env overrides:
#   ICU_BIN  built bench_icu binary   (default: Collation/Tools/bench_icu)
#   ICU_LIB  ICU dylib dir for DYLD   (default: ~/Projects/claude/collation/icu-build/lib)
# The companion run_benchmarks.sh builds all three harnesses then calls this.

import os, subprocess, sys, re

if len(sys.argv) < 2:
    sys.exit("usage: bench_matrix.py <BenchFoundation-binary> [K]   (run from repo root)")
BF   = sys.argv[1]
K    = int(sys.argv[2]) if len(sys.argv) > 2 else 7
HOME = os.path.expanduser("~")
ICU_BIN = os.environ.get("ICU_BIN", "Collation/Tools/bench_icu")
ICU_LIB = os.environ.get("ICU_LIB", f"{HOME}/Projects/claude/collation/icu-build/lib")
SYS_SCRIPT = "Collation/Tools/bench_system_foundation.swift"
# Precompiled bench_system binary (run_benchmarks.sh builds it once);
# fallback recompiles the script per run, which dominates wall time at K>1.
SYS_BIN = os.environ.get("SYS_BIN")
# Full-WMO engine-only bench (build_engine_bench.sh) for Table 1: measures
# the shipping optimization level even on machine 1, where the full
# BenchFoundation executable must build -no-WMO (Locale SIGILL, Docs/25).
# Falls back to the BenchFoundation numbers when unset.
ENGINE_BIN = os.environ.get("ENGINE_BIN")

# (label, corpus file, locale-or-None for ICU bin, reps) — reps equalize work
# (thai is ~33k lines vs ~200-440 for the rest).
CORPORA = [
    ("ascii", "Collation/Tools/bench/bench-ascii.txt", None, 300),
    ("latin", "Collation/Tools/bench/bench-latin.txt", None, 300),
    ("cjk",   "Collation/Tools/bench/bench-cjk.txt",   None, 300),
    ("paths", "Collation/Tools/bench/bench-paths.txt", None, 150),
    # thai is ~33k lines per rep already; 10 reps for tighter mins.
    # ICU gets the root collator like ours (a "th"-tailored ICU collator is
    # ~9% slower on this corpus and was never the same data table as ours).
    ("thai",  "Collation/Tools/bench/bench-thai.txt",  None,  10),
]
pat = re.compile(r"\s*([A-Za-z().:_ ]+?)\s*:\s*(\d+)\s*ns/op")

def best(cmd, env_extra=None, runs=K):
    env = {**os.environ, **(env_extra or {})}
    out_min = {}
    for _ in range(runs):
        out = subprocess.run(cmd, capture_output=True, text=True, env=env).stdout
        for line in out.splitlines():
            m = pat.match(line)
            if m:
                k, v = m.group(1).strip(), int(m.group(2))
                out_min[k] = min(out_min.get(k, 1 << 62), v)
    return out_min

def ratio(a, b):
    return f"{a/b:.2f}x" if (a and b) else "  -"

results = {}
for label, corpus, loc, reps in CORPORA:
    icu  = best([ICU_BIN, corpus, str(reps)] + ([loc] if loc else []),
               {"DYLD_LIBRARY_PATH": ICU_LIB})
    ours = best([BF, corpus, str(reps)])
    if ENGINE_BIN:
        ours.update(best([ENGINE_BIN, corpus, str(reps)]))
    sys_cmd = [SYS_BIN] if SYS_BIN else ["swift", "-O", SYS_SCRIPT]
    sysf = best(sys_cmd + [corpus, str(reps)])
    results[label] = {"icu": icu, "ours": ours, "sys": sysf}

eng = "engine rows FULL-WMO via EngineBench" if ENGINE_BIN else "engine rows -no-WMO (set ENGINE_BIN!)"
print(f"\nK={K}  min ns/op over interleaved runs. {eng}; Foundation rows -no-WMO on machine 1 (Docs/27).")
print("\n================ TABLE 1: PURE COLLATOR ENGINE (ours vs ICU C) ================")
print(f"{'corpus':6} | {'cmp ICU':>7} {'ours':>5} {'ratio':>6} | {'sk ICU':>7} {'ours':>6} {'ratio':>6} | {'skRet':>6} {'ratio':>6}")
print("-" * 80)
for label, _, _, _ in CORPORA:
    r = results[label]
    ic, oc = r["icu"].get("compare"), r["ours"].get("RootCollator.cmp")
    isk, osk = r["icu"].get("sortKey"), r["ours"].get("RootCollator.sk")
    # skRet = the allocating sortKey variant, vs the same ICU reference
    osr = r["ours"].get("RootCollator.skRet")
    print(f"{label:6} | {ic or '-':>7} {oc or '-':>5} {ratio(oc,ic):>6} | "
          f"{isk or '-':>7} {osk or '-':>6} {ratio(osk,isk):>6} | "
          f"{osr or '-':>6} {ratio(osr,isk):>6}")

print("\n===== TABLE 2: FOUNDATION APIs (speedup = sys/ours; >1 = ours faster) =====")
APIS = ["compare(locale:)", "localizedCompare", "localizedStdCmp",
        "localizedCaseICmp", "localizedStdContns", "localizedCaseICnt",
        "localizedStdRange", "range(of:locale:)", "range(backwards)"]
for api in APIS:
    print(f"\n--- {api} ---")
    print(f"{'corpus':6} | {'sysICU':>7} {'ours':>7} {'speedup':>7}")
    for label, _, _, _ in CORPORA:
        s = results[label]["sys"].get(api)
        o = results[label]["ours"].get(api)
        print(f"{label:6} | {s or '-':>7} {o or '-':>7} {ratio(s,o):>7}")
