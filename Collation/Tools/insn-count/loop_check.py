#!/usr/bin/env python3
# Reads a pc_trace recording of EngineBench's compare loop (see loop_check.sh) and prints one line:
#   instructions per pass inside compare (the engine) and outside it (the benchmark loop), taken branches,
#   the two position rules, and the difference to the reference file.
# Usage: python3 -I loop_check.py <trace.txt> <binary> <corpus> <reference file> [--write-ref]
# Exit status 1: the loop count differs from the reference, or a position rule applies.
#
# The two position rules (Apple M1 Max, found 2026-11-13, technique log §52 (k); the micro tests are in
# Tools/layout-micro):
#   1. The processor takes in code in pieces of at most 16 instructions; a taken branch ends a piece, and so does a
#      4 KB address boundary (a 64-byte boundary does not). A boundary that makes a hot run need one more piece costs
#      one cycle or more per pass.
#   2. Two hot pieces that both end in a return collide when their start addresses are a multiple of 2 KB apart.
import collections
import re
import subprocess
import sys

trace, binary, corpus, ref_path = sys.argv[1:5]
write_ref = "--write-ref" in sys.argv[5:]
HOT = 0.05          # a run counts as hot from this many executions per pass
PIECE = 16          # instructions per piece
PAGE = 4096
ALIAS = 2048

entries = []        # an int (file address), None (another image) or "C" (entry of compare)
for line in open(trace):
    if line[0] == "C":
        entries.append("C")
    elif line[0] == "L":
        entries.append(None)
    else:
        entries.append(int(line, 16))
calls = entries.count("C")
if calls < 2:
    sys.exit(f"{corpus}: the recording has {calls} calls; see the .log file next to it")

# The return address: the instruction after the call instruction that precedes the second entry.
second = [i for i, e in enumerate(entries) if e == "C"][1]
return_address = entries[second - 1] + 4

inside = outside = taken = 0
in_call = False
runs = collections.Counter()        # (start, last) of each straight run -> executions
start = prev = None
for e in entries:
    if e == "C":
        in_call = True
        continue
    if e is not None and in_call and e == return_address:
        in_call = False
    if in_call:
        inside += 1
    else:
        outside += 1
    if e is None or prev is None or e != prev + 4:
        if start is not None:
            runs[(start, prev)] += 1
        if e is not None and prev is not None:
            taken += 1
        start = e
    prev = e
if start is not None:
    runs[(start, prev)] += 1


def pieces(first, last, cut):
    """Pieces of the run first...last; with cut, a 4 KB boundary ends a piece."""
    n = 0
    a = first
    while a <= last:
        end = last
        if cut:
            end = min(end, (a | (PAGE - 1)) - 3)      # the last instruction before the next boundary
        length = (end - a) // 4 + 1
        n += -(-length // PIECE)
        a = end + 4
    return n


rule1 = []
for (first, last), count in sorted(runs.items()):
    added = pieces(first, last, True) - pieces(first, last, False)
    if added and count / calls >= HOT:
        before = ((first | (PAGE - 1)) + 1 - first) // 4
        rule1.append(f"run at {first:#x}, {(last - first) // 4 + 1} instructions, boundary after {before}, "
                     f"{count / calls:.2f} per pass")

mnemonic = {}
for line in subprocess.run(["xcrun", "objdump", "-d", "--no-show-raw-insn", binary],
                           capture_output=True, text=True).stdout.splitlines():
    m = re.match(r"^\s*([0-9a-f]+):\s+(\S+)", line)
    if m:
        mnemonic[int(m.group(1), 16)] = m.group(2)
ret_starts = sorted({first for (first, last), count in runs.items()
                     if count / calls >= HOT and mnemonic.get(last, "").startswith("ret")})
rule2 = [f"pieces at {a:#x} and {b:#x} ({abs(a - b)} bytes apart)"
         for i, a in enumerate(ret_starts) for b in ret_starts[i + 1:] if (a - b) % ALIAS == 0]

engine, loop, branches = inside / calls, outside / calls, taken / calls
reference = {}
try:
    for line in open(ref_path):
        p = line.split()
        if len(p) == 4 and not line.startswith("#"):
            reference[p[0]] = (float(p[1]), float(p[2]), float(p[3]))
except FileNotFoundError:
    pass

status = 0
if corpus not in reference:
    note = "no reference"
else:
    ref_engine, ref_loop, _ = reference[corpus]
    parts = []
    if abs(ref_loop - loop) >= 0.05:
        parts.append(f"LOOP CHANGED (reference {ref_loop:.1f}): this row is not comparable with the reference build")
        status = 1
    if abs(ref_engine - engine) >= 0.05:
        parts.append(f"engine changed (reference {ref_engine:.1f})")
    note = "; ".join(parts) or "same as the reference"
if rule1 or rule2:
    status = 1
print(f"{corpus:6s} pass {engine + loop:6.1f} = engine {engine:6.1f} + loop {loop:5.1f}   taken branches {branches:5.2f}   "
      f"rule 1: {'APPLIES' if rule1 else 'no'}   rule 2: {'APPLIES' if rule2 else 'no'}   {note}")
for r in rule1:
    print(f"       rule 1 (a 4 KB boundary cuts a hot run): {r}")
for r in rule2:
    print(f"       rule 2 (two return-ended pieces a multiple of 2 KB apart): {r}")

if write_ref:
    reference[corpus] = (engine, loop, branches)
    with open(ref_path, "w") as f:
        f.write("# Reference of loop_check.sh: corpus, instructions per pass inside compare, outside it, taken branches.\n")
        for name in sorted(reference):
            f.write(f"{name} {reference[name][0]:.1f} {reference[name][1]:.1f} {reference[name][2]:.2f}\n")
sys.exit(status)
