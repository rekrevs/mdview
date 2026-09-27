# mdview 2.0.0 — genomförande och verifiering

2026-09-27. Den godkända omskrivningen är byggd, testad och installerad i `~/Applications/mdview.app`. Den gamla appen sparades som `mdview.app.backup-20260927-091205-81934`. Äldre körande instanser måste avslutas och appen öppnas igen för att använda den nya versionen. Ingen commit eller publicering har gjorts.

## Arkitektur och resultat

Den tidigare uppdelningen i separata SwiftUI-textblock är ersatt med ett sammanhängande WKWebView-dokument. Det gör markering, kopiering, radbrytning och länkar till dokumentfunktioner. SwiftUI/AppKit ansvarar för dokumentfönster, menyer, native-sökfält, innehållsförteckning, länköppning och filbevakning. Zoom och sökning tillhör respektive fönster.

markdown-it 15.0.2, KaTeX 0.18.9 och highlight.js 11.12.0 ligger lokalt i appen med fonter, licenser, versionsmanifest och källarkivens kontrollsummor. Inga renderingstjänster eller CDN behövs. Teknikvalet följer erfarenheterna i [källkodsjämförelsen](../../review/2026-09-27/COMPARISON.md): en webbdokumentmodell löser de grundläggande interaktionsproblemen och etablerade parsers minskar behovet av specialfall. Appen behåller sitt native-fönster och sin inriktning som läsare.

## Samtliga fynd i reviewn

| Fynd | Åtgärd | Verifiering |
|---|---|---|
| R1: markering/kopiering över block | Sammanhängande DOM; text- och HTML-urklipp; matematik kopieras som ursprunglig LaTeX en gång | Verklig musdragning över två stycken, macOS Copy, Cmd+A/C i releaseappen, JS-test över lista/kod/tabell/formel |
| R2: döda länkar | Riktiga länkar, ankarnavigering, relativ filupplösning, native systemöppning | Klick till injicerad extern endpoint, ankarhopp, faktiskt klick till separat `.markdown`-fönster |
| R3: förstörda matrisrader | TeX skyddas innan Markdown bearbetar specialtecken | Tvåradig matris i native WebKit, kopierad källtext, visuell granskning |
| R4: matematiksyntax och sammanhang | Inline, display, multiline, fenced math, formaterad text och tabeller; kod/valutatext undantas | Rendererregressioner och fem matematikförekomster i native-fönster |
| R5: bilder saknas | Relativa lokala bilder genom separat bildprotokoll; alttext/felindikering | Verklig avkodning av bild med procentkodat mellanslag i sökvägen |
| R6: nästlat innehåll försvinner | Standardparser och rekursiv dokumentstruktur | Nästlade rubriker, listor och kod i citat |
| R7: atomiska sparningar bryter reload | Bevakning av både katalog och aktuell filidentitet | Upprepade atomic replace, in-place, delete/recreate; tre verkliga reader-uppdateringar |
| R8: läckta fildeskriptorer | Explicit cancellation och descriptor-ägande utan beroende av levande owner | 50 start/stopp-livscykler; avbrutna callbacks |
| R9: checklistans tillstånd försvinner | Disabled checkbox med bevarat tillstånd och kopierad markör | DOM, native-fönster och urklipp |
| R10: kodindrag förstörs | Källkod behålls exakt; separat kopieringsknapp | Första rad, följande rader och avslutande radbrytning i faktiskt urklipp |
| R11: inline-matte bryter textflödet | Inline KaTeX inom samma stycke | 500-punkters fönster utan horisontellt spill; granskad skärmbild |
| R12: zoom ändrar alla fönster | ReaderController per dokument och fokusbundna menykommandon | Två native-fönster; andra fönstrets modell och DOM förblir oförändrade |
| R13: resurser saknas i appen | Explicit resursinventering, båda SwiftPM-layoutvarianterna, uppslag från installerad bundle | Relokerad testapp laddar från `.app/Contents/Resources`, signatur-/resurskontroll på installerad app |
| R14: dokumentation och test saknas | Ny README, bygg-/installationsskript, beroendelicenser och testsviter | Debug/release, Swift/JS/native/shell-tester, dokumenterade kommandon |

## Körda kontroller

- `make check`: **11/11 Swift-test** och **15/15 renderer-test**.
- `python scripts/check-reader.py`: **30/30 kontroller** i en LaunchServices-startad app med riktig WKWebView, NSWindow och NSPasteboard. [Logg](checks.log).
- `osascript Tests/Integration/ShellChecks.applescript <test-pid>`: **12 kontroller** av den faktiskt byggda releaseappens UI. Cmd+F, direkt inmatning, träffräknare, Cmd+G, Shift+Cmd+G, Return, Shift+Return, Escape, Cmd+A/C, outline och relativ filöppning passerade. Båda dokumentfönstren behölls.
- Debug och release byggda. Paketering och strikt ad-hoc-signaturvalidering passerade. Installation testad först i temporär katalog med befintlig sentinel-app, sedan i `~/Applications` med sparad föregångare.
- Installerad och testad releasebinär har identisk SHA256: [installationsbevis](installation.json).
- `git diff --check`: utan anmärkning.

GUI-testningen upptäckte två ytterligare integrationsfel: flat SwiftPM-bundle gav fel resurssökväg, och Return i sökfältet återställde träffpositionen. Båda är rättade. Sökfältet använder nu NSSearchField med explicit tangenthantering och fokus vid anslutning till fönstret. Oförändrad söktext startar inte om sökningen; detta har en egen native-regression.

[Markering](selection.png), [ljust läge](reader-light.png), [mörkt läge](reader-dark.png), [matris och tabell](math-and-table.png), [smalt textflöde med matte](narrow-math.png) har inspekterats visuellt.

## Avgränsningar och reproduktion

Testmiljö: Apple Silicon, macOS 27, installerad macOS 26.5 SDK som lokal workaround för preview-toolchainens SwiftUI-makroproblem. Appens deklarerade minimum är macOS 13; äldre OS och Intel har inte körtestats. Swift Testing-kontrollerna kräver macOS 14+. Det är inte en prestandajämförelse eller ett generellt påstående om full GFM/MathJax-kompatibilitet.

KaTeX stöder inte hela LaTeX/MathJax. Felaktiga eller ej stödda formler visas som källtext med felindikering. Raw HTML exekveras inte. Mermaid, MDX, Quick Look och PDF-export ingår inte. Sökning avser synlig prosa och kod, inte formelns interna MathML/LaTeX. Webb-/e-postlänkens native systemendpoint testas med injicerad mottagare så att testsviten inte startar användarens externa appar. Den relativa Markdown-länken testades däremot genom faktisk fönsteröppning.

Kör `make check` och `make gui-test` för automatiserade kontroller. För full release-shellkontroll: `make release`, kör reader-harnessen för att skapa `.build/reader-checks/document.md`, öppna filen i en separat instans med `open -n -a "$PWD/mdview.app" "$PWD/.build/reader-checks/document.md"`, identifiera just den processens PID och kör AppleScript-filen ovan. Den kontrollen kräver Accessibility-behörighet och en aktiv desktop. Testerna återställer urklippet. Shelltestet bör köras utan samtidig manuell tangentbordsanvändning.

Wotan: T-0014–T-0018 slutförda. Även de äldre T-0007 (sökning) och T-0013 (inline-matte) är avslutade genom denna implementation. Det tidigare alternativa MarkdownView-experimentet T-0010 är parkerat som IDEA.
