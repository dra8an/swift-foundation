# ICU4C → Swift Port: Source Mapping

> A comprehensive map of how the ICU4C collation implementation was ported
> to this Swift library, showing the relationship between C source files,
> APIs, and functions on both sides.

## 1. High-Level Architecture Diagram

```mermaid
graph LR
    subgraph Swift["Swift Port"]
        direction TB
        SW1[RootCollator.swift]
        SW2[CollationCompare.swift]
        SW3[CollationFastLatin.swift]
        SW4[CollationElements.swift]
        SW5[NFDIterator.swift]
        SW6[NormalizationData.swift]
        SW7[CollationData.swift]
        SW8[CollationConstants.swift]
        SW9[CollationOptions.swift]
        SW10[UTrie2.swift]
        SW11[UCharsTrie.swift]
        SW12[SortKey.swift]
        SW13[DataStorage.swift]
        SW14[ScratchBuffers.swift]
    end

    subgraph ICU["ICU4C Source"]
        direction TB
        IC1["rulebasedcollator.cpp<br>ucol.cpp"]
        IC2[collationcompare.cpp]
        IC3[collationfastlatin.cpp]
        IC4["collationiterator.cpp<br>utf8collationiterator.cpp"]
        IC5["ICU4X fused NFD model<br>no direct counterpart"]
        IC6["normalizer2impl.cpp<br>replaced by nfd.bin"]
        IC7["collationdatareader.cpp<br>collationdata.cpp"]
        IC8[collation.h]
        IC9[collationsettings.h]
        IC10[utrie2.cpp]
        IC11[ucharstrie.cpp]
        IC12["collationkeys.cpp<br>bocsu.cpp"]
        IC13["no counterpart<br>Swift-specific memory owner"]
        IC14["stack buffers<br>CEBuffer in collationiterator.h"]
    end

    SW1 --> IC1
    SW2 --> IC2
    SW3 --> IC3
    SW4 --> IC4
    SW5 --> IC5
    SW6 --> IC6
    SW7 --> IC7
    SW8 --> IC8
    SW9 --> IC9
    SW10 --> IC10
    SW11 --> IC11
    SW12 --> IC12
    SW13 --> IC13
    SW14 --> IC14
```

## 2. Detailed File-to-File Mapping

| Swift File | ICU4C Source | Role |
|---|---|---|
| `CollationConstants.swift` | `collation.h` | CE32/CE bit layouts, tag enum, implicit primaries |
| `CollationData.swift` | `collationdatareader.h/.cpp`, `collationdata.h` | Binary data parser, trie/array accessors |
| `CollationElements.swift` | `collationiterator.h/.cpp`, `utf8collationiterator.h/.cpp` | CE generation, tag dispatch, contractions, prefixes |
| `CollationCompare.swift` | `collationcompare.h/.cpp` | Level-by-level CE comparison |
| `CollationFastLatin.swift` | `collationfastlatin.h/.cpp` | Mini-CE fast path for Latin text |
| `CollationOptions.swift` | `collationsettings.h/.cpp` | Strength, alternate, caseFirst, numeric, etc. |
| `SortKey.swift` | `collationkeys.h/.cpp`, `bocsu.h/.cpp` | Sort key generation + BOCSU identical level |
| `RootCollator.swift` | `rulebasedcollator.h/.cpp`, `ucol.cpp` | Public API, fast path orchestration |
| `UTrie2.swift` | `utrie2.h/.cpp` | Code-point-to-value lookup trie |
| `UCharsTrie.swift` | `ucharstrie.h/.cpp` | String-sequence-to-value trie |
| `NFDIterator.swift` | *(ICU4X model, no direct counterpart)* | Fused incremental NFD front end |
| `NormalizationData.swift` | `normalizer2impl.h` *(replaced)* | Single-trie nfd.bin: ccc + decomposition |
| `DataStorage.swift` | *(Swift-specific)* | Owns allocated memory behind UnsafeBufferPointers |
| `ScratchBuffers.swift` | `CEBuffer[40]` in `collationiterator.h` | Thread-local reusable per-call buffers |
| ❌ Not ported | `collationbuilder.h/.cpp`, `collationruleparser.h/.cpp` | Rule compilation — replaced by pre-extracted binaries |

