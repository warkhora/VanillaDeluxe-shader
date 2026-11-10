# VanillaDeluxe 1.11.0 – Performance & Polish Update

En shaderpack for Minecraft Java 26.2 med Iris 1.11.4 eller nyere og Sodium. Pakken har
fotorealistisk lyssetting med en mørk, varm og rødlig karakter, og er laget for høy ytelse.

## Installasjon

1. Installer Fabric med Iris og Sodium for Minecraft 26.2. Iris 1.11.4 eller nyere er påkrevd.
2. Legg `VanillaDeluxe_v1.11.0.zip` i mappen `shaderpacks` i Minecraft-mappen din. Ikke pakk den ut.
3. I spillet: **Options → Video Settings → Shader Packs**, velg VanillaDeluxe og trykk **Apply**.

**Viktig:** Iris støtter ikke Vulkan. Står **Graphics API** i videoinnstillingene på Vulkan, må
du sette det til Default eller Prefer OpenGL.

## Ray Tracing og profiler

Velg profil øverst i **Shader Pack Settings** eller i menyen **Ray Tracing**. Profilene styrer bare
ray tracing. Skygger, skyer og resten stiller du i sine egne menyer.

| Profil | Hva den gjør | GPU-tid i testriggen, 1440p |
|---|---|---|
| **Av** | Vanlig Minecraft-lys med omgivelsesskygge | 3,4–3,8 ms |
| **Lav** | Strålesporet lys og skygger fra fakler, glowstone og lava | +0,4–1,0 ms |
| **Middels** (standard) | Som Lav, pluss sprettlys med 1 spratt og 2 chunks rekkevidde | omtrent som forrige versjon |
| **Høy** | 3 spratt, 4 chunks rekkevidde og Advanced Color Tracing | +0,5–0,9 ms over Middels |
| **Ultra** | Opptil 24 spratt, 16 chunks rekkevidde og Advanced Color Tracing | +0,8–1,7 ms over Middels |

I menyen kan du også stille **Lysspratt** (1–24), **Strålelengde** (1–16 chunks), **Trinn per stråle**,
**Bredde på denoiser** og **Mykt fyllys** hver for seg.

**Strålesporet blokklys.** Skyggepasset legger blokkene i en voksel-scene på 128 × 64 × 128 blokker
rundt spilleren, og lister hver lyskilde. Hver piksel i halv oppløsning velger én lyskilde i nærheten og
sender én skyggestråle mot den. Lyset virker også når lyskilden er utenfor skjermen. Der lyset ikke
når fram, er det like mørkt som om lyskilden ikke fantes (med **Mykt fyllys** på 0 %, som er standard).

**Sprettlys.** Hver piksel i halv oppløsning følger én sti gjennom dybdebufferen. Hver flate stien
treffer, blir lyst opp der og da av sin egen glød, sola, himmelen og blokklyset, og sender lyset videre
i sin egen farge. En rød vegg kaster altså rødt lys, som et hvitt gulv sender videre. Svake stier
avsluttes tidlig, så mange spratt koster mindre enn det høres ut som.

**Advanced Color Tracing.** Hver lyskilde lyser i fargen fra sin egen tekstur, for eksempel dyp blå
rundt sjelefakler og rødt rundt redstone, og farget glass farger lyset som går gjennom det. Fargen
lagres i voksel-scenen, så den koster nesten ingenting.

**Denoiser.** Lyset samles over tid, omtrent et tredels sekund, og filtreres deretter i to romlige
pass som stopper ved kanter i dybde og normal. De stopper også ved lysforskjeller som er større enn
støyen som er målt i hver piksel, så skyggekanter holder seg skarpe. All støy gjentar seg i korte
sykluser som filteret jevner helt ut, slik at skyggene ikke flimrer når kameraet står stille.

**Begrensninger:**
- Bare det som er på skjermen kan treffes av sprettlyset. Det direkte lyset fra lyskilder virker også
  utenfor skjermen.
- Utenfor voksel-scenen, omtrent 50 blokker bortover og 20 blokker opp eller ned, faller lyset tilbake
  til vanlig blokklys uten skygger.
