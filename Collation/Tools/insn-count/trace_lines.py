# trace_lines <out.txt>: like count_insns.py's trace_insns, but each line is "function  file:line  mnemonic operands",
# so you can see which source line a spill or a call belongs to. Import into Xcode's lldb, stop at the function, run
# `trace_lines <file>` (the trace ends at the function's return).
import lldb, re
def trace_lines(debugger, command, result, internal_dict):
    out_path = command.strip()
    target = debugger.GetSelectedTarget()
    thread = target.GetProcess().GetSelectedThread()
    i = 0
    while thread.GetFrameAtIndex(i).IsInlined(): i += 1
    return_pc = thread.GetFrameAtIndex(i + 1).GetPC()
    steps = []
    while len(steps) < 20000:
        frame = thread.GetFrameAtIndex(0)
        if frame.GetPC() == return_pc: break
        sym = frame.GetSymbol()
        fn = sym.GetName() if sym.IsValid() else "?"
        fn = re.sub(r"\(.*", "", fn).split()[-1][-40:]
        le = frame.GetLineEntry()
        where = f"{le.GetFileSpec().GetFilename()}:{le.GetLine()}" if le.IsValid() else "?"
        insn = target.ReadInstructions(frame.GetPCAddress(), 1)[0]
        steps.append(f"{fn:40s} {where:28s} {insn.GetMnemonic(target)} {insn.GetOperands(target)}")
        thread.StepInstruction(False)
    open(out_path, "w").write("\n".join(steps) + "\n")
    print(f"traced {len(steps)}")
def __lldb_init_module(debugger, d):
    debugger.HandleCommand("command script add -f trace_lines.trace_lines trace_lines")
