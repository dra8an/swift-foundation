#!/usr/bin/env python3
"""Extracts the portable regression cases from ICU4C's
intltest/regcoll.cpp (CollationRegressionTest) into regcoll.json.

Portable = uses the en_US (root) collator with strength/attribute settings
and a compareArray triplet table (source row, relation row, target row).
Cases that build collators from rule strings, exercise the
CollationElementIterator API, or test object identity are skipped (counted).

Usage: extract_regcoll.py <regcoll.cpp> <out.json>
"""
import json
import re
import sys


def main():
    text = open(sys.argv[1], encoding='utf-8', errors='replace').read()
    # Split into Test* function bodies.
    bodies = re.split(r'\nvoid CollationRegressionTest::(Test\w+|TestT\w+)\s*\([^)]*\)\s*\n', text)
    cases = []
    skipped = []
    for i in range(1, len(bodies) - 1, 2):
        name, body = bodies[i], bodies[i + 1]
        # End at the next function (split already did) — body is up to next match.
        if 'new RuleBasedCollator' in body or 'RuleBasedCollator(rules' in body:
            skipped.append((name, 'rules'))
            continue
        if 'compareArray' not in body:
            skipped.append((name, 'no compareArray'))
            continue
        if 'createCollationElementIterator' in body:
            skipped.append((name, 'CE iterator API'))
            continue
        locale = 'root'
        if 'Locale::getCanadaFrench()' in body:
            locale = 'fr_CA'
        elif 'da_DK' in body:
            locale = 'da'
        elif 'Locale(' in body and 'en_us' not in body:
            skipped.append((name, 'other locale'))
            continue

        strength = 'tertiary'
        m = re.search(r'setStrength\(Collator::(\w+)\)', body)
        if m:
            strength = m.group(1).lower()
        attrs = re.findall(r'setAttribute\((\w+),\s*(\w+)', body)

        arrs = re.findall(
            r'(?:static\s+)?const\s+(?:UChar|char16_t)\s+\w+\s*\[\s*\]\s*\[[^\]]*\]\s*=\s*\{(.*?)\}\s*;',
            body, flags=re.S,
        )
        if not arrs:
            skipped.append((name, 'no array'))
            continue
        # Test4114077 runs its first array with normalization OFF (which this
        # implementation cannot honor); use its second, normalization-ON array.
        arr_body = arrs[1] if name == 'Test4114077' else arrs[0]
        rows = []
        for row in re.finditer(r'\{([^{}]*)\}', arr_body):
            units = [int(u, 16) for u in re.findall(r'0[xX]([0-9a-fA-F]+)', row.group(1))]
            scalars = []
            j = 0
            while j < len(units):
                u = units[j]
                if u == 0:
                    break
                if 0xd800 <= u <= 0xdbff and j + 1 < len(units) and 0xdc00 <= units[j + 1] <= 0xdfff:
                    scalars.append(0x10000 + ((u - 0xd800) << 10) + (units[j + 1] - 0xdc00))
                    j += 2
                    continue
                scalars.append(u)
                j += 1
            rows.append(''.join(chr(c) for c in scalars))
        if len(rows) % 3 != 0:
            skipped.append((name, f'rows % 3 != 0 ({len(rows)})'))
            continue
        triplets = [rows[j:j + 3] for j in range(0, len(rows), 3)]
        if any(t[1] not in '<=>' for t in triplets):
            skipped.append((name, 'unexpected relation row'))
            continue
        cases.append({'name': name, 'locale': locale, 'strength': strength, 'attrs': attrs, 'triplets': triplets})

    with open(sys.argv[2], 'w', encoding='utf-8') as f:
        json.dump({'cases': cases}, f, ensure_ascii=False, indent=1)
    print(f'extracted {len(cases)} cases: {[c["name"] for c in cases]}')
    print(f'skipped {len(skipped)}: {skipped}')


if __name__ == '__main__':
    main()
