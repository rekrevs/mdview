# Review av mdview — 2026-09-27

**Bedömning:** mdview fungerar för enkel löptext och en del enkla formler, men är ännu inte en tillförlitlig viewer för tekniska Markdown-rapporter. Problemen gäller både läsinteraktion och förlust/förändring av innehåll. Ett byte av dokumentrendering är mer motiverat än ytterligare putsning av avstånd runt formler.

Granskad revision: `4de9fc80b28fb90c47008c779bcccd552dd1d057`. Produktionskod och Wotan-statusar har inte ändrats. [Kodjämförelsen](COMPARISON.md) behandlar åtta publika projekt samt produktuppgifter för Markdown Lens och Twain.

## Testmetod och avgränsning

Jag byggde originalkoden och kompilerade dess oförändrade `ContentView.swift`, `MathView.swift` och `MarkdownDocument.swift` i en separat AppKit-testapp. Den startades via **macOS LaunchServices**, med ett riktigt aktivt fönster. Testvärden använder originalets fullständiga `ContentView`, inklusive tangentbordsvy och skrollvy. Musdrag och klick skickas som syntetiska AppKit-event; kopieringen går via responderkedjan och det verkliga urklippet, vars tidigare innehåll återställs efter testet. Detta är körda interaktionstester, inte bara kodläsning.

Testvärden är inte hela `DocumentGroup`-applikationen. Finder-association, dokumentöppning i den installerade appen, appmenyer, fysisk svensk tangentbordslayout och VoiceOver har därför **inte** verifierats från början till slut. Länkarnas rendering/klickbeteende testades separat med en `openURL`-räknare och en fungerande SwiftUI-länk som positiv kontroll; inga externa sidor behövde öppnas. Filbevakaren testades direkt, utanför GUI-testets upptagna huvudkö, med riktiga diskoperationer.

Miljö: Apple Silicon, macOS 27.0 (26A428), Swift 6.4, SDK 26.5. Beroenden: swift-markdown 0.7.3, swift-cmark 0.7.1, SwiftMath 1.7.3. Aktuell beroendelåsning finns i [evidence/package-resolved.json](evidence/package-resolved.json).

| Kontroll | Resultat / evidens |
| --- | --- |
| Vanlig `swift build` | Misslyckades först på sandboxens cacheåtkomst; även med åtkomst saknade SDK 27 `SwiftUIMacros.StateMacro`. Miljöproblem, inte visad produktregression. |
| Debug med SDK 26.5 och native build system | Godkänd. Ingen ändring i produktionskod krävdes. |
| Release med samma SDK | Godkänd; [bygglogg](evidence/build-release.log). |
| `swift test` | Misslyckas: **no tests found**. [Logg](evidence/swift-test.log). |
| Originalvyer i testapp | Sju renderingsfall, sparade Markdown-fixtures och PNG-bilder, visuellt granskade. |
| Interaktion | Enstyckskopiering fungerar som kontroll; flerstyckskopiering och dokumentomfattande Select All fallerar. Länkkontrollen fungerar, Markdown-länkarna gör det inte. |
| Flera fönster / tangentbord | Zoom påverkar båda fönstren. Pil ned, Cmd+pil ned och Home flyttar skrollpositionen korrekt när originalets tangentbordshanterare anropas. |
| Filbevakning | Skrivning på plats och första atomiska ersättningen upptäcks; senare skrivningar tappas. 25 avslutade bevakare lämnar 25 extra filbeskrivare öppna. |
| Glim och Markd | Deras faktiska parserinitiering och medföljande JS-bibliotek kördes på fyra gemensamma fixtures vardera. **Inte** fullständiga GUI-tester av konkurrenterna. |

[GUI-/AST-logg](evidence/runtime.log), [filbevakarlogg](evidence/watcher.log), [konkurrenternas parserresultat](evidence/competitor-parser.log). Den första direkta CLI-starten gav inget aktivt testfönster och fallerade även på positiv kopieringskontroll. Dessa resultat ersattes av LaunchServices-körningen. Motsvarande positiv kontroll för filbevakning säkrades i en separat process. Slutresultaten bygger på de fungerande kontrollerna.

