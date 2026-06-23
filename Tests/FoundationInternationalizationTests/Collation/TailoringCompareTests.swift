import Testing
@testable import FoundationInternationalization

@Suite("Tailoring Compare")
struct TailoringCompareTests {
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

    // MARK: - Turkish: dotless ı sorts before dotted i

    @Test func turkishDotlessI() throws {
        let tr = try RootCollator(tailoringNamed: "tr")
        let trResult = try tr.compare("ı", "i")
        let rootResult = try root.compare("ı", "i")
        #expect(trResult == .ascending, "Turkish: 'ı' < 'i'")
        #expect(rootResult == .descending, "Root: 'ı' > 'i'")
    }

    @Test func turkishCedilla() throws {
        let tr = try RootCollator(tailoringNamed: "tr")
        let result = try tr.compare("ca", "ça")
        #expect(result == .ascending, "Turkish: 'ca' < 'ça'")
    }

    // MARK: - Hungarian: cs/sz are single letters

    @Test func hungarianCsDigraph() throws {
        let hu = try RootCollator(tailoringNamed: "hu")
        var primary = CollationOptions()
        primary.strength = .primary
        let huResult = try hu.compare("cs", "d", options: primary)
        #expect(huResult == .ascending, "Hungarian: 'cs' < 'd'")
    }

    @Test func hungarianSzDigraph() throws {
        let hu = try RootCollator(tailoringNamed: "hu")
        var primary = CollationOptions()
        primary.strength = .primary
        let huResult = try hu.compare("sz", "t", options: primary)
        #expect(huResult == .ascending, "Hungarian: 'sz' < 't'")
    }

    // MARK: - Croatian: lj/nj are single letters

    @Test func croatianLjDigraph() throws {
        let hr = try RootCollator(tailoringNamed: "hr")
        var primary = CollationOptions()
        primary.strength = .primary
        let hrResult = try hr.compare("lj", "m", options: primary)
        #expect(hrResult == .ascending, "Croatian: 'lj' < 'm'")
    }

    @Test func croatianNjDigraph() throws {
        let hr = try RootCollator(tailoringNamed: "hr")
        var primary = CollationOptions()
        primary.strength = .primary
        let hrResult = try hr.compare("nj", "o", options: primary)
        #expect(hrResult == .ascending, "Croatian: 'nj' < 'o'")
    }

    // MARK: - Polish: ł sorts after l, ź after z

    @Test func polishStrokedL() throws {
        let pl = try RootCollator(tailoringNamed: "pl")
        var primary = CollationOptions()
        primary.strength = .primary
        let plResult = try pl.compare("l", "ł", options: primary)
        let rootResult = try root.compare("l", "ł", options: primary)
        #expect(plResult == .ascending, "Polish: 'l' < 'ł'")
        #expect(rootResult == .same, "Root: 'l' == 'ł' at primary")
    }

    @Test func polishAccentedLetters() throws {
        let pl = try RootCollator(tailoringNamed: "pl")
        var primary = CollationOptions()
        primary.strength = .primary
        let result = try pl.compare("z", "ź", options: primary)
        #expect(result == .ascending, "Polish: 'z' < 'ź'")
    }

    // MARK: - Slovak: ch between h and i

    @Test func slovakChDigraph() throws {
        let sk = try RootCollator(tailoringNamed: "sk")
        let skResult = try sk.compare("h", "ch")
        let rootResult = try root.compare("h", "ch")
        #expect(skResult == .ascending, "Slovak: 'h' < 'ch'")
        #expect(rootResult == .descending, "Root: 'h' > 'ch'")
    }

    // MARK: - Welsh: ll/dd are single letters

    @Test func welshLlDigraph() throws {
        let cy = try RootCollator(tailoringNamed: "cy")
        var primary = CollationOptions()
        primary.strength = .primary
        let cyResult = try cy.compare("ll", "m", options: primary)
        #expect(cyResult == .ascending, "Welsh: 'll' < 'm'")
    }

    @Test func welshDdDigraph() throws {
        let cy = try RootCollator(tailoringNamed: "cy")
        var primary = CollationOptions()
        primary.strength = .primary
        let cyResult = try cy.compare("dd", "e", options: primary)
        #expect(cyResult == .ascending, "Welsh: 'dd' < 'e'")
    }

    // MARK: - Latvian: š and ž are separate primary letters

    @Test func latvianSCaron() throws {
        let lv = try RootCollator(tailoringNamed: "lv")
        var primary = CollationOptions()
        primary.strength = .primary
        let lvResult = try lv.compare("s", "š", options: primary)
        let rootResult = try root.compare("s", "š", options: primary)
        #expect(lvResult == .ascending, "Latvian: 's' < 'š' at primary")
        #expect(rootResult == .same, "Root: 's' == 'š' at primary")
    }

    // MARK: - Vietnamese: ă and ơ are distinct primary letters

    @Test func vietnameseAVariants() throws {
        let vi = try RootCollator(tailoringNamed: "vi")
        var primary = CollationOptions()
        primary.strength = .primary
        let result = try vi.compare("a", "ă", options: primary)
        #expect(result == .ascending, "Vietnamese: 'a' < 'ă' at primary")
    }

    @Test func vietnameseOVariants() throws {
        let vi = try RootCollator(tailoringNamed: "vi")
        var primary = CollationOptions()
        primary.strength = .primary
        let result = try vi.compare("o", "ơ", options: primary)
        #expect(result == .ascending, "Vietnamese: 'o' < 'ơ' at primary")
    }
}