- Figurer og dyr blir lyst opp, men kaster ikke skygger fra blokklys. Halve blokker som trapper og heller
  demper lyset i stedet for å stoppe det nøyaktig langs formen sin.
- Bare første spratt får skygger fra blokklys. Dypere spratt bruker det vanlige lysnivået, siden de er
  for svake til at skyggene synes.
- De gamle helhetsprofilene (Ultra Fast, Lav, Middels, Høy) er erstattet av ray tracing-profilene.
  Iris har bare én profilliste.

Path tracing-versjonen ligger urørt i `archive/VanillaDeluxe-path-tracing.zip`.

## Røyk og tåke

Menyen **Smoke & Fog** har disse innstillingene:

- **Volumetrisk røyk**: fakler, bål, ild og lava sender opp røyk som stiger, virvler og får gløden
  fra kilden sin. Den erstatter de flate grå røykpartiklene over dem. Røyken bruker listen over
  lyskilder fra voksel-scenen, så den virker også med ray tracing av.
- **Volumetrisk tåke**:
  - Svevende dis i dype huler, som blir tettere jo dypere du er og lyses av fakler og lava rundt den.
  - Tåkebanker som ruller inn med regn, og blir tettere i tordenvær.
  - Tykk tåke i Nether, i fargen til biomet og glødende oransje over lavahavet.
- **Tetthet på huledis**, **Styrke på værtåke** og **Tetthet på Nether-tåke** fra 0 til 300 %.

Alt beregnes i det samme volumetriske passet som solstrålene, i halv oppløsning med filtrering over
tid. Det koster derfor ikke et ekstra pass.

**Begrensninger:**
- Røyken kommer bare fra lyskilder innenfor voksel-scenen, omtrent 50 blokker bortover.
- Iris sier ikke hvilke partikler som er røyk. Grå partikler rett over en røykkilde fjernes, mens
  gnister og flammer blir værende.
- Huledisen vet at du er under jorden ut fra hvor mye himmel du ser, slik spillet selv gjør det.
- Lava-røyken leses rett fra lavablokkene i voksel-scenen. Den er derfor lik fra bilde til bilde, uansett i
  hvilken rekkefølge skjermkortet tegner blokkene.

## Vær

Menyen **Weather & Materials** (også under **Smoke & Fog**) har disse innstillingene:

- **Regn og snø**: regnet er regnet fra 1.9.0: vanilla-stripene, med lysbrytning, vinddrift og lys fra fakler.
  Snøen tegnes av pakken i ekte dybde, 3D Smooth (standard) eller Ultra med flere lag lenger unna.
  Vanilla-plaskene på bakken filtreres bort i partikkelpasset.
- **Vær på glass**: i regn sitter dråper på vinduene og glir sakte nedover, og de bøyer det du ser gjennom
  og i glasset. I snø vokser en smal, ujevn rimkant inn fra rutenes kanter, mer jo kraftigere det snør.
- **Regnplask**: små dråper spretter lavt opp der regnet treffer bakken. Kraftigere regn og storm gir flere
  og høyere dråper.

- **Lysbrytning i regn**: hver regndråpe bøyer bildet bak seg. Dette gjøres i sluttbildet, etter TAA, så
  stripene holder seg skarpe. Dråpene fanger lyset fra sola og månen, og fra fakler i sin egen farge med
  ray tracing.
- **Synlighet på regn**: hvor tydelig regnet synes.
- **Regnringer**: Av, Lav, Middels eller Høy. Regndråper lager ringer i vann, pytter og på våt bakke, og
  ringene synes i refleksjonene.
- **Vinddrift i snø**: hvor hardt vinden blåser og virvler snøen. Snøfnugg lyser opp nær fakler og lava.

Under uvær lener regnet seg i vinden, skydekket lukker seg, sol- og himmellys dempes, og disen og tåken
tetner, mest i tordenvær. Snøvær gir lysere og hvitere tåke enn regn.

**Begrensninger:**
- Vanilla-partiklene for plask beholdes. Ringene ligger i overflaten, ikke som egne partikler.
- Snø og regn skilles ut fra biomet der du står, slik Iris oppgir det.

Under **Utseende** finner du:

