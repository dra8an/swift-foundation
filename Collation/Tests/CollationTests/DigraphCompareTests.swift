import Testing
@testable import Collation

@Suite("Digraph Compare")
struct DigraphCompareTests {
    let root = try! RootCollator()
    let cs = try! RootCollator(tailoringNamed: "cs")
    let es = try! RootCollator(tailoringNamed: "es")

    // MARK: - Czech: ch sorts as a single letter after h

    @Test func czechChAfterH() throws {
        // In Czech, "ch" comes after "h" in sort order
        // So "ha" < "cha" in Czech
        let result = try cs.compare("ha", "cha")
        #expect(result == .ascending, "Czech: 'ha' should sort before 'cha' (ch is after h)")
    }

    @Test func czechChBeforeI() throws {
        // "ch" sorts after "h" but before "i" in Czech
        let result = try cs.compare("cha", "ia")
        #expect(result == .ascending, "Czech: 'cha' should sort before 'ia' (ch is between h and i)")
    }

    @Test func rootChIsJustCPlusH() throws {
        // In root collation, "ch" is just c followed by h — no special treatment
        // So "ci" < "ch" because i > h in root
        let result = try root.compare("ci", "ch")
        #expect(result == .descending, "Root: 'ci' should sort after 'ch' (no digraph)")
    }

    @Test func czechVsRootChOrdering() throws {
        // "h" < "ch" in Czech but "ch" < "h" would be wrong
        // Czech: h < ch < i
        // Root:  c < ch < ci (plain alphabetical)
        let czechHvsCh = try cs.compare("h", "ch")
        let rootHvsCh = try root.compare("h", "ch")
        #expect(czechHvsCh == .ascending, "Czech: 'h' < 'ch'")
        #expect(rootHvsCh == .descending, "Root: 'h' > 'ch' (h comes after c)")
    }

    @Test func czechChWords() throws {
        // "hrad" should sort before "chrám" in Czech (h < ch)
        let result = try cs.compare("hrad", "chrám")
        #expect(result == .ascending, "Czech: 'hrad' < 'chrám'")
    }

    @Test func czechChNotTriggeredByDifferentStarters() throws {
        // "c" followed by a non-"h" should not trigger the ch contraction
        let result = try cs.compare("ca", "cha")
        #expect(result == .ascending, "Czech: 'ca' < 'cha' (c sorts before ch)")
    }

    @Test func czechSWithCaron() throws {
        // š sorts after s in Czech (separate letter)
        let result = try cs.compare("sa", "ša")
        #expect(result == .ascending, "Czech: 'sa' < 'ša' (š is after s)")
    }

    @Test func czechRWithCaron() throws {
        // ř sorts after r in Czech (separate letter)
        let result = try cs.compare("ra", "řa")
        #expect(result == .ascending, "Czech: 'ra' < 'řa' (ř is after r)")
    }

    @Test func czechZWithCaron() throws {
        // ž sorts after z in Czech (separate letter)
        let result = try cs.compare("za", "ža")
        #expect(result == .ascending, "Czech: 'za' < 'ža' (ž is after z)")
    }

    @Test func czechCaronVsRootCaron() throws {
        // In root, š and s have the same primary (differ at tertiary)
        // In Czech, š is a different primary letter after s
        var primary = CollationOptions()
        primary.strength = .primary

        let rootResult = try root.compare("s", "š", options: primary)
        let czechResult = try cs.compare("s", "š", options: primary)
        #expect(rootResult == .same, "Root: 's' == 'š' at primary strength")
        #expect(czechResult == .ascending, "Czech: 's' < 'š' at primary (different letters)")
    }

    // MARK: - Spanish: ñ is a separate letter after n

    @Test func spanishEneAfterN() throws {
        // In Spanish, ñ sorts after n
        let result = try es.compare("na", "ña")
        #expect(result == .ascending, "Spanish: 'na' < 'ña' (ñ is after n)")
    }

    @Test func spanishEneBeforeO() throws {
        // ñ sorts after n but before o
        let result = try es.compare("ña", "oa")
        #expect(result == .ascending, "Spanish: 'ña' < 'oa' (ñ is between n and o)")
    }

    @Test func spanishEneVsRootEne() throws {
        // In root, ñ is just n + tilde (same primary as n)
        // In Spanish, ñ has its own primary after n
        var primary = CollationOptions()
        primary.strength = .primary

        let rootResult = try root.compare("n", "ñ", options: primary)
        let esResult = try es.compare("n", "ñ", options: primary)
        #expect(rootResult == .same, "Root: 'n' == 'ñ' at primary strength")
        #expect(esResult == .ascending, "Spanish: 'n' < 'ñ' at primary (different letters)")
    }

    @Test func spanishEneWords() throws {
        // "nube" < "ñoño" < "obra" in Spanish sort order
        let nVsEne = try es.compare("nube", "ñoño")
        let eneVsO = try es.compare("ñoño", "obra")
        #expect(nVsEne == .ascending, "Spanish: 'nube' < 'ñoño'")
        #expect(eneVsO == .ascending, "Spanish: 'ñoño' < 'obra'")
    }

    @Test func spanishAnoVsAnno() throws {
        // "ano" and "año" are different words — ñ ≠ n
        let result = try es.compare("ano", "año")
        #expect(result == .ascending, "Spanish: 'ano' < 'año' (n < ñ)")
    }

    // MARK: - Cross-locale: same strings, different order

    @Test func crossLocaleChOrdering() throws {
        // "hrad" vs "chrám":
        // Czech: hrad < chrám (h < ch)
        // Root:  chrám < hrad (c < h)
        let czechResult = try cs.compare("hrad", "chrám")
        let rootResult = try root.compare("hrad", "chrám")
        #expect(czechResult == .ascending, "Czech: hrad < chrám")
        #expect(rootResult == .descending, "Root: hrad > chrám")
    }

    @Test func crossLocaleEneOrdering() throws {
        // "niño" vs "obra":
        // Both should agree (ñ before o in both)
        // But "nube" vs "ñoño":
        // Spanish: nube < ñoño (n < ñ)
        // Root: ñoño < nube (ñ = n+tilde at primary, but "ñ" < "nu" at secondary)
        var primary = CollationOptions()
        primary.strength = .primary
        let esResult = try es.compare("nube", "ñoño", options: primary)
        let rootResult = try root.compare("nube", "ñoño", options: primary)
        #expect(esResult == .ascending, "Spanish primary: 'nube' < 'ñoño'")
        #expect(rootResult == .descending, "Root primary: 'nube' > 'ñoño' (same primary n, u>o)")
    }
}
