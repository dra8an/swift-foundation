import Testing
@testable import Collation

@Suite("Digraph Compare")
struct DigraphCompareTests {
    let root = try! RootCollator()
    let cs = try! RootCollator(tailoringNamed: "cs")
    let es = try! RootCollator(tailoringNamed: "es")

    // MARK: - Czech: ch sorts as a single letter after h

    @Test func czechChAfterH() throws {
        let result = try cs.compare("ha", "cha")
        #expect(result == .ascending, "Czech: 'ha' < 'cha' (ch is after h)")
    }

    @Test func czechChBeforeI() throws {
        let result = try cs.compare("cha", "ia")
        #expect(result == .ascending, "Czech: 'cha' < 'ia' (ch is between h and i)")
    }

    @Test func rootChIsJustCPlusH() throws {
        let result = try root.compare("ci", "ch")
        #expect(result == .descending, "Root: 'ci' > 'ch' (no digraph)")
    }

    @Test func czechVsRootChOrdering() throws {
        let czechHvsCh = try cs.compare("h", "ch")
        let rootHvsCh = try root.compare("h", "ch")
        #expect(czechHvsCh == .ascending, "Czech: 'h' < 'ch'")
        #expect(rootHvsCh == .descending, "Root: 'h' > 'ch'")
    }

    @Test func czechChWords() throws {
        let result = try cs.compare("hrad", "chrám")
        #expect(result == .ascending, "Czech: 'hrad' < 'chrám'")
    }

    @Test func czechChNotTriggeredByDifferentStarters() throws {
        let result = try cs.compare("ca", "cha")
        #expect(result == .ascending, "Czech: 'ca' < 'cha'")
    }

    @Test func czechSWithCaron() throws {
        let result = try cs.compare("sa", "ša")
        #expect(result == .ascending, "Czech: 'sa' < 'ša'")
    }

    @Test func czechRWithCaron() throws {
        let result = try cs.compare("ra", "řa")
        #expect(result == .ascending, "Czech: 'ra' < 'řa'")
    }

    @Test func czechZWithCaron() throws {
        let result = try cs.compare("za", "ža")
        #expect(result == .ascending, "Czech: 'za' < 'ža'")
    }

    @Test func czechCaronVsRootCaron() throws {
        var primary = CollationOptions()
        primary.strength = .primary
        let rootResult = try root.compare("s", "š", options: primary)
        let czechResult = try cs.compare("s", "š", options: primary)
        #expect(rootResult == .same, "Root: 's' == 'š' at primary")
        #expect(czechResult == .ascending, "Czech: 's' < 'š' at primary")
    }

    // MARK: - Spanish: ñ is a separate letter after n

    @Test func spanishEneAfterN() throws {
        let result = try es.compare("na", "ña")
        #expect(result == .ascending, "Spanish: 'na' < 'ña'")
    }

    @Test func spanishEneBeforeO() throws {
        let result = try es.compare("ña", "oa")
        #expect(result == .ascending, "Spanish: 'ña' < 'oa'")
    }

    @Test func spanishEneVsRootEne() throws {
        var primary = CollationOptions()
        primary.strength = .primary
        let rootResult = try root.compare("n", "ñ", options: primary)
        let esResult = try es.compare("n", "ñ", options: primary)
        #expect(rootResult == .same, "Root: 'n' == 'ñ' at primary")
        #expect(esResult == .ascending, "Spanish: 'n' < 'ñ' at primary")
    }

    @Test func spanishEneWords() throws {
        let nVsEne = try es.compare("nube", "ñoño")
        let eneVsO = try es.compare("ñoño", "obra")
        #expect(nVsEne == .ascending, "Spanish: 'nube' < 'ñoño'")
        #expect(eneVsO == .ascending, "Spanish: 'ñoño' < 'obra'")
    }

    @Test func spanishAnoVsAnno() throws {
        let result = try es.compare("ano", "año")
        #expect(result == .ascending, "Spanish: 'ano' < 'año'")
    }

    // MARK: - Cross-locale: same strings, different order

    @Test func crossLocaleChOrdering() throws {
        let czechResult = try cs.compare("hrad", "chrám")
        let rootResult = try root.compare("hrad", "chrám")
        #expect(czechResult == .ascending, "Czech: hrad < chrám")
        #expect(rootResult == .descending, "Root: hrad > chrám")
    }

    @Test func crossLocaleEneOrdering() throws {
        var primary = CollationOptions()
        primary.strength = .primary
        let esResult = try es.compare("nube", "ñoño", options: primary)
        let rootResult = try root.compare("nube", "ñoño", options: primary)
        #expect(esResult == .ascending, "Spanish primary: 'nube' < 'ñoño'")
        #expect(rootResult == .descending, "Root primary: 'nube' > 'ñoño'")
    }
}