- **VanillaDeluxe / Dark Red** (standard), **Naturlig varm** eller **Nøytral**
- **AgX** eller **ACES** som tonemapping
- Menyfanene **Ray Tracing**, **Smoke & Fog**, **Lighting** og **Materials**, med fargekoder
- **Solnedgangsdybde** for hvor røde solnedgangene skal være

## Nytt i 1.11.0

- **Regnet fra 1.9.0 er tilbake.** Vanilla-plaskene på bakken fjernes: Iris kan bare slå dem av sammen med
  selve regnet, så partikkelpasset kjenner dem igjen som blålige partikler rett oppå bakken der det regner.
- **Dybdeskarphet er av som standard**, så bildet er helt skarpt.
- **Tilt-shift / miniatyr** under **Camera Effects**: myk uskarphet øverst og nederst, med et skarpt bånd
  over midten. Både styrke og høyde på båndet kan stilles.
- **Ytelse:**
  - Volumetrikken (tåke, solstråler, skyer og røyk) regnes i et sjakkbrettmønster, halvparten av pikslene per
    bilde, og det temporale filteret fyller inn resten. Den var allerede i halv oppløsning.
  - Sprett etter det første bruker halvparten så mange søketrinn.
  - Linseflaren måles én gang per bilde i stedet for i hver piksel, og smusset på linsen beregnes bare der det
    lyser.
  - Profilene **Av** og **Lav** bruker også lettere skygger, refleksjoner, volumetrikk, POM og bølger, for eldre
    skjermkort. Middels, Høy og Ultra er uendret.

## Nytt i 1.10.0

**Vær bare der det faktisk regner.** Skyggepasset lager et høydekart over den øverste blokken i hver kolonne
innenfor 64 blokker. Alle væreffekter sjekker det: regn, snø, plask, regnringer, våt bakke, pytter og dråper
på glass. Under tak er bakken tørr, også rett innenfor takkanten. Lenger unna enn kartet brukes lysnivået
fra himmelen, som før.

**Kameraeffekter** (menyen **Camera Effects**):
- **Dybdeskarphet** med autofokus på det som er midt på skjermen. Fokuset følger mykt etter, og hånden
  holdes alltid skarp.
- **Linseflare** fra sola og månen, dempet av skyer og terreng foran.
- **Smuss på linsen**, som bare lyser opp rundt sterke lys.

**Dimensjoner** (menyen **Dimensions**):
- **Nether**: kraftigere varmeflimring høyt over lavahavene. Tåken tar farge fra lysene i den, og glowstone
  og ild kaster lysstråler gjennom den. Lysstrålene krever strålesporet blokklys.
- **End**: **Void Aurora**, bølgende gardiner av blått og fiolett lys. **End-krystaller** gløder og sender
  sakte roterende lysstråler ut i mørket.

**PBR og fysikk** (menyen **PBR & Physics**):
- **Dynamiske pytter**: vannet samler seg først i senkninger, der terrenget rundt er høyere, og sprer seg
  til flat mark etter hvert. Etter regnet krymper pyttene igjen, raskere i sol.
- **Subsurface scattering** fantes fra før. Nå har det en egen styrke, og undersiden av løv slipper også
  gjennom litt himmellys, så den holder seg grønn i stedet for grå.

**Begrensninger:**
- End-krystallene finnes via `entity.properties`. Hvis Iris ikke gir dem en ID, gløder de som vanlig, men
  strålene mangler.
- Med eldre Iris som ikke kan slå av vanilla-været, vises det fortsatt ingenting av det, men plaskpartiklene
  kan komme tilbake.
- Høydekartet bygges av det skyggepasset tegner. Blokker utenfor skyggeavstanden mangler i kartet, og der
  faller væreffektene tilbake til lysnivået fra himmelen.

## Funksjoner

**Lys og materialer**
- labPBR og seusPBR: normal, specular, ruhet, metaller, glød, porøsitet og subsurface
- Parallax occlusion mapping med selvskygge
- Innebygde materialer, så vanilla-teksturer får glans, metall og glød uten PBR-pakke
- Omgivelsesskygge med synlighetsbitmaske og strålesporet sprettlys med 1–24 spratt, i halv oppløsning med temporal akkumulering og støystyrt romlig denoiser
- Våte overflater og pytter i regn, og dynamisk håndlys

