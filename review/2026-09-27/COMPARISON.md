# Jämförelse med andra Markdown-viewers

Granskad 2026-09-27. Detta är i första hand en **kodjämförelse**, kompletterad med körning av Glims och Markds parsers samt verifierade produktuppgifter. Jag har inte installerat och användartestat konkurrenternas fullständiga appar, mätt deras starttid eller minne, eller kört deras testsuiter. Deras markering/kopiering är därför inte empiriskt rangordnad här.

Alla lokala checkouter och exakta revisioner finns i [manifestet](evidence/competitor-revisions.json). Hänvisningarna nedan är låsta till dessa revisioner. Originalet mdview granskades och kördes enligt [huvudrapporten](REVIEW.md).

## Arkitektur och relevans

| Projekt | Kodens renderingsmodell | Vad vi kan lära oss | Begränsning i jämförelsen |
| --- | --- | --- | --- |
| **Vår mdview** | swift-markdown → en SwiftUI-vy per block/segment; SwiftMath-vyer vid sidan av texten | Litet SwiftUI-/AppKit-skal som kan återanvändas | Körda tester visar fragmenterad markering, döda länkar och innehållsförlust |
| **Glim** | SwiftUI + WKWebView; markdown-it + texmath/KaTeX och highlight.js | Sammanhängande dokument, native skal, relativ länkrouting, sökning, kopieringsmeddelanden och Quick Look | Parserkörning här; hela GUI:t ej kört. Har vuxit till viewer/editor |
| **Markd** | SwiftUI `DocumentGroup` + WKWebView; markdown-it/KaTeX/Mermaid/DOMPurify | Litet, direkt jämförbart skal och separat JS-renderingspipeline | Parserkörning här. Lokal `.md`-navigation är mindre komplett än hos Glim/ekino |
| **ekino/MarkdownViewer** | Tauri/Rust + HTML; marked, KaTeX, highlight.js, DOMPurify | Explicit routing för externa länkar, ankare och dokumentlänkar; sökning och fokuserade tester | Källkod granskad; frontendtestsuiter och GUI ej körda |
| **thgossler/mdv** | Go/Wails GUI + markdown-it/KaTeX/DOMPurify; separat terminalspår | Parserbaserad matte, `math`-fence, katalogbevakning och klart separerade GUI/TUI-vägar | Matte är beroende av extended-läget; ingen prestandajämförelse gjord |
| **rajatarya/mdviewer** | Tauri 2 + pulldown-cmark/ammonia → webview; KaTeX/Mermaid i JS | Rust-baserad parsing och sanitization, kodundantag i preprocessing | README:s ”zero webview overhead” motsägs av koden; JS-resurser hämtas från CDN |
| **MacDown 3000** | Objective-C/AppKit + äldre WebKit `WebView`; Hoedown-rendering och MathJax | Utbyggda regressionstester för bland annat urklipp, externa uppdateringar och MathJax-skroll | Editor med stor befintlig kodbas; ingen självklar modern grund för vår lilla viewer |
| **MacMark** | Objective-C/AppKit + WebKit `WebView`; cmark-gfm, mattepreprocessing och MathJax | Visar behovet av att skydda LaTeX före vanlig Markdown-parsning | Separat MacDown-fork, inte samma program som MacDown 3000 |
| **QuickMD** (extra kontroll) | Blockvis native `NSTextView` i en virtualiserad blocklista; SwiftMath | Native länkattribut och förbättrad blockprestanda | Ett NSTextView **per block** bevisar inte sammanhängande markering genom dokumentet |

En webview i en native macOS-app betyder här att operativsystemets webbmotor sköter dokumentytan. Glim och Markd använder fortfarande SwiftUI för appen. Detta gör det möjligt att behålla vårt lilla skal och samtidigt få en sammanhängande textmodell. Det är ett arkitekturargument, inte ett uppmätt påstående om hastighet eller minne.

## Glim: närmast vår befintliga stack