## Prioriterade fynd

P1 = blockerar grundläggande läsning eller kan visa fel/utelämnat innehåll. P2 = betydande funktionell eller teknisk brist. Ingen P0 har identifierats.

### R1 · P1 · Sammanhängande markering och kopiering saknas

**Ankare:** [ContentView.swift](../../Sources/ContentView.swift), rader 127–133, 229–238, 349–355.

Dokumentet renderas som en `VStack` av separata `Text`-vyer, och stycken med matte splittras ytterligare. `.textSelection(.enabled)` på föräldern skapar ingen gemensam textmodell.

**Reproduktion:** markera `Alpha first paragraph.` och kopiera: hela stycket kommer med. Dra sedan från början av Alpha till slutet av nästa stycke, `Bravo second paragraph.`. Urklippet innehåller fortfarande endast `Alpha first paragraph.`. `selectAll:` följt av `copy:` ger också bara Alpha. Testfönstret var aktivt och kopieringskontrollen lyckades. [Markering](evidence/07-cross-selection.png), [logg](evidence/runtime.log).

**Konsekvens:** användaren kan inte citera ett sammanhängande rapportavsnitt. Tabeller, listor och matte har samma uppdelade grundmodell; deras fullständiga urklippsbeteende är inte separat testat här.

**Åtgärd:** en sammanhängande DOM i `WKWebView`, alternativt ett gemensamt `NSTextView`/TextKit-dokument. Att ersätta varje enskilt stycke med var sitt `NSTextView` löser inte dokumentövergripande markering.

### R2 · P1 · Länkar är dekorativ text

**Ankare:** [ContentView.swift](../../Sources/ContentView.swift), rader 377–381; även 48–50 och 104–116.

`Markdown.Link.destination` används aldrig. Resultatet blir vanlig text med blå färg och understrykning, utan länk-attribut eller klickåtgärd. Därför nås inte den befintliga URL-hanteraren från renderade länkar.

**Reproduktion:** klicka på externa, relativa och ankarlänkar. Räknaren får **0 anrop**; kontrollänken får **1 anrop**. Den renderade länken exponerar dessutom `AXStaticText` och inga accessibility actions. Se [logg](evidence/runtime.log).

**Åtgärd:** återställ riktiga länkobjekt och testa externa URL:er, `mailto:`, relativa `.md`/`.markdown`, mellanslag/percentkodning samt fragment. Rubrik-ID:n och ankarhopp behöver också implementeras; de saknas idag. `baseURL` skickas omkring men används inte för att skapa länkar.

### R3 · P1 · Matte kan ändra betydelse under parsningen

**Ankare:** [ContentView.swift](../../Sources/ContentView.swift), rader 128 och 249–270.

Matte identifieras i redan parsade `Markdown.Text`-noder. Då har Markdown redan konsumerat backslash-escapes och formateringsmarkörer.

**Reproduktion:** `$$\begin{pmatrix} a & b \\ c & d \end{pmatrix}$$` blir i AST en sträng med **en** backslash mellan raderna. SwiftMath får därför inte LaTeX-radbrytningen och visar en enda rad. Felet finns även i projektets ursprungliga `test-math.md`. `$a*b*c$` blir text med Markdown-emfas i mitten och renderas inte som motsvarande formel. [Bild](evidence/04-math-integrity.png), [befintligt testdokument](evidence/06-existing-fixture.png).

**Konsekvens:** en teknisk rapport kan se plausibel ut men visa fel matematiskt objekt. Detta bör prioriteras före typografisk putsning.

**Åtgärd:** skydda matematikens originalkälltext före vanlig inlineparsning eller använd en parser med riktiga mattetoken. Testa att exakt LaTeX, inklusive dubbla backslash, når mattemotorn.

### R4 · P1 · Vanliga matteformer och kontexter stöds inte

**Ankare:** [ContentView.swift](../../Sources/ContentView.swift), rader 249–270, 283–324, 199, 405–408 och 585–587.