## 3. Function-Level Mapping

### 3.1 Public API Layer

| ICU4C | Swift | Notes |
|-------|-------|-------|
| `ucol_strcollUTF8()` | `RootCollator.compare(_:_:options:)` | UTF-8 entry point; Swift receives `String` |
| `ucol_getSortKey()` | `RootCollator.sortKey(for:options:)` | Returns `[UInt8]` (ICU writes to caller buffer) |
| `ucol_open(locale)` | `RootCollator(tailoringNamed:)` | Loads bundled binary tailoring |
| `ucol_open("root")` | `RootCollator()` | Default root collator |
| `ucol_setAttribute()` | `CollationOptions` struct | Options are per-call, not per-collator |
| `ucol_setReorderCodes()` | `Reordering` (in tailoring data) | Data-supplied only, no runtime API |

### 3.2 Comparison Engine

```mermaid
flowchart TD
    subgraph "RootCollator.compare"
        A1["UTF-8 byte fast path<br>ICU: doCompare UTF-8 variant"] --> A2
        A2["Identical-prefix skip<br>ICU: equalPrefixLength"] --> A3
        A3["Fast Latin scalar path<br>ICU: CollationFastLatin::compareUTF8"] --> A4
        A4["Full CE pipeline<br>ICU: compareUpToQuaternary"]
    end
```

| ICU4C Function | Swift Function | File |
|----------------|---------------|------|
| `RuleBasedCollator::doCompare()` | `RootCollator.compare()` | RootCollator.swift |
| — byte-level prefix scan | `fastLatinUTF8()` (static) | RootCollator.swift |
| — scalar prefix skip | inline in `compare()` (lines 149–165) | RootCollator.swift |
| `CollationFastLatin::compareUTF8()` | `CollationFastLatin.compareUTF8(...)` | CollationFastLatin.swift |
| `CollationFastLatin::compareKeys()` | `CollationFastLatin.compare(...)` | CollationFastLatin.swift |
| `CollationFastLatin::getOptions()` | `CollationFastLatin.getOptions(...)` | CollationFastLatin.swift |
| `CollationCompare::compareUpToQuaternary()` | `CollationCompare.compareUpToQuaternary(...)` | CollationCompare.swift |

### 3.3 CE Generation

```mermaid
flowchart LR
    subgraph ICU4C
        I1["CollationIterator::nextCE()"]
        I2["::nextCEFromCE32()"]
        I3["::getCE32FromPrefix()"]
        I4["::nextCE32FromContraction()"]
        I5["::nextCE32FromDiscontiguousContraction()"]
        I6["::appendNumericCEs()"]
        I1 --> I2 --> I3 & I4 & I5 & I6
    end

    subgraph Swift
        S1["CEIterator.ce(at:)"]
        S2["CEIterator.appendMore()"]
        S3["CEIterator.appendCEs(d:c:ce32:depth:)"]
        S4["CEIterator.prefixCE32(d:_:)"]
        S5["CEIterator.contractionCE32(d:_:)"]
        S6["CEIterator.appendNumericCEs(d:firstCE32:)"]
        S1 --> S2 --> S3 --> S4 & S5 & S6
    end

    I1 -.- S1
    I2 -.- S3
    I3 -.- S4
    I4 -.- S5
    I6 -.- S6
```

| ICU4C Function | Swift Function | Notes |
|----------------|---------------|-------|
| `CollationIterator::nextCE()` | `CEIterator.ce(at:)` | Lazy: generates on demand |
| `CollationIterator::appendCEsFromCE32()` | `CEIterator.appendCEs(d:c:ce32:depth:)` | Tag dispatch loop |
| `CollationIterator::getCE32FromPrefix()` | `CEIterator.prefixCE32(d:_:)` | UCharsTrie walk on prev1/prev2 |
| `CollationIterator::nextCE32FromContraction()` | `CEIterator.contractionCE32(d:_:)` | Longest match + S2.1 discontiguous |
| `CollationIterator::nextCE32FromDiscontiguousContraction()` | (inlined in `contractionCE32`) | Combined into one function |
| `CollationIterator::appendNumericCEs()` | `CEIterator.appendNumericCEs(d:firstCE32:)` | CODAN digit runs |
| `CollationIterator::appendNumericSegmentCEs()` | `CEIterator.appendNumericSegmentCEs(d:_:)` | Per-segment encoding |
| `UTF8CollationIterator::nextCodePoint()` | `NFDIterator.next()` | NFD fused front end replaces raw iteration |
| `CollationIterator::CEBuffer` | `CEIterator.ces: [Int64]` | Growable array vs fixed 40-element + overflow |