[MarkdownWebView.swift](https://github.com/yeduk3/Glim/blob/c24dc05e061ac66d3ea51c8a93933b5cf4841447/App/Viewer/MarkdownWebView.swift) skapar `WKWebView`, bundlar den lokala renderingssidan, uppdaterar dokumentet och kopplar sökning, markering och kodkopiering till native-funktioner. `openLink` skiljer externa URL:er från relativa dokument, percentavkodar filvägar och löser dem mot dokumentets katalog. Fragment inom sidan hanteras i JS; funktionen för andra filer strippar fragment, så cross-file-ankare bör testas särskilt före ett eventuellt byte.

[render.js](https://github.com/yeduk3/Glim/blob/c24dc05e061ac66d3ea51c8a93933b5cf4841447/App/Resources/web/render.js) registrerar KaTeX i markdown-it via texmath och rapporterar `selectionchange`. [AppState.swift](https://github.com/yeduk3/Glim/blob/c24dc05e061ac66d3ea51c8a93933b5cf4841447/App/Shared/AppState.swift) bevakar föräldrakatalogen via `DirectoryWatcher`, vilket adresserar samma filersättningsproblem som vår inodebundna bevakare missar.

**Lärdom:** kopiera ansvarsfördelningen mellan native skal, dokumentpipeline och länkrouting. Hela Glims editor, folder sidebar och tabs behöver inte följa med.

## Markd: litet skal, men inte komplett facit

[MarkdownWebView.swift](https://github.com/chathurank/Markd/blob/e19e66d413ac2466a20ad02df33af742d7dc2c88/Markd/Views/MarkdownWebView.swift) och [render.js](https://github.com/chathurank/Markd/blob/e19e66d413ac2466a20ad02df33af742d7dc2c88/Markd/Resources/Web/js/render.js) separerar SwiftUI från Markdown/KaTeX/DOMPurify. De medföljande JS-resurserna kan laddas lokalt. Till skillnad från vår efterhandsuppdelning registreras texmath i parsern.

[WebViewCoordinator.swift](https://github.com/chathurank/Markd/blob/e19e66d413ac2466a20ad02df33af742d7dc2c88/Markd/Services/WebViewCoordinator.swift#L155) skickar HTTP(S)-länkar till `NSWorkspace` men låter andra URL:er navigera i webviewn. Där finns inte samma explicita öppning av relativa Markdown-dokument som hos Glim eller ekino. Man ska därför inte anta att alla användarflöden är lösta bara för att grundrenderingen är bättre.

[FileWatcher.swift](https://github.com/chathurank/Markd/blob/e19e66d413ac2466a20ad02df33af742d7dc2c88/Markd/Services/FileWatcher.swift) försöker återansluta efter rename/delete och har debounce. Implementationen läser dock källans eventflags i det fördröjda arbetet och har en svag `self`-capture i cancel-handlern; den bör körtestas innan den återanvänds. Den har inte fått ett godkänt livscykeltest i denna review. Ingen licensfil identifierades i denna checkout; publikt tillgänglig kod ska inte automatiskt likställas med bekräftad rätt att återanvända den.

## ekino: bäst referens här för explicita läsflöden och frontendtester

[markdown.ts](https://github.com/ekino/MarkdownViewer/blob/59f2a21967b1ca3113cdebc8523f2fc6f0076288/src/markdown.ts) sätter ihop marked-tillägg för KaTeX, kodhighlighting, rubrik-ID:n, alerts och fotnoter och sanerar sedan resultatet med DOMPurify.

[main.ts, interceptLinks](https://github.com/ekino/MarkdownViewer/blob/59f2a21967b1ca3113cdebc8523f2fc6f0076288/src/main.ts#L1969) delar upp externa URL:er, interna ankare och Markdown-länkar. Dokumentlänkar med `#fragment` laddar filen innan de söker målankaret. Det motsvarar konkret det som saknas hos oss.

[search.ts](https://github.com/ekino/MarkdownViewer/blob/59f2a21967b1ca3113cdebc8523f2fc6f0076288/src/search.ts) bygger ett sökindex över textnoder och mappar träffar tillbaka till DOM-intervall; matte och diagram undantas uttryckligen. [markdown.test.ts](https://github.com/ekino/MarkdownViewer/blob/59f2a21967b1ca3113cdebc8523f2fc6f0076288/src/markdown.test.ts), `search.test.ts` och `integration.test.ts` visar betydligt mer konkret verifiering än vår nuvarande bygg-/processkontroll. Att filerna finns och har relevanta fall är verifierat; att hela sviten passerar har inte testats här.

## mdv: bra för matteparser och bevakning

[gui/main.go](https://github.com/thgossler/mdv/blob/292724fd0156b3e73069dab2371a965d634ad5df/gui/main.go) använder Wails och beskriver hur GUI-binärena bäddas in i startprogrammet. ”En executable” för distribution innebär alltså inte en native text-renderer utan webview.

[render.ts](https://github.com/thgossler/mdv/blob/292724fd0156b3e73069dab2371a965d634ad5df/gui/frontend/src/render.ts) registrerar matematik bara i extended-läget. [md/math.ts](https://github.com/thgossler/mdv/blob/292724fd0156b3e73069dab2371a965d634ad5df/gui/frontend/src/md/math.ts) har riktiga inline-/blockregler, stöd för `math`-fence och KaTeX-utdata med MathML. Detta skyddar LaTeX från den vanliga Markdown-inlineparsningen. En kommentar talar om att undvika prisfeltolkning genom efterföljande siffror, men den visade sökloopen kontrollerar inte det villkoret; även denna kod behöver egna adversariala fixtures.

[internal/watch/watch.go](https://github.com/thgossler/mdv/blob/292724fd0156b3e73069dab2371a965d634ad5df/internal/watch/watch.go) bevakar dokumentets föräldrakatalog och filtrerar filhändelser, i stället för att förlita sig på en descriptor till den ersatta filen. `watch_test.go`, `bridge_test.go` och `render.test.ts` ger konkreta testreferenser.

## rajatarya/mdviewer: korrigering av den ursprungliga diskussionen

README anger ”zero webview overhead”, men [lib.rs](https://github.com/rajatarya/mdviewer/blob/9b73da43b45550c5fce93bb63e5bcfc67e6596c6/src-tauri/src/lib.rs#L222) skapar uttryckligen `WebviewWindowBuilder`. [dist/index.html](https://github.com/rajatarya/mdviewer/blob/9b73da43b45550c5fce93bb63e5bcfc67e6596c6/dist/index.html#L9) laddar dessutom KaTeX och Mermaid från jsDelivr. Ett löfte om helt offline matte/diagram kan därför inte grundas på denna version.

Rust-pipelinen använder pulldown-cmark och ammonia och skyddar kodregioner före flera preprocessorer. KaTeX körs sedan i HTML-vyn. Filbevakningen pollar modifieringstid ungefär en gång i sekunden och slutar när filmetadata inte längre går att läsa. Det är en annan kompromiss än både vår kqueue-bevakare och mdv:s katalogbevakning.

**Lärdom:** intressant källkod, men README:s prestandafraser är inget benchmark. Uppgiften ”6 stjärnor” från den tidigare diskussionen är tidsbunden och används inte som aktuellt kvalitetsmått.

## MacMark och MacDown 3000 är två olika spår

I granskad [MacDown 3000 MPRenderer.m](https://github.com/schuyler/macdown3000/blob/962df74793d1d98a0ad9e85628f0a1d6c24769e2/MacDown/Code/Document/MPRenderer.m) används **Hoedown**, och [MPDocument.m](https://github.com/schuyler/macdown3000/blob/962df74793d1d98a0ad9e85628f0a1d6c24769e2/MacDown/Code/Document/MPDocument.m#L1883) har den äldre `WebView`/`WebPolicyDelegate`-modellen. MathJax-konfigurationen refererar CDN-version 2.7.3. Det finns omfattande testkällor, bland annat `MPMathJaxScrollTests.m`, `MPEditorViewPasteboardTests.m` och `MPResourceWatcherSetTests.m`. Storleken och historiken gör detta mer användbart som regressionsreferens än som minimalt skal att kopiera.

[MacMarks renderer](https://github.com/gitgonow/macmark/blob/99b954b7f8be52a4e5ac83b3826a076ebe9d034e/MacDown/Code/Document/MPRenderer.m) använder däremot **cmark-gfm** och skyddar matematik före parsningen med preprocessing och återinsättning. Även detta spår har MathJax/CDN och äldre WebKit-delegater. Delad härkomst betyder inte samma parser eller identiskt beteende.

## QuickMD: varför ”NSTextView” behöver preciseras

Detta extra projekt togs med som kontroll av ett native alternativ. [TextBlockView.swift](https://github.com/b451c/quickmd/blob/9956d0220e59d32e24929edff1ddf10b15fd6d6d/QuickMD/QuickMD/Views/TextBlockView.swift#L176) beskriver uttryckligen en läsbar `NSTextView` **för ett block** och implementerar native länkklick genom `NSTextViewDelegate`. [MarkdownView.swift](https://github.com/b451c/quickmd/blob/9956d0220e59d32e24929edff1ddf10b15fd6d6d/QuickMD/QuickMD/MarkdownView.swift#L213) använder en virtualiserad blocklista. Detta kan förbättra prestanda och textinteraktion inom block. Utan körtest går det inte att dra slutsatsen att dokumentövergripande markering är löst.

## Gemensamma körda parserfall: Glim och Markd

[compare-parsers.js](compare-parsers.js) läser respektive projekts **egen parserinitiering**, med de JS-bibliotek som finns i checkouten. Resultaten är HTML före DOM-sanitization och GUI-postprocessing; inga macOS-fönster från konkurrenterna startades.

| Samma Markdown-fall | mdview, originalvyer körda | Glim och Markd, parserresultat körda |
| --- | --- | --- |
| Tre typer av länkar | Blå statisk text, inga klickcallbacks | Tre riktiga `<a>`-element; navigationen är endast kodgranskad |
| Befintlig lokal bild | Utelämnad, även alt-text | `<img>`-element bevaras; faktisk bildladdning ej testad |
| Kryssad/okryssad lista | Två vanliga bullets | Två checkbox-inputs |
| Rubrik/lista/kodblock i citat och kod i listpost | Underinnehåll försvinner | Innehållet bevaras |
| 2×2-matris | En rad | MathML innehåller två `<mtr>`-rader |
| Matte över flera rader, i fetstil/rubrik/tabell | Råtext | Matte produceras i dessa kontexter |
| Escapade dollarpriser | Omtolkas till matte | Ingen extra mattenod för pristexten |
| `math`-fence | Vanligt kodblock | **Även här vanligt kodblock i båda granskade pipelines** |

[Parserloggen](evidence/competitor-parser.log) och de åtta `Glim-*.html`/`Markd-*.html`-filerna visar exakt vad som producerades. Detta ger starkare jämförelse för innehållsbevarande än en funktionslista, men ersätter inte tester av markering, copy/paste, filtrerad MathML, scroll eller VoiceOver i slutapparna.

## Markdown Lens och Twain: produktuppgifter, inte kodgranskning

För dessa identifierades ingen appkällkod som granskades i denna review. De ska därför inte få samma evidensetikett som de publika kodprojekten ovan.

**Markdown Lens** uppger GFM, KaTeX, Mermaid, syntax highlighting, Finder-öppning, live reload och länkar som öppnar andra Markdown-filer. Det gör den till en relevant produktreferens för vardagsläsning; den är inte här verifierad som felfri eller snabbast. [Utvecklarens webbplats](https://markdownlens.com/), [App Store-beskrivning](https://apps.apple.com/us/app/markdown-lens/id6758561513?mt=12).

**Twain** dokumenterar offline GFM/KaTeX/Mermaid, Quick Look för Markdown/MDX och sökning. ”Offline rendering” betyder inte att appen aldrig gör nätverksanrop: dokumentationen säger att fjärrbilder laddas som standard i appen, medan Quick Look blockerar dem. Den aktuella produkten inkluderar också en valfri editor och en Pro-del, så beskrivningen ”ren viewer” är inte hela bilden. [Twains dokumentation](https://docs.twain.md/).

För vårt projekt ger kodjämförelsen tydligast stöd för att prova **SwiftUI + en sammanhängande WKWebView med lokala resurser**, och mäta samma acceptansfall innan ett definitivt renderingsbyte. Glim/Markd visar formen, ekino visar flera av läsflödena, och mdv visar en användbar matte- och bevakningsstruktur. Ingen av dem behöver tas över i sin helhet.