**Kört:** `$$` på egna rader blir separata textnoder med `SoftBreak`; uttrycket renderas som råtext. Matte i fetstil, rubriker och tabellceller blir också råtext. Ett `math`-fence går till vanlig kodblocksvy. `$a$ then $$b$$` lämnar första uttrycket orenderat eftersom sökningen efter `$$` prioriteras över tidigare `$`. Escapade priser `\$5 and \$10` omtolkas till matte. [Bild](evidence/02-math.png), [fixture](evidence/02-math.md).

**Åtgärd:** definiera en gemensam mattesyntax och dess kontexter, med tester för flerlinjeblock, blandade delimiters, escapes och kodundantag. GitHub stöder `$…$`, alternativ inlineform med backticks, `$$`-block och `math`-fence och använder MathJax. KaTeX/SwiftMath är separata kompatibilitetsfrågor; våra fel här inträffar redan före mattemotorn. [GitHubs dokumentation](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/writing-mathematical-expressions).

### R5 · P1 · Bilder försvinner helt

**Ankare:** [ContentView.swift](../../Sources/ContentView.swift), rader 357–396 och 671–695.

`LocalImageView` finns, men anropas aldrig från renderingen. `Markdown.Image` faller till `default` och returnerar tom text. Även alt-texten försvinner.

**Reproduktion:** [läs-fixturen](evidence/01-reading.md) pekar på en befintlig ikon med korrekt relativ väg från dokumentets katalog. AST innehåller bilden; [renderingen](evidence/01-reading.png) innehåller varken bild eller alt-text. Full `ContentView` har fixturefilens riktiga `fileURL`.

**Åtgärd:** rendera bildnoder, lös relativa sökvägar mot dokumentet och visa begriplig fallback när en bild saknas.

### R6 · P1 · Innehåll i blockcitat och listor utelämnas

**Ankare:** [ContentView.swift](../../Sources/ContentView.swift), rader 432–437, 474–483 och 519–528.

Blockcitat hanterar endast stycken. Listposter hanterar stycken och nästlade listor, men inte kodblock, citat eller andra blocktyper.

**Reproduktion:** rubrik, lista och kodblock i ett citat samt kodblock i en listpost finns i AST men saknas på skärmen. Det står uttryckligen `SHOULD APPEAR` i fixturen. [Fixture](evidence/03-structure.md), [bild](evidence/03-structure.png).

**Åtgärd:** återanvänd rekursiv blockrendering genom alla blockcontainrar. Vanlig CommonMark får inte tyst förlora innehåll.

### R7 · P1 · Live reload dör efter atomisk sparning

**Ankare:** [ContentView.swift](../../Sources/ContentView.swift), rader 705–727.

Bevakningen sitter på filens öppna descriptor. `.rename`/`.delete` triggar callback, men bevakaren öppnar aldrig filen på nytt. Efter att ett redigeringsprogram ersatt filen bevakas den gamla inoden.

**Kört:** skrivning på plats → callback; första atomiska sparning → callback; andra atomiska sparning → **ingen callback**; skrivning på plats i den nya filen → **ingen callback**. [Logg](evidence/watcher.log).

**Åtgärd:** bevaka föräldrakatalogen och filtrera på sökväg, eller återanslut säkert efter ersättning. Lägg till debounce och testa flera efterföljande sparningar, borttagning och återskapande.

### R8 · P2 · Filbevakaren läcker descriptors

**Ankare:** [ContentView.swift](../../Sources/ContentView.swift), rader 729–741.

Cancel-handlern fångar `self` svagt. När `deinit` avbryter källan är objektet borta när handlern behöver hämta `fileDescriptor`, så `close` uteblir.

**Kört:** skapa och släpp 25 bevakare, låt huvudloopen köra mellan dem och räkna öppna descriptors med `fcntl`. Resultat: **+25 descriptors**. [Logg](evidence/watcher.log).

**Åtgärd:** ge cancel-handlern det öppna descriptorvärdet direkt och säkra exakt en stängning per descriptor.

