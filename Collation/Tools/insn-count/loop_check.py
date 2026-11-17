#!/usr/bin/env python3
# Reads a pc_trace recording of EngineBench's compare loop (see loop_check.sh) and prints one line:
#   instructions per pass inside compare (the engine) and outside it (the benchmark loop), taken branches,
#   the two position rules, and the difference to the reference file.
# Usage: python3 -I loop_check.py <trace.txt> <binary> <corpus> <reference file> [--write-ref]
# Exit status 1: the loop count differs from the reference, or a position rule applies.
#
# The two position rules (Apple M1 Max, found 2026-11-13, technique log §52 (k), corrected in (n); the micro tests
# are in Tools/layout-micro):
#   1. The processor takes in code in pieces of at most 16 instructions; a taken branch ends a piece, and so does a
#      4 KB address boundary (a 64-byte boundary does not). Shown for a run that ENDS IN A RETURN: a boundary that
#      makes such a hot run need one more piece cost 0.5-0.7 ns per compare. A cut run that ends in a call was
#      measured without a loss, so the tool reports other runs as a note, not as an error.
#   2. Two hot pieces that both end in a return collide when their start addresses are a multiple of 2 KB apart
#      (the piece is the last piece of the run, after the cuts of rule 1).
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

# The return address of each call: the instruction after the call instruction that precedes its entry. `main` has
# two copies of the loop (the warm-up pass and the timed passes), so one address for the whole file is wrong when a
# recording crosses from one copy to the other.
marks = [i for i, e in enumerate(entries) if e == "C"]
returns = {}
for k, i in enumerate(marks):
    if i > 0 and isinstance(entries[i - 1], int):
        returns[k] = entries[i - 1] + 4
if not returns:
    sys.exit(f"{corpus}: no call site found in the recording")
first_known = returns[min(returns)]
call_sites = sorted(set(returns.values()))

inside = outside = taken = 0
in_call = False
return_address = None
call_index = -1
runs = collections.Counter()        # (start, last) of each straight run -> executions
start = prev = None
for e in entries:
    if e == "C":
        call_index += 1
        in_call = True
        return_address = returns.get(call_index, first_known)
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
            taken += 1                  # transitions inside the main executable only
        start = e
    prev = e
if start is not None:
    runs[(start, prev)] += 1


def piece_starts(first, last, cut):
    """Start addresses of the pieces of the run first...last; with cut, a 4 KB boundary ends a piece."""
    starts = []
    a = first
    while a <= last:
        end = last
        if cut:
            end = min(end, (a | (PAGE - 1)) - 3)      # the last instruction before the next boundary
        b = a
        while b <= end:
            starts.append(b)
            b += 4 * PIECE
        a = end + 4
    return starts


mnemonic = {}
for line in subprocess.run(["xcrun", "objdump", "-d", "--no-show-raw-insn", binary],
                           capture_output=True, text=True).stdout.splitlines():
    m = re.match(r"^\s*([0-9a-f]+):\s+(\S+)", line)
    if m:
        mnemonic[int(m.group(1), 16)] = m.group(2)

rule1 = []          # a 4 KB boundary adds a piece to a hot run that ends in a return
rule1_notes = []    # the same for a run that ends in another instruction: reported, not an error
ret_starts = set()
for (first, last), count in sorted(runs.items()):
    if count / calls < HOT:
        continue
    ends_in_return = mnemonic.get(last, "").startswith("ret")
    cut_starts = piece_starts(first, last, True)
    if ends_in_return:
        ret_starts.add(cut_starts[-1])
    added = len(cut_starts) - len(piece_starts(first, last, False))
    if added:
        before = ((first | (PAGE - 1)) + 1 - first) // 4
        text = (f"run at {first:#x}, {(last - first) // 4 + 1} instructions, ends in {mnemonic.get(last, '?')}, "
                f"boundary after {before}, {count / calls:.2f} per pass")
        (rule1 if ends_in_return else rule1_notes).append(text)
ret_starts = sorted(ret_starts)
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
    print(f"       rule 1 (a 4 KB boundary cuts a hot run that ends in a return): {r}")
for r in rule1_notes:
    print(f"       note (a 4 KB boundary cuts a hot run that does not end in a return; no loss was measured for such a run): {r}")
if len(call_sites) > 1:
    print(f"       note: the recording has {len(call_sites)} call sites of the function (two copies of the loop)")
for r in rule2:
    print(f"       rule 2 (two return-ended pieces a multiple of 2 KB apart): {r}")

if write_ref:
    reference[corpus] = (engine, loop, branches)
    with open(ref_path, "w") as f:
        f.write("# Reference of loop_check.sh: corpus, instructions per pass inside compare, outside it, taken branches.\n")
        for name in sorted(reference):
            f.write(f"{name} {reference[name][0]:.3f} {reference[name][1]:.3f} {reference[name][2]:.3f}\n")
sys.exit(status)
