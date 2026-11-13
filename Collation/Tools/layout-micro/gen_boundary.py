#!/usr/bin/env python3
# Generates micro.S and table.h: for each case a loop "run" that calls "f"; f saves registers, jumps to a far block,
# and the far block jumps to the epilogue (P nops, 6 x ldp, add sp, ret) — the shape of compareUTF8's exit.
# The jump target (the first instruction of that run) sits D instructions before a boundary:
#   kind p4k: a 4 KB boundary;  kind l64: a 64-byte boundary that is not a 4 KB boundary.
cases = []
for kind, off in (("p4k", 4096), ("l64", 4096 + 192)):
    for P in (0, 12):
        for D in range(0, 9 if P == 0 else 21):
            cases.append((f"{kind}_P{P}_D{D}", off, P, D))
s = []
for tag, off, P, D in cases:
    s += [f"\t.p2align 12", f"\t.globl _run_{tag}", f"_run_{tag}:",
          "\tstp x29, x30, [sp, #-32]!", "\tstp x20, x19, [sp, #16]", "\tmov x19, x0",
          f"1:\tbl _f_{tag}", "\tsubs x19, x19, #1", "\tb.ne 1b",
          "\tldp x20, x19, [sp, #16]", "\tldp x29, x30, [sp], #32", "\tret",
          "\t.p2align 6", f"_f_{tag}:", "\tsub sp, sp, #0x80"] + \
         [f"\tstp x{a}, x{b}, [sp, #{o:#x}]" for a, b, o in ((28,27,0x20),(26,25,0x30),(24,23,0x40),(22,21,0x50),(20,19,0x60),(29,30,0x70))] + \
         ["\tcmp x19, #0", "\tb 2f", "\t.p2align 12", f"\t.space {off - 4 * D}", "3:"] + ["\tnop"] * P + \
         [f"\tldp x{a}, x{b}, [sp, #{o:#x}]" for a, b, o in ((29,30,0x70),(20,19,0x60),(22,21,0x50),(24,23,0x40),(26,25,0x30),(28,27,0x20))] + \
         ["\tadd sp, sp, #0x80", "\tret", "\t.p2align 6", "2:\tmov w8, #-1", "\tcneg w0, w8, hs", "\tb 3b"]
open("micro.S", "w").write("\t.text\n" + "\n".join(s) + "\n")
open("table.h", "w").write("".join(f"extern long run_{t}(long);\n" for t, *_ in cases) +
    "static struct { const char *name; long (*fn)(long); } cases[] = {\n" + "".join(f'  {{"{t}", run_{t}}},\n' for t, *_ in cases) + "};\n")