### 3.4 Normalization (Architectural Divergence)

```mermaid
flowchart TD
    subgraph "ICU4C Model"
        N1["Input string - may not be NFD"]
        N2["FCD check - fcd16 per character"]
        N3["If non-FCD: normalize segment to NFD"]
        N4["CE iteration on normalized segment"]
        N1 --> N2 --> N3 --> N4
    end

    subgraph "Swift Port - ICU4X Model"
        M1["Input string - any normalization"]
        M2["NFDIterator: fused incremental NFD"]
        M3["Always produces NFD scalars"]
        M4["CE iteration on NFD stream"]
        M1 --> M2 --> M3 --> M4
    end
```

| ICU4C | Swift | Notes |
|-------|-------|-------|
| `Normalizer2Impl` (common/) | `NormalizationData` | Custom single-trie `nfd.bin` format |
| FCD16 check + segment normalize | `NFDIterator.next()` | Always-on fused NFD, no FCD |
| `normalizer2impl.h: getDecomposition()` | `NormalizationData.appendDecomposition(of:to:)` | Single trie lookup |
| `normalizer2impl.h: getCCC()` | `NormalizationData.ccc(_:)` | Packed in same trie value |
| Canonical ordering (within normalizer) | `NFDIterator.flushMarks()` | Insertion sort by ccc |
| No direct counterpart | `NormalizationData.isInert(_:)` | Fast-path: bare starters skip buffering |

### 3.5 Sort Keys

| ICU4C Function | Swift Function | Notes |
|----------------|---------------|-------|
| `CollationKeys::writeSortKeyUpToQuaternary()` | `CollationKeys.writeSortKeyUpToQuaternary(...)` | Faithful port with compression |
| `SortKeyByteSink` | `inout [UInt8]` + `SortKeyLevelBuffers` | No abstract sink; direct arrays |
| `SortKeyLevel` (internal class) | `SortKeyLevel` (struct) | Per-level byte accumulator |
| `BOCSU::writeIdenticalLevelRun()` | `CollationKeys.writeIdenticalLevelRun(...)` | BOCSU encoding for identical level |
| `BOCSU::writeDiff()` | `CollationKeys.writeDiff(_:into:)` | Single code-point diff encoding |

### 3.6 Trie Infrastructure

| ICU4C | Swift | Notes |
|-------|-------|-------|
| `UTRIE2_GET32(trie, c)` macro | `UTrie2.get(_ c: UInt32) -> UInt32` | `@inline(__always)`, same algorithm |
| `utrie2_fromBinary()` | `UTrie2.init(bytes:offset:length:storage:)` | Parse serialized format |
| `UCharsTrie::first()` | `UCharsTrie.first(_:)` | Start traversal |
| `UCharsTrie::next()` | `UCharsTrie.next(_:)` | Continue traversal |
| `UCharsTrie::nextForCodePoint()` | `UCharsTrie.nextForCodePoint(_:)` | Handle supplementary as surrogate pair |
| `UCharsTrie::getValue()` | `UCharsTrie.getValue()` | Read current value |

### 3.7 Data Loading

| ICU4C | Swift | Notes |
|-------|-------|-------|
| `CollationDataReader::read()` | `CollationData.init(bytes:)` | Parse ucadata.icu format |
| `CollationRoot::getRoot()` | `CollationData.root()` | Load bundled root binary |
| `ucol_open(locale)` loads .res | `CollationData.tailoring(named:)` | Bundled pre-extracted binaries |
| Stack buffers / `CEBuffer[40]` | `ScratchBuffers` + `ThreadLocalScratch` | Thread-local reuse instead of stack |

## 4. What Was NOT Ported (by design)