**Skygger**
- Kontaktherdende skygger: skarpe ved kontakt, mykere med avstanden
- Fargede skygger gjennom glass, kaustikk under vann og lys gjennom løv

**Atmosfære**
- Fysisk basert Rayleigh-, Mie- og ozonspredning, beregnet i en liten himmeltabell hvert bilde
- Solstråler, høydetåke og volumetriske skyer med skyskygger

**Vann og refleksjoner**
- Prosedyrebaserte bølger, Fresnel, lysbrytning og dybdefarge, med valgfritt skum langs land
- Vann lyses bare av lys som faktisk når det, så det er helt mørkt uten lyskilder i nærheten
- Skjermrefleksjoner på vann, glass, metall, polerte og våte flater

**Materialeffekter** (egen meny)
- Lava: pulserende glød med egen glidebryter, glans på smeltede områder og varmeflimring i lufta over
- Is: blank overflate med refleksjoner og lysbrytning. Vanlig is er gjennomsiktig med kald kropp, mens pakket is og blåis bare reflekterer, siden de er massive blokker
- Glass: Fresnel-refleksjoner fra begge sider av ruten og fysisk beregnet lysbrytning, også i de klare delene av vinduer

**Bilde**
- TAA med Catmull-Rom og varianskutting, som også fjerner støy fra de samplede effektene
- AgX og ACES, bloom, svak kromatisk aberrasjon, automatisk eksponering og skotopisk nattsyn

Nether og End har egne lysoppsett. Nether kjører uten skyggepass, som sparer mye GPU-tid.

## Slik er pakken testet

Testene ble kjørt uten Minecraft, med verktøyene i `tools/`:

- **Kompilering:** Alle program, i alle tre dimensjoner, kompileres og lenkes med NVIDIA-driveren
  over alle sett med innstillinger: alle profiler, hvert valg av og på, og ytterverdier.
- **Kjøring:** En testrigg (`tools/harness`) kjører hele pipelinen på en syntetisk verden, med samme
  rekkefølge, buffer-flipping og skyggematriser som i kildekoden til Iris.
- **Statiske sjekker:** `tools/build.py lint` kontrollerer uniforms, menyer, språkfiler og reserverte navn.

**Ikke testet i selve spillet.** Iris sin kodeoversetter (glsl-transformer) kjører ikke i testriggen,
og Minecraft-spesifikk geometri som entiteter og partikler er bare forenklet representert.

Hvis noe feiler i spillet: trykk **Ctrl+D** på Shader Packs-skjermen for å slå på feilsøking, last
pakken på nytt, og se etter feilmeldinger i `logs/latest.log`. Oversatt shaderkode havner da i
mappen `patched_shaders`.

## Utvikling

```bash
python tools/build.py zip
```

```bash
dotnet run --project tools/harness -c Release -- compile
```

```bash
dotnet run --project tools/harness -c Release -- render --scene sunset
```

`tools/build.py` lager program-stubbene i `world0`, `world-1` og `world1` og skriver
`VanillaDeluxe.zip` øverst i prosjektmappen. Selve koden ligger i `shaders/program` og `shaders/lib`, og alle valgene i
`shaders/lib/settings.glsl`. Testriggen bruker kopien av `shaders` som ligger i en overliggende mappe
av programfilen, og kan velge scene med `--scene`: `day`, `sunset`, `dusk`, `night`, `rain`, `pool`,
`shore`, `underwater`, `cave`, `forest`, `pavilion` eller `moving`.

## Kilder

All kode er skrevet for denne pakken. Inspirasjonen til utseendet er Complementary Unbound, men
ingen kode er hentet derfra. Følgende publiserte metoder er brukt:

- Hillaire 2020: atmosfærekoeffisienter
- Therrien mfl. 2023: indirekte lys med synlighetsbitmaske
- Stephen Hill: ACES-tilpasning
- Benjamin Wrensch: AgX-tilpasning
- Jorge Jimenez: interleaved gradient noise og Catmull-Rom-oppslag med fem punkter
