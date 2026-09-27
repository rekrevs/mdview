# mdview 2.0.1 — förbättrad formaterad kopiering

2026-09-27, Wotan T-0019. Utgår från användarens bekräftelse att rubrik och vanlig text redan går bra att klistra in i Word.

## Konkreta förbättringar

- Delmarkeringar behåller sina omgivande formateringstaggar. Ett ord ur fet text, en rubrik eller kod blir inte längre oformaterad text i HTML-kopian. Omarkerad text följer inte med.
- Tabeller får portabla cellkanter, cellmarginaler och kolumnjustering. Kod har explicit Courier New och bevarade blanksteg. Stilarna följer kopian och är oberoende av viewerns CSS, mörkt läge och zoom.
- Utdrag ur numrerade listor behåller det första markerade objektets nummer, även vid liststart 0.
- Relativa länkar och ankare får fullständig adress med källdokumentet som utgångspunkt. Lokala länkar fortsätter vara lokala; de blir inte delbara webblänkar.

Vanlig Cmd+C lägger fortfarande både text och HTML på urklippet. Kodblockets Copy-knapp ger fortfarande exakt kodtext. Matematik kopieras fortsatt som LaTeX och bilder som alttext. Denna patch konverterar inte ekvationer till Word-ekvationer och bäddar inte in bilder.

## Verifiering

Fyra nya rendererreproduktioner misslyckades på 2.0.0 och passerade efter rättningen. Slutresultat: **19/19 renderer-test**, **11/11 Swift-test**, **33/33 native WebKit/NSPasteboard-kontroller**. [Native-logg](checks.log).

Det riktiga HTML-urklippet från native-testet klistrades in i ett separat nytt dokument i **Microsoft Word för Mac 16.113.1**. Dokumentet sparades och stängdes, och tidigare urklipp återställdes. Inget befintligt användardokument ändrades. [Sparat testdokument](word-paste.docx).

`python scripts/check-word-paste.py <sparad-docx>` passerade **8/8 kontroller** av Words sparade dokumentstruktur:

1. Rubriken är riktig Heading1.
2. Tabellen är en redigerbar Word-tabell med sex celler.
3. Alla celler har kanter.
4. Höger- och centrumjustering är bevarade.
5. Båda kodradernas fyra inledande mellanslag finns kvar.
6. Words HTMLCode-stil använder Courier New.
7. Extern länk och fullständig lokal fillänk finns i dokumentets relationer.
8. Formelns LaTeX förekommer en gång.

HTML och ren text från urklippet finns i `office-clipboard.html` respektive `office-clipboard.txt`. Kontroll av Words sparade struktur är inte en garanti om identisk visuell layout i alla Office-program. PowerPoint och Outlook har inte testats. Den särskilda delmarkerings- och listnumreringskontrollen gjordes i renderer/native-urklippstesterna, inte i Word.

Release 2.0.1 byggd och installerad med säkerhetskopia av föregångaren. Appens resurser och signatur validerade av installationsskriptet. Starta om mdview för att använda uppdateringen.

## Reproduktion av Word-testet

Efter `make release` och `python scripts/check-reader.py`:

```bash
swift -sdk /path/to/MacOSX.sdk Tests/Integration/WordPaste.swift \
  .build/reader-checks Tests/Integration/WordPaste.applescript
python scripts/check-word-paste.py <docx-sökvägen-som-testet-skrev-ut>
```

Word-testet är frivilligt och ingår inte i `make check`. Det kräver installerat Word och macOS Automation-behörighet. Första sparningen kan kräva att Word får åtkomst till just testmappen. Skriptet skapar ett nytt dokument med unikt filnamn, sparar det utan att lägga det i listan över senaste filer, stänger testdokumentet och återställer urklippet.