```mermaid
graph TD
    subgraph "Not Ported"
        NP1["collationbuilder.cpp<br>Rule parser and builder"]
        NP2["collationruleparser.cpp<br>Rule syntax parser"]
        NP3["collationdatabuilder.cpp<br>Trie builder"]
        NP4["collationdatawriter.cpp<br>Binary serializer"]
        NP5["collationfcd.cpp<br>FCD normalization"]
        NP6["collationsets.cpp<br>UnicodeSet utilities"]
        NP7["Backward iteration<br>previousCE"]
        NP8["ucol_getCollationElementIterator<br>Public CEI API"]
    end

    NP1 --- R1["Replaced by pre-extracted<br>binary tailorings"]
    NP5 --- R2["Replaced by always-on<br>fused NFD - ICU4X model"]
    NP7 --- R3["Not needed:<br>forward-only comparison"]
```

| ICU4C Component | Why Not Ported | Alternative |
|-----------------|---------------|-------------|
| `CollationBuilder` | Runtime rule compilation too complex for initial port | Binary tailorings from ICU build tools |
| `CollationRuleParser` | Only needed by builder | — |
| `CollationDataBuilder` | Only needed by builder | — |
| FCD check / `CollationFCD` | ICU4X architectural decision: always normalize | Fused NFD front end |
| Backward iteration (`previousCE()`) | Forward-only comparison is sufficient | — |
| Canonical closure in data | ICU4X model: NFD in iterator, not in data | Simpler data, correct via NFD |
| Unpaired surrogate handling | Swift `String` cannot contain them | — |
| `ucol_getCollationElementIterator` (public) | No public CE iterator API needed | Internal `collationElements(of:)` test hook |

## 5. Data Flow: A Compare Call

```mermaid
sequenceDiagram
    participant User
    participant RC as RootCollator
    participant FL as FastLatin
    participant CE as CEIterator
    participant NFD as NFDIterator
    participant Trie as UTrie2
    participant CC as CollationCompare

    User->>RC: compare café vs caff
    RC->>RC: UTF-8 byte prefix scan ca = ca
    RC->>FL: compareUTF8 bytes offset=2
    FL->>FL: mini-CE lookup f vs f
    FL->>FL: mini-CE lookup e-acute - bail out
    FL-->>RC: bailOutResult

    RC->>RC: scalar prefix skip shared=2
    RC->>RC: takeScratch - thread-local
    RC->>CE: reset source first=f
    RC->>CC: compareUpToQuaternary left right

    loop Primary level
        CC->>CE: ce at i
        CE->>NFD: next - scalar
        NFD->>NFD: nextSourceScalar - decompose e-acute
        NFD-->>CE: e then combining acute
        CE->>Trie: get 0x65 - CE32
        CE->>CE: appendCEs - primary weight
        CE-->>CC: primary
    end

    CC-->>RC: result ascending or descending
    RC->>RC: giveScratch - thread-local
    RC-->>User: .ascending
```

## 6. Summary Table

| Layer | ICU4C Files | Swift File | Key Difference |
|-------|------------|------------|----------------|
| **API** | rulebasedcollator, ucol | RootCollator | Value-type struct, options per-call |
| **Fast Path** | collationfastlatin | CollationFastLatin | Same algorithm, static functions |
| **Compare** | collationcompare | CollationCompare | Identical logic |
| **CE Iteration** | collationiterator, utf8/16collationiterator | CollationElements | Single struct, no inheritance |
| **Normalization** | normalizer2impl + FCD | NFDIterator + NormalizationData | Fused NFD, no FCD (ICU4X model) |
| **Constants** | collation.h | CollationConstants | Same bit layouts |
| **Options** | collationsettings | CollationOptions | Public value type |
| **Data** | collationdata + datareader | CollationData | UnsafeBufferPointer views |
| **Sort Keys** | collationkeys + bocsu | SortKey | Same compression algorithm |
| **Tries** | utrie2, ucharstrie | UTrie2, UCharsTrie | Read-only, same lookup |
| **Memory** | stack buffers, CEBuffer[40] | DataStorage, ScratchBuffers | Heap + thread-local reuse |
| **Builder** | collationbuilder + ruleparser | ❌ Not ported | Pre-extracted binaries |
