#!/bin/zsh
# Interleaved EngineBench A/B (the project's standard): R rounds, order alternates per round, all five corpora
# (thai at 10 repetitions — never more). Run from the repo root.
# Usage: Collation/Tools/ab/engine_ab.sh <base EngineBench> <variant EngineBench> <out.txt> [rounds=5]
#        python3 Collation/Tools/ab/engine_ab_report.py <out.txt>
C=Collation/Tools/bench
R=${4:-5}; : > $3
for r in $(seq 1 $R); do
  for c in ascii latin cjk paths thai; do
    reps=300; [[ $c == paths ]] && reps=150; [[ $c == thai ]] && reps=10
    if (( r % 2 )); then order=(base var); else order=(var base); fi
    for side in $order; do
      bin=$1; [[ $side == var ]] && bin=$2
      $bin $C/bench-$c.txt $reps | sed "s/^/$r $c $side /" >> $3
    done
  done
done
