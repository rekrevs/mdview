# Reviewplan 2026-09-27

Granska befintlig mdview (HEAD 4de9fc80b28fb90c47008c779bcccd552dd1d057), utan att ändra produktionskoden. Användarens fokus: markering/kopiering över stycken, klickbara länkar och allmän läsupplevelse. Jämför även koden i relevanta öppna alternativ.

1. Läs implementation, dokumentation och tidigare verifieringsunderlag.
2. Bygg aktuell kod. Skapa reproducerbara testfall för text/länkar, GFM, matematik, bildvisning, filbevakning och fönsterbeteende.
3. Kör verklig SwiftUI/AppKit-rendering i en separat testvärd med originalkoden. Spara bilder och loggar; skilj simulerade event från manuell systeminteraktion.
4. Inspektera öppna alternativ vid dokumenterade revisioner. Jämför renderingsmodell, navigering, markering, matte, bevakning och tester. Verifiera produktuppgifter mot primärkällor.
5. Sammanställ prioriterade fynd med kodankare, reproduktion, konsekvens och rekommenderad åtgärd. Redovisa testbegränsningar och vad som fungerar.

Backloggen används som historisk evidens; reviewn startar inte den pågående implementationen T-0013 och ändrar inga taskstatusar.

## Slutfört

Samtliga fem steg genomförda. Leverans: `REVIEW.md`, `COMPARISON.md`, originalkodsbaserad AppKit-testvärd, parserjämförelse, sju renderingsfixtures, åtta bilder, körloggar och låsta konkurrentrevisioner. `verify-evidence.py` verifierar positiva kontroller och rapportens evidensreferenser. Produktionskod och backlog oförändrade. Testbegränsningar är uttryckligt dokumenterade i rapporterna.