### R9 · P2 · GFM-checkboxarnas status går förlorad

**Ankare:** [ContentView.swift](../../Sources/ContentView.swift), rader 495–508.

AST skiljer mellan `[ ]` och `[x]`, men renderer visar alltid `•`. I [läs-fixturen](evidence/01-reading.png) ser väntande, klara och vanliga listposter likadana ut. Detta gäller visning av status; redigering av checkboxar behöver inte vara en viewer-funktion.

**Åtgärd:** visa AST:s checkboxstatus. Lägg till kontroll mot både kryssad och okryssad post.

### R10 · P2 · Kodblockets första indrag raderas

**Ankare:** [ContentView.swift](../../Sources/ContentView.swift), rad 407.

`trimmingCharacters(in: .whitespacesAndNewlines)` tar bort första radens inledande mellanslag, men lämnar nästa rads indrag. Två lika indragna Python-rader visas med olika indrag. [Bild](evidence/03-structure.png).

**Åtgärd:** bevara kodens whitespace; avlägsna högst en definierad avslutande newline för presentation. Testa kopierad kod mot källan. Ingen syntax highlighting implementeras, trots README:s påstående.

### R11 · P2 · Inline-matte bryter textflödet

**Ankare:** [ContentView.swift](../../Sources/ContentView.swift), rader 234–238 och 618–659.

Layouten placerar hela textsegment och formler som separata rektanglar och centrerar dem vertikalt. Det är ingen gemensam radbrytare med textbaslinjer.

**Kört:** vid stödd fönsterbredd **500 pt** hamnar formeln till höger om ett tvåradigt textsegment och på en annan baslinje; efterföljande text börjar på en separat rad. [Bild](evidence/05-flow-narrow.png).

**Åtgärd:** låt samma textlayout hantera både text och inline-matte. Enstaka spacing-konstanter kan inte lösa kombinationen radbrytning, baslinje och sammanhängande markering.

### R12 · P2 · Zoomkommandot påverkar alla dokumentfönster

**Ankare:** [mdviewApp.swift](../../Sources/mdviewApp.swift), rader 14–27; [ContentView.swift](../../Sources/ContentView.swift), rader 59–67.

Appen skickar globala notifieringar och alla öppna `ContentView` lyssnar. Ingen kontroll görs av aktivt fönster.

**Kört:** två fönster visar samma formel, ett är aktivt. En `.zoomIn` ändrar bådas formelbredd från **56,5 till 62,0 pt**. [Logg](evidence/runtime.log).

**Åtgärd:** rikta kommandot mot aktivt dokument, exempelvis via fokuserade värden eller responderkedjan. Om global zoom önskas ska det vara ett medvetet dokumenterat beteende.

### R13 · P1 för distribution · Appbundlen saknar SwiftMath-resurser

**Ankare:** [bundle.sh](../../bundle.sh), rader 25–35; genererad `SwiftMath.build/DerivedSources/resource_bundle_accessor.swift`.

Bundle-scriptet kopierar executable och ikon men inte `SwiftMath_SwiftMath.bundle`. Den genererade resursaccessorn söker först i appen och därefter på byggmaskinens absoluta `.build`-sökväg. Om inget finns anropas `fatalError`.

**Evidensnivå:** kod-/paketeringsgranskning, **inte** en körd installation på ren Mac. Reviewns math-rendering har tillgång till byggträdet och bevisar därför inte att appen är självförsörjande.

**Åtgärd:** paketera och verifiera resurserna på den plats accessorn faktiskt söker; testa en flyttad app utan åtkomst till byggträdet.

### R14 · P2 · Verifieringshistoriken överskattar färdigställandet

**Ankare:** [T-0012](../../wotan/dev-log/T-0012.md), [README](../../README.md), [Package.swift](../../Package.swift).

T-0012 är `DONE` och deklarerar framgång, men acceptanspunkterna för länkar, bilder och annat är okryssade. Evidensen är build, bundle och en levande process. README beskriver fortfarande MarkdownUI och syntax highlighting, medan implementationen använder swift-markdown + egen renderer. `swift test` hittar inga tester.

