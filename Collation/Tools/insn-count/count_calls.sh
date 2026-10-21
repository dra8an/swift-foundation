#!/bin/zsh
# Instruction count of N calls of one function, under Xcode's lldb (technique log §50 (g), §51).
# Usage (from the repo root): Collation/Tools/insn-count/count_calls.sh <binary> <corpus> '<breakpoint spec>' <skip> <out.jsonl> [n] [locations to disable]
#   corpus: a name under Collation/Tools/bench (ascii, latin, cjk, paths, thai) — the binary gets "<corpus file> 1".
#   breakpoint spec: what follows `breakpoint set`, e.g. "-r compareFastPath" or the mangled name of
#   sortKey(for:into:options:): "-n \$s10CollEngine12RootCollatorV7sortKey3for4into7optionsySS_Says5UInt8VGzAA16CollationOptionsVtKF"
#   (regexes do not match names with argument types, and `-a` addresses miss because of ASLR).
#   skip: calls to ignore first. EngineBench runs a warm-up pass and timed passes; skipping 3 passes needs
#   3 × (calls per pass): compare makes (lines − 1) calls per pass (597 for the 200-line corpora, 1314 for paths),
#   sortKey makes lines calls per pass (600; 1317 for paths). For thai, 200 (inside the warm-up pass) is fine.
# Counts from the stop to the function's return (count_insns). Build the binary with `-Xswiftc -g` first.
SCRIPT_DIR=${0:A:h}
REPO=${SCRIPT_DIR:h:h:h}
LLDB=/Applications/Xcode26.app/Contents/Developer/usr/bin/lldb
n=${6:-10}
rm -f $5; args=(-b -o "command script import $SCRIPT_DIR/count_insns.py" -o "breakpoint set $3")
[[ -n "$7" ]] && args+=(-o "breakpoint disable $7")
args+=(-o "breakpoint modify -i $4 1" -o run)
for k in $(seq 1 $n); do args+=(-o "count_insns $2 $5" -o continue); done
$LLDB "${args[@]}" -- $1 $REPO/Collation/Tools/bench/bench-$2.txt 1 > $5.log 2>&1
python3 -c "import json;r=[json.loads(l) for l in open('$5')];print('$2',[x['total'] for x in r], round(sum(x['total'] for x in r)/len(r),1))"
