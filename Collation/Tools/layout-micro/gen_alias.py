#!/usr/bin/env python3
# Second micro test: two short pieces of code that each end in a ret, as in the b30a9e66 build:
#   piece A (8 instructions: 6 x ldp, add sp, ret) = the exit of f, reached by a jump (like compareUTF8's exit);
#   piece B (3 instructions: and, sub, ret) = a small function g, reached by a call (like Order.rawValue.getter).
# B starts DELTA bytes after A. The loop calls f, then g.
deltas = [64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 0xd800, 2048 + 4, 2048 + 64, 4096 + 64, 3072, 0x1800, 1024 + 4, 10240]
s = []; names = []
for d in deltas:
    tag = f"d{d}"; names.append(tag)
    s += ["\t.p2align 14", f"\t.globl _run2_{tag}", f"_run2_{tag}:",
          "\tstp x29, x30, [sp, #-32]!", "\tstp x20, x19, [sp, #16]", "\tmov x19, x0",
          f"1:\tbl _f2_{tag}", f"\tbl _g2_{tag}", "\tsubs x19, x19, #1", "\tb.ne 1b",
          "\tldp x20, x19, [sp, #16]", "\tldp x29, x30, [sp], #32", "\tret",
          "\t.p2align 6", f"_f2_{tag}:", "\tsub sp, sp, #0x80"] + \
         [f"\tstp x{a}, x{b}, [sp, #{o:#x}]" for a, b, o in ((28,27,0x20),(26,25,0x30),(24,23,0x40),(22,21,0x50),(20,19,0x60),(29,30,0x70))] + \
         ["\tcmp x19, #0", "\tb 2f", "\t.p2align 6", "2:\tmov w8, #-1", "\tcneg w0, w8, hs", "\tb 3f",
          "\t.p2align 14", "\t.space 0x57c", "3:"] + \
         [f"\tldp x{a}, x{b}, [sp, #{o:#x}]" for a, b, o in ((29,30,0x70),(20,19,0x60),(22,21,0x50),(24,23,0x40),(26,25,0x30),(28,27,0x20))] + \
         ["\tadd sp, sp, #0x80", "\tret", f"\t.space {d - 32}", f"_g2_{tag}:", "\tand x8, x0, #0xff", "\tsub x0, x8, #1", "\tret"]
open("micro_alias.S", "w").write("\t.text\n" + "\n".join(s) + "\n")
open("table.h", "w").write("".join(f"extern long run2_{t}(long);\n" for t in names) +
    "static struct { const char *name; long (*fn)(long); } cases[] = {\n" + "".join(f'  {{"{t}", run2_{t}}},\n' for t in names) + "};\n")
