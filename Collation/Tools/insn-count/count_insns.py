# Instruction count of ONE call, under lldb (technique log §50 (g)).
# Use Xcode's lldb: /Applications/Xcode*.app/Contents/Developer/usr/bin/lldb
# (the swiftly toolchain's lldb lacks its Python framework). Build the target
# with `-Xswiftc -g` so lldb finds the names in the .dSYM. Example, 10 ascii
# pairs through the compare ladder's count mode:
#   lldb -b -o "command script import count_insns.py" \
#        -o "breakpoint set -n countPublic" -o run \
#        -o "count_insns swift out.jsonl" -o continue  (repeat the last two) \
#        -- CmpLadder <corpus> 1 count 1 10
# For EngineBench (no wrapper): break on compareFastPath and skip the warm-up
# calls with `breakpoint modify -i <n> 1`.
# Usage inside lldb, stopped at the entry of the wrapper (countPublic / count_icu):
#   command script import count_insns.py
#   count_insns <label> <output.jsonl>
# Single-steps (stepping INTO every callee) until execution reaches the
# wrapper's return address, and appends {"label", "total", "by_key"} to the
# output file, where a key is "module|function|file:line" of each executed
# instruction. Prints the first functions it enters and periodic progress.
import collections
import json
import sys
import lldb

LIMIT = 20000


def count_insns(debugger, command, result, internal_dict):
    label, out_path = command.split()
    thread = debugger.GetSelectedTarget().GetProcess().GetSelectedThread()
    # Skip inlined (virtual) frames: the wrapper's real frame is the first one
    # that is not inlined, and its caller holds the return address.
    i = 0
    while thread.GetFrameAtIndex(i).IsInlined():
        i += 1
    return_pc = thread.GetFrameAtIndex(i + 1).GetPC()
    print(f"{label}: start pc {hex(thread.GetFrameAtIndex(0).GetPC())}, return pc {hex(return_pc)}", flush=True)
    by_key = collections.Counter()
    total = 0
    last_function = None
    entered = 0
    while total < LIMIT:
        frame = thread.GetFrameAtIndex(0)
        if frame.GetPC() == return_pc:
            break
        module = frame.GetModule().GetFileSpec().GetFilename() or "?"
        sym = frame.GetSymbol()
        function = sym.GetName() if sym.IsValid() else hex(frame.GetPC())
        if function != last_function and entered < 40:
            print(f"  [{total}] {module}: {function[:110]}", flush=True)
            entered += 1
        last_function = function
        le = frame.GetLineEntry()
        where = f"{le.GetFileSpec().GetFilename()}:{le.GetLine()}" if le.IsValid() else "?"
        by_key[f"{module}|{function}|{where}"] += 1
        total += 1
        if total % 2000 == 0:
            print(f"  ... {total} instructions", flush=True)
        thread.StepInstruction(False)
    status = "complete" if total < LIMIT else "LIMIT REACHED"
    with open(out_path, "a") as f:
        f.write(json.dumps({"label": label, "total": total, "status": status, "by_key": by_key}) + "\n")
    print(f"{label}: {total} instructions ({status})", flush=True)


def trace_insns(debugger, command, result, internal_dict):
    """trace_insns <output.txt>: like count_insns, but writes the executed
    instruction sequence, one "function: mnemonic operands" line per step,
    with immediate addresses masked, so two builds can be diffed."""
    out_path = command.strip()
    target = debugger.GetSelectedTarget()
    thread = target.GetProcess().GetSelectedThread()
    i = 0
    while thread.GetFrameAtIndex(i).IsInlined():
        i += 1
    return_pc = thread.GetFrameAtIndex(i + 1).GetPC()
    steps = []
    while len(steps) < LIMIT:
        frame = thread.GetFrameAtIndex(0)
        if frame.GetPC() == return_pc:
            break
        sym = frame.GetSymbol()
        function = sym.GetName() if sym.IsValid() else "?"
        insn = target.ReadInstructions(frame.GetPCAddress(), 1)[0]
        text = f"{insn.GetMnemonic(target)} {insn.GetOperands(target)}"
        import re
        text = re.sub(r"0x[0-9a-f]+", "ADDR", text)
        steps.append(f"{function[:60]}: {text}")
        thread.StepInstruction(False)
    with open(out_path, "w") as f:
        f.write("\n".join(steps) + "\n")
    print(f"traced {len(steps)} instructions", flush=True)


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand("command script add -f count_insns.count_insns count_insns")
    debugger.HandleCommand("command script add -f count_insns.trace_insns trace_insns")
