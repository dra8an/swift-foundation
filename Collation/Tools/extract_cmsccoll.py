#!/usr/bin/env python3
"""Extracts the non-rule test cases from ICU4C's cintltst/cmsccoll.c into
cmsccoll.json. Each case is a locale + options + a string list expected to be
in ascending order (genericLocaleStarter semantics: every pair i<j compares
LESS) — or EQUAL for the WithOptionsAndResult(UCOL_EQUAL) case.

The selection of portable cases is explicit below; everything else in
cmsccoll.c builds collators from rule strings (88 genericRulesStarter/
ucol_openRules sites) or tests APIs we do not have. TestExtremeCompression is
programmatic and reimplemented directly in Swift.

Usage: extract_cmsccoll.py <cmsccoll.c> <out.json>
"""
import json
import re
import sys

# (case name, enclosing function, array name, locale, [[attr, value]...], expected)
# Note: TestJ784 is intentionally absent — it sits in an #if 0 block in
# cmsccoll.c (superseded by TestBeforePinyin, which is included).
CASES = [
    ('UpperCaseFirst-da', 'TestUpperCaseFirst', 'data', 'da', [], 'less'),
    ('J815-fr', 'TestJ815', 'data', 'fr', [], 'less'),
    # ko__LOTUS falls back to ko standard in current ICU.
    ('HangulTailoring-ko', 'TestHangulTailoring', 'koreanData', 'ko', [], 'less'),
    ('NewJapanese-1-quat', 'TestNewJapanese', 'test1', 'ja',
     [['strength', 'quaternary']], 'less'),
    ('NewJapanese-2-quat', 'TestNewJapanese', 'test2', 'ja',
     [['strength', 'quaternary']], 'less'),
    ('NewJapanese-1-shifted', 'TestNewJapanese', 'test1', 'ja',
     [['strength', 'quaternary'], ['alternate', 'shifted']], 'less'),
    ('NewJapanese-2-shifted', 'TestNewJapanese', 'test2', 'ja',
     [['strength', 'quaternary'], ['alternate', 'shifted']], 'less'),
    ('Numeric-basic', 'TestNumericCollation', 'basicTestStrings', 'root',
     [['numeric', 'on']], 'less'),
    ('Numeric-32bit', 'TestNumericCollation', 'thirtyTwoBitNumericStrings', 'root',
     [['numeric', 'on']], 'less'),
    ('Numeric-long', 'TestNumericCollation', 'longNumericStrings', 'root',
     [['numeric', 'on']], 'less'),
    ('Numeric-foreign', 'TestNumericCollation', 'foreignDigits', 'root',
     [['numeric', 'on']], 'less'),
    ('Numeric-supplementary', 'TestNumericCollation', 'supplementaryDigits', 'root',
     [['numeric', 'on']], 'less'),
    ('Numeric-evenZeroes', 'TestNumericCollation', 'evenZeroes', 'root',
     [['numeric', 'on']], 'less'),
    ('PinyinProblem', 'TestPinyinProblem', 'test', 'zh', [], 'less'),
    ('BeforePinyin-1', 'TestBeforePinyin', 'test', 'zh', [], 'less'),
    ('BeforePinyin-2', 'TestBeforePinyin', 'test2', 'zh', [], 'less'),
    ('UpperFirstQuaternary', 'TestUpperFirstQuaternary', 'tests', 'root',
     [['strength', 'quaternary'], ['caseFirst', 'upper']], 'less'),
    ('J4960-primary-caselevel-ignorables', 'TestJ4960', 'tests', 'root',
     [['strength', 'primary'], ['caseLevel', 'on']], 'equal'),
    ('J4960-primary-caselevel-case', 'TestJ4960', 'tests2', 'root',
     [['strength', 'primary'], ['caseLevel', 'on']], 'less'),
    ('J5232-th-partial', 'TestJ5232', 'test', 'th', [], 'less'),
]


def unescape(source):
    """Two stages, matching how ICU test sources work: the C compiler turns
    \\\\ into a backslash (etc.), then u_unescape decodes \\uXXXX /
    \\UXXXXXXXX at runtime (with surrogate-pair combining)."""
    # Stage 1: C string-literal unescape of the captured source text.
    s = ''
    i = 0
    while i < len(source):
        if source[i] == '\\' and i + 1 < len(source):
            n = source[i + 1]
            if n == '\\': s += '\\'; i += 2; continue
            if n == '"': s += '"'; i += 2; continue
            if n == 't': s += '\t'; i += 2; continue
            if n == 'n': s += '\n'; i += 2; continue
            raise AssertionError(f'unknown C escape in {source!r}')
        s += source[i]
        i += 1
    # Stage 2: u_unescape.
    out = []
    units = []

    def flush_units():
        i = 0
        while i < len(units):
            u = units[i]
            if 0xd800 <= u <= 0xdbff and i + 1 < len(units) and 0xdc00 <= units[i + 1] <= 0xdfff:
                out.append(chr(0x10000 + ((u - 0xd800) << 10) + (units[i + 1] - 0xdc00)))
                i += 2
                continue
            assert not (0xd800 <= u <= 0xdfff), f'unpaired surrogate in {s!r}'
            out.append(chr(u))
            i += 1
        units.clear()

    i = 0
    while i < len(s):
        if s[i] == '\\' and i + 1 < len(s):
            kind = s[i + 1]
            if kind == 'u':
                units.append(int(s[i + 2:i + 6], 16))
                i += 6
                continue
            if kind == 'U':
                flush_units()
                out.append(chr(int(s[i + 2:i + 10], 16)))
                i += 10
                continue
            if kind == '\\':
                flush_units()
                out.append('\\')
                i += 2
                continue
            raise AssertionError(f'unknown escape in {s!r}')
        flush_units()
        out.append(s[i])
        i += 1
    flush_units()
    return ''.join(out)


def main():
    text = open(sys.argv[1], encoding='utf-8', errors='replace').read()
    # Strip comments first: commented-out strings are often commented out
    # precisely because their order is wrong.
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'#if 0.*?#endif', '', text, flags=re.S)  # disabled code
    # Function bodies, keyed by name.
    bodies = {}
    for m in re.finditer(r'(?:static\s+)?void\s*\n?(\w+)\s*\([^)]*\)\s*\{', text):
        start = m.end()
        depth = 1
        i = start
        while depth > 0 and i < len(text):
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
            i += 1
        bodies[m.group(1)] = text[start:i]

    out = []
    for name, func, array, locale, attrs, expected in CASES:
        body = bodies[func]
        m = re.search(
            r'(?:static\s+)?const\s+char\s*\*\s*(?:const\s+)?' + array
            + r'\s*\[\s*\]\s*=\s*\{(.*?)\}\s*;',
            body, flags=re.S,
        )
        assert m, f'{func}/{array} not found'
        # Concatenate adjacent string literals per element.
        elements = []
        for elem in re.finditer(r'((?:"(?:[^"\\]|\\.)*"\s*)+)(?:,|$)', m.group(1)):
            parts = re.findall(r'"((?:[^"\\]|\\.)*)"', elem.group(1))
            elements.append(unescape(''.join(parts)))
        assert len(elements) >= 2, f'{func}/{array}: only {len(elements)} elements'
        out.append({'name': name, 'locale': locale, 'attrs': attrs,
                    'expected': expected, 'strings': elements})
        print(name, locale, attrs, expected, len(elements))

    with open(sys.argv[2], 'w', encoding='utf-8') as f:
        json.dump({'cases': out}, f, ensure_ascii=False, indent=1)
    print('wrote', sys.argv[2])


if __name__ == '__main__':
    main()
