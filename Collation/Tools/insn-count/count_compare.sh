#!/bin/zsh
# Instruction count of N whole compare(_:_:options:) calls in EngineBench, from the function's FIRST instruction
# (`-K false`: no prologue skip), with every other `compare` breakpoint location disabled by name (technique log §51 (i)).
# Usage (from the repo root): Collation/Tools/insn-count/count_compare.sh <EngineBench> <corpus> <skip> <out.jsonl> [n]
#   skip: 597 for ascii/latin/cjk (3 × 199), 1314 for paths; thai: 200 (inside the warm-up pass is fine).
SCRIPT_DIR=${0:A:h}
REPO=${SCRIPT_DIR:h:h:h}
LLDB=/Applications/Xcode26.app/Contents/Developer/usr/bin/lldb
n=${5:-10}
ids=$($LLDB -b -o "breakpoint set -s EngineBench -n compare -K false" -o "breakpoint list" $1 2>&1 | grep -E "^\s+1\.[0-9]+:" | grep -v "RootCollator.compare(_:_:options:) " | perl -ne 'print "$1 " if /^\s+(1\.\d+):/')
rm -f $4; args=(-b -o "command script import $SCRIPT_DIR/count_insns.py" -o "breakpoint set -s EngineBench -n compare -K false")
[[ -n "$ids" ]] && args+=(-o "breakpoint disable $ids")
args+=(-o "breakpoint modify -i $3 1" -o run)
for k in $(seq 1 $n); do args+=(-o "count_insns $2 $4" -o continue); done
$LLDB "${args[@]}" -- $1 $REPO/Collation/Tools/bench/bench-$2.txt 1 > $4.log 2>&1
python3 -c "import json;r=[json.loads(l) for l in open('$4')];print('$2',[x['total'] for x in r], round(sum(x['total'] for x in r)/len(r),1))"
