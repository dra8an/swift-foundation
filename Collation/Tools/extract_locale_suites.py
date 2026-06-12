#!/usr/bin/env python3
"""Extracts the test-case arrays from ICU4C's classic locale collation test
suites (cintltst/*.c and intltest/*.cpp) into locale-suites.json, consumed by
LocaleSuiteTests.swift. The strings come out of the C sources mechanically
(no hand transcription); the per-suite loop logic is reimplemented in Swift.

Usage: extract_locale_suites.py <icu4c/source/test> <out.json>
"""
import json
import re
import sys

FILES = {
    'en': 'cintltst/encoll.c',
    'de': 'cintltst/cdetst.c',
    'es': 'cintltst/cestst.c',
    'fr': 'cintltst/cfrtst.c',
    'ja': 'cintltst/cjaptst.c',
    'tr': 'cintltst/cturtst.c',
    'fi': 'intltest/ficoll.cpp',
    'ko': 'intltest/lcukocol.cpp',
    'currency': 'intltest/currcoll.cpp',
}

RESULT_TOKENS = {
    'UCOL_LESS': -1, 'UCOL_EQUAL': 0, 'UCOL_GREATER': 1,
    'Collator::LESS': -1, 'Collator::EQUAL': 0, 'Collator::GREATER': 1,
}


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def parse_uchar_arrays(text):
    """name[][...] = { {0x...., ...}, ... } -> {name: [str, ...]}"""
    arrays = {}
    for m in re.finditer(
        r'(?:static\s+|const\s+)*(?:UChar|char16_t)\s+(?:\w+::)?(\w+)\s*\[\s*\]\s*\[[^\]]*\]\s*=\s*\{(.*?)\}\s*;',
        text, flags=re.S,
    ):
        name, body = m.group(1), m.group(2)
        rows = []
        for row in re.finditer(r'\{([^{}]*)\}', body):
            units = [int(u, 16) for u in re.findall(r'0[xX]([0-9a-fA-F]+)', row.group(1))]
            scalars = []
            i = 0
            while i < len(units):
                u = units[i]
                if u == 0:
                    break
                if 0xd800 <= u <= 0xdbff and i + 1 < len(units) and 0xdc00 <= units[i + 1] <= 0xdfff:
                    scalars.append(0x10000 + ((u - 0xd800) << 10) + (units[i + 1] - 0xdc00))
                    i += 2
                    continue
                scalars.append(u)
                i += 1
            rows.append(''.join(chr(c) for c in scalars))
        arrays[name] = rows
    return arrays


def parse_result_arrays(text):
    results = {}
    for m in re.finditer(
        r'(?:static\s+|const\s+)*(?:UCollationResult|Collator::EComparisonResult)\s+(?:\w+::)?(\w+)\s*'
        r'\[\s*\]\s*(\[\s*2\s*\])?\s*=\s*\{(.*?)\}\s*;',
        text, flags=re.S,
    ):
        name, twocol, body = m.group(1), m.group(2), m.group(3)
        tokens = re.findall(r'(?:UCOL_|Collator::)(?:LESS|EQUAL|GREATER)', body)
        values = [RESULT_TOKENS[t if t.startswith('Collator') else t] for t in tokens]
        if twocol:
            results[name] = [values[i:i + 2] for i in range(0, len(values), 2)]
        else:
            results[name] = values
    return results


def main():
    base, out = sys.argv[1], sys.argv[2]
    suites = {}
    for key, rel in FILES.items():
        text = strip_comments(open(f'{base}/{rel}', encoding='utf-8', errors='replace').read())
        suites[key] = {
            'source': rel,
            'arrays': parse_uchar_arrays(text),
            'results': parse_result_arrays(text),
        }
        print(key, {n: len(v) for n, v in suites[key]['arrays'].items()},
              {n: len(v) for n, v in suites[key]['results'].items()})
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(suites, f, ensure_ascii=False, indent=1)
    print('wrote', out)


if __name__ == '__main__':
    main()
