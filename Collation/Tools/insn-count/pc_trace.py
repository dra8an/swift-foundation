# lldb command: pc_trace <out.txt> <calls>
# Run it when the process stops at the first instruction of the measured function (a breakpoint there). It
# single-steps and writes the FILE address (hex) of every executed instruction of the main executable, one per
# line, until the function was entered <calls> more times. A line "C <n>" marks the n-th entry; a line "L ..."
# stands for an instruction in another image. So the file holds <calls> whole passes of the loop around the
# function: the function AND the loop, which count_insns.py does not see (technique log §52 (k)).
import lldb


def pc_trace(debugger, command, result, internal_dict):
    out_path, calls = command.split()
    calls = int(calls)
    target = debugger.GetSelectedTarget()
    thread = target.GetProcess().GetSelectedThread()
    entry = thread.GetFrameAtIndex(0).GetPC()
    exe = target.GetModuleAtIndex(0)
    # Without this, a step that lands on the entry stops there twice (the step, then the breakpoint).
    debugger.HandleCommand("breakpoint disable")
    seen = 0
    n = 0
    with open(out_path, "w") as f:
        while True:
            frame = thread.GetFrameAtIndex(0)
            if frame.GetPC() == entry:
                seen += 1
                if seen > calls:
                    break
                f.write(f"C {seen}\n")
            a = frame.GetPCAddress()
            if a.GetModule() == exe:
                f.write(f"{a.GetFileAddress():x}\n")
            else:
                f.write(f"L {a.GetModule().GetFileSpec().GetFilename()}\n")
            n += 1
            thread.StepInstruction(False)
    print(f"pc_trace: {n} instructions, {calls} calls", flush=True)


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand("command script add -f pc_trace.pc_trace pc_trace")
