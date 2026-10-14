# 30 — Side note: ICU4J fast-Latin compare bug (signed pair test)

> Recorded 2026-10-14. **Not our bug.** Our collator and ICU4C are correct.
> This note exists so that the finding is not lost if nobody in ICU picks
> it up.

## The field report

A user reported against ICU4J 78.3: `Collator.compare()` does not always
give the same result as a comparison of the `CollationKey`s. A reply asked
for a test with the ICU 79 release candidate.

```java
Collator collator = Collator.getInstance(new Locale("en"));
collator.compare("dàß", "Daß");                       // -1  (wrong)
collator.getCollationKey("dàß")
        .compareTo(collator.getCollationKey("Daß"));  // +1  (correct)
```

The correct answer is +1. At the primary level both strings are d, a, ß
("ss"). At the secondary level the grave accent makes "dàß" greater. The
D/d difference is only tertiary, so it does not decide.

## Results

| implementation | `compare` | key | |
|---|---|---|---|
| ICU4J 74.1, 75.1, 76.1, 78.1 | −1 | +1 | **wrong** |
| ICU4J 79.1 snapshot (newest) | −1 | +1 | **wrong** |
| ICU4C 79.1 | +1 | +1 | correct |
| Our collator (`compare()` and the fast path directly) | +1 | +1 | correct |

78.3 lies between 78.1 and 79.1, which fail with the same code, so 78.3
fails too.

## The trigger

A precomposed accented letter directly before ß fails: "àß" vs "aß",
"dáß" vs "Daß", "déß" vs "Deß", "dàßx" vs "Daßx". Case does not matter.
These pass: a decomposed accent (a + U+0300), a letter between the accent
and ß ("dàxß"), "s" instead of ß, and æ instead of ß. A non-Latin
character anywhere in the strings forces the slow path, and the slow path
is correct.

## The cause

`icu4j/main/collate/src/main/java/com/ibm/icu/impl/coll/CollationFastLatin.java`
is a port of `icu4c/source/i18n/collationfastlatin.cpp`. A "pair" holds the
current mini CE in the low 16 bits and the next one (if any) in the high 16
bits. The four weight getters start with:

```java
if (pair <= 0xffff) {   // one mini CE
```

In C++, `pair` is a `uint32_t`, so a pair of two mini CEs is always greater
than 0xffff. In Java, `pair` is an `int`: the caller casts the `long` from
`nextPair` to `int`. If the second mini CE is 0x8000 or more, the `int` is
negative, and a negative value passes `pair <= 0xffff`. The getter then
handles a two-CE expansion as one special mini CE and returns the raw pair,
not its weights.

ß is an expansion to "ss", and the mini CE of s is 0x8000 or more (s is
late in the primary order). In "dàß" vs "Daß", after the common weights
match, the left side still holds the grave secondary of à. The right side
fetches ß and gets the raw pair. Its low 16 bits are the raw s mini CE, not
a secondary weight. The grave weight is smaller, so `compare()` returns −1.

The defective test is in all four getters (79.1 snapshot line numbers):
`getSecondaries` (813), `getCases` (842), `getTertiaries` (878),
`getQuaternaries` (930). The failure above goes through `getSecondaries`.
No failing case was constructed for the other three; they have the same
defect in the code.

## The fix

```diff
-        if (pair <= 0xffff) {
+        if ((pair >>> 16) == 0) {
```

in all four getters. That is the unsigned meaning of the C++ test.

**Verified:** a patched `CollationFastLatin` class, put ahead of the
79.1-snapshot jar on the class path, fixes the report case and all 24 pairs
of the narrowing set. The unpatched jar still fails them.

## Our collator

`CollationFastLatin.swift` ports the C++ code, and its getters take
`UInt32` pairs, so the test is unsigned by construction. Verified: 96
comparisons (12 pairs × 2 argument orders × 4 option sets: default, case
level at primary strength, shifted at quaternary strength, upper-first)
gave 0 mismatches between `compare()` and the sort keys. A direct call of
`CollationFastLatin.compare` engaged on 88 of them, including the report
case (+1); the 8 bail-outs were the pair with a non-Latin character, which
must bail.

**Do not change the `pair` type in our port to a signed type.** That would
import this exact bug.

## If you want to report it

The ICU Jira is the place; the reporter could not create an issue there. A
fix should come with an ICU4J test that compares `compare()` with the
`CollationKey` order for the trigger strings above.
