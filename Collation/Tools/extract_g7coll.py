#!/usr/bin/env python3
"""Extracts the rule-free TestG7Locales data from ICU4C's intltest/g7coll.cpp
into g7coll.json, consumed by G7CollationTests.swift. The strings and the
per-locale expected-order rows come out of the C source mechanically (no hand
transcription). The demo tests and the last four result rows build collators
from rule strings and are out of scope (see 12-rule-builder-decision.md).

Usage: extract_g7coll.py <icu4c/source/test> <out.json>
"""
import json
import re
import sys

FIXEDTESTSET = 15  # g7coll.h: pairwise loop bound for the locale rows
LOCALES = ['en_US', 'en_GB', 'en_CA', 'fr_FR', 'fr_CA', 'de_DE', 'it_IT', 'ja_JP']


def main(test_dir, out_path):
    src = open(f'{test_dir}/intltest/g7coll.cpp', encoding='utf-8').read()

    # testCases[][MAX_TOKEN_LEN]: brace groups of char16_t hex values,
    # NUL-terminated.
    m = re.search(r'testCases\[\]\[[^\]]*\] = \{(.*?)\n\};', src, re.S)
    strings = []
    for group in re.findall(r'\{([^{}]*)\}', m.group(1)):
        values = [int(v, 16) for v in re.findall(r'0x([0-9a-fA-F]+)', group)]
        while values and values[-1] == 0:
            values.pop()
        strings.append(''.join(chr(v) for v in values))

    # results[TESTLOCALES][TOTALTESTSET]: the first 8 rows are the locale
    # rows (the rest need rule-based collators); only the first FIXEDTESTSET
    # entries of each row are compared.
    m = re.search(r'results\[[^=]*\] = \{(.*?)\n\};', src, re.S)
    rows = re.findall(r'\{([^{}]*)\}', m.group(1))
    orders = []
    for row in rows[:len(LOCALES)]:
        indexes = [int(v) for v in re.findall(r'\d+', row)][:FIXEDTESTSET]
        assert all(i < len(strings) for i in indexes), 'index out of range'
        orders.append(indexes)
    assert len(orders) == len(LOCALES), 'unexpected locale row count'

    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(
            {'source': 'intltest/g7coll.cpp TestG7Locales',
             'strings': strings, 'locales': LOCALES, 'orders': orders},
            f, ensure_ascii=False, indent=1)
        f.write('\n')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