**Åtgärd:** synkronisera dokumentationen och kräv verkliga läs-/interaktionskontroller för renderingsbyten. Reviewn ändrar inte gamla taskstatusar i efterhand.

## Övriga observationer och sådant som fungerar

Grundläggande rubriker, fetstil, kursiv, genomstrykning, enkla listor, enkla tabeller och vanliga kodblock syns. `$E=mc^2$`, enkla enrads-`$$` och flera av `test-math.md`:s integraluttryck renderas. Matte i vanliga kodblock lämnas korrekt bokstavlig. Ljus och mörk presentation är läsbara i de körda fallen, inklusive matte: [mörkt läge](evidence/08-dark.png).

Tabellernas vänster-/höger-/centreringsmetadata ignoreras: `TableCellContentView` använder alltid `.leading`, bekräftat i [strukturbilden](evidence/03-structure.png). Sökning, TOC, Mermaid och Quick Look saknar implementation. Rå HTML utelämnas enligt uttryckligt designbeslut; detta är en kompatibilitetsgräns, inte ett nytt fel i sig. Granskningen ska inte likställa stöd för en GFM-parser med komplett GFM-visning.

Ett enkelt dokument med 200 stycken gick att skapa och skrolla i testvärden. Det är ingen jämförbar starttids- eller minnesbenchmark, och inget stöd för slutsatser om megabytefiler. Eager `VStack`, ny AST-parsning i `body` och dubbla mattelayoutberäkningar är kodbaserade prestandarisker som bör mätas först när korrektheten är återställd.

## Rekommenderad väg

**Behåll det lilla macOS-skalet, men prova en sammanhängande `WKWebView` med lokalt bundlade Markdown-/KaTeX-resurser som ersättning för renderingsytan.** Glim är närmast vår teknikstack; ekino är en bra referens för länkrouting, sökning och tester; mdv är en bra referens för parserintegration och katalogbevakning. Det är en rekommendation utifrån granskningen, inte ett fattat projektbeslut eller en påbörjad migration.

Ett gemensamt `NSTextView` med attachments är ett rimligt alternativ om native textsemantik är ett hårt krav, men tabeller, matte, bildlayout och export blir mer egen kod. QuickMD:s granskade implementation är blockvis `NSTextView`, vilket visar varför ordet ”native” i sig inte garanterar sammanhängande markering.

Den första prototypens godkännandekrav bör vara konkreta:

1. Dra och kopiera genom två stycken, lista, kodblock och tabell; definiera tydligt hur formeltext kopieras.
2. Externa, relativa och interna ankarlänkar fungerar med rätt destination och navigation.
3. Samtliga review-fixtures bevarar innehållet, särskilt matrisrader, nästlade block, bilder och checkboxstatus.
4. Sökning hittar text på båda sidor om formatering; zoom håller sig till aktivt fönster.
5. Minst tre atomiska sparningar i följd uppdaterar samma dokument; inga descriptors läcker efter upprepade öppna/stäng.
6. Appen fungerar utan nätverk och utan byggträd; rå HTML och länkscheman hanteras enligt en uttrycklig policy.

Återanvänd först därefter testfallen för ett jämförbart prestandatest och överväg TOC, Mermaid, export och Quick Look. De två först rapporterade problemen måste vara verifierat lösta före fler funktioner.

## Reproducera

Från repositoryroten, på motsvarande macOS/SDK:

```sh
swift build --build-system native --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
python review/2026-09-27/run-harness.py
node review/2026-09-27/compare-parsers.js
```

GUI-testet behöver en inloggad macOS-session. Scriptet startar och avslutar en temporär review-app; det installerar inte om mdview. Konkurrenttestet förutsätter checkout-sökvägarna i scriptet och revisionerna i [manifestet](evidence/competitor-revisions.json). Det kör deras parsers före eventuell DOM-sanitization, inte deras färdiga appar eller testsuiter. Se [testvärdens källkod](ReviewHarness.swift).
