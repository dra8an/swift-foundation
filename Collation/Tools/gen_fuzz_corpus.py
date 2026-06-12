#!/usr/bin/env python3
"""Generates the fuzz corpus: random strings weighted toward collation
trouble spots (combining marks, contraction bases, digits, Hangul, kana,
Tibetan, format controls, supplementary planes).

Deterministic for a given seed. Regenerate with:
    python3 gen_fuzz_corpus.py 42 2000 ../Tests/CollationTests/Golden/fuzz-corpus.txt
then regenerate the reference keys with gen_golden (keys-only mode):
    DYLD_LIBRARY_PATH=$ICU_BUILD/lib ./gen_golden \
        ../Tests/CollationTests/Golden/fuzz-corpus.txt \
        ../Tests/CollationTests/Golden/fuzz --keys-only
"""
import random
import sys

POOLS = [
    # (weight, scalars)
    (30, list(range(0x20, 0x7f))),                                # ASCII
    (10, list(range(0xc0, 0x180))),                               # Latin-1/Ext-A precomposed
    (12, [0x300, 0x301, 0x302, 0x303, 0x308, 0x30a, 0x30c,       # combining marks
          0x323, 0x327, 0x328, 0x334, 0x345, 0x31b, 0x35c, 0x362]),
    (4, [0x6c, 0x4c, 0xb7, 0x387]),                               # l-middle-dot prefix parts
    (4, list(range(0xf40, 0xf6c)) + [0xf71, 0xf72, 0xf74, 0xf80,  # Tibetan incl. contraction
                                     0xf73, 0xf75, 0xf81, 0xf39, 0xf7a]),
    (5, list(range(0x3041, 0x3097)) + [0x3099, 0x309a, 0x309d,    # kana + voicing + marks
                                       0x309e, 0x30fc, 0x30a1, 0x30f4]),
    (5, list(range(0xac00, 0xac30)) + list(range(0x1100, 0x1113)) # Hangul + Jamo
        + list(range(0x1161, 0x1176)) + list(range(0x11a8, 0x11c0))),
    (4, list(range(0x30, 0x3a)) + [0x660, 0x661, 0x6f0, 0x966]),  # digits incl. Arabic/Devanagari
    (4, list(range(0x391, 0x3aa)) + list(range(0x3b1, 0x3ca))     # Greek, Cyrillic
        + list(range(0x410, 0x450)) + [0x301, 0x306, 0x308]),
    (3, list(range(0x4e00, 0x4e80)) + list(range(0x9f00, 0x9fa6))),  # Han (OFFSET ranges)
    (3, list(range(0xe00, 0xe3b)) + list(range(0xe40, 0xe4f))),   # Thai
    (2, [0xad, 0x200b, 0x200c, 0x200d, 0x2060, 0xfeff]),          # ignorables/format controls
    (2, [0xf900, 0xfa10, 0x2f800, 0x1d15e, 0x1d157, 0x1d165]),    # compat/musical decompositions
    (2, list(range(0x1f600, 0x1f620)) + list(range(0x20000, 0x20020))),  # supplementary
    (1, [0x378, 0x53b0, 0xe000, 0xfdd0, 0xffff, 0x10fffd]),       # unassigned/PUA/noncharacters
    (1, [0x2c, 0x2e, 0x20, 0x21, 0x24, 0x20ac, 0x2028]),          # separators/symbols
]


def main():
    seed, count, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    rng = random.Random(seed)
    weighted = [pool for weight, pool in POOLS for _ in range(weight)]
    lines = set()
    while len(lines) < count:
        length = rng.choice([1, 1, 2, 2, 3, 3, 4, 5, 6, 8, 12])
        s = ''.join(chr(rng.choice(rng.choice(weighted))) for _ in range(length))
        if '\n' in s or '\x00' in s or s.strip() != s and rng.random() < 0.5:
            continue
        lines.add(s)
    with open(out, 'w', encoding='utf-8') as f:
        f.write('\n'.join(sorted(lines)) + '\n')
    print(f'wrote {len(lines)} strings to {out}')


if __name__ == '__main__':
    main()
