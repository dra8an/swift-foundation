# Lists the functions of a Mach-O binary that load ___stack_chk_guard (a stack protector), from the machine code itself
# (technique log §51 (ay)): the SIL marks alone missed functions. Usage: python3 -I stack_guard_funcs.py <binary> [name filter]
import re, subprocess, sys
binary = sys.argv[1]; filt = sys.argv[2] if len(sys.argv) > 2 else ""
fix = subprocess.run(["xcrun", "dyld_info", "-fixups", binary], capture_output=True, text=True).stdout
slots = {int(m.group(1), 16) for m in re.finditer(r"__got\s+0x([0-9A-Fa-f]+)\s+bind\s+\S*___stack_chk_guard", fix)}
dis = subprocess.run(["xcrun", "objdump", "-d", "--no-show-raw-insn", binary], capture_output=True, text=True).stdout
cur = None; page = {}; hits = []
for line in dis.splitlines():
    m = re.match(r"^[0-9a-f]+ <(.+)>:$", line)
    if m: cur = m.group(1); page = {}; continue
    m = re.search(r"adrp\s+(x\d+), 0x([0-9a-f]+)", line)
    if m: page[m.group(1)] = int(m.group(2), 16); continue
    m = re.search(r"ldr\s+x\d+, \[(x\d+), #0x([0-9a-f]+)\]", line)
    if m and m.group(1) in page and page[m.group(1)] + int(m.group(2), 16) in slots:
        if cur and (not hits or hits[-1] != cur): hits.append(cur)
names = subprocess.run(["xcrun", "swift-demangle", "--simplified"], input="\n".join(hits), capture_output=True, text=True).stdout.splitlines()
names = [n for n in names if filt in n]
print(f"{len(names)} functions with a stack protector{' matching ' + repr(filt) if filt else ''}:")
for n in names: print("  " + n[:170])
