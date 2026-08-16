# Friland — opsætning og brug

Friland er det perfekte testcase: veje uden officielle numre i Google, huse spredt langs stier, og gæster der skal finde **husnummer eller beboer** — ikke en vejadresse Google forstår.

Referenceområde på Google Maps: [Friland på Google Maps](https://maps.app.goo.gl/ddeJr98bqsHZGEyF7)

**Vores løsning:** I tegner de rigtige gangstier og placerer hvert hus. Gæster søger på navn eller nummer og får rute **langs jeres stier** — ikke Googles bil-navigation.

---

## 1. Opret Friland-kortet

1. Kør migrationer (inkl. `004_poi_metadata.sql`)
2. Åbn appen → **Opret nyt event**
3. Navn: `Friland`
4. Appen sætter GPS-center automatisk hvis du er on-site; ellers bruges ca. `56.3612, 10.5274`
5. Gem edit-koden et sikkert sted

Ved publicering: brug slug **`friland`** (genereres automatisk fra navnet).

---

## 2. Map stier (det Google ikke kan)

Gå/stå ved skærmen og tegn **alle gangbare stier** i området:

| Trinn | Handling |
|-------|----------|
| 1 | Vælg **Tegn sti** |
| 2 | Tap langs hver sti (Friland, Jeshøjvej-indkørsel, stier mellem huse osv.) |
| 3 | **Afslut sti** ved forgreninger, start nyt segment |
| 4 | Sørg for stier mødes i kryds (snap inden for 5 m) |

**Tip:** Start med hovedstierne, derefter sidegrene til huse. Ruten må kun gå hvor gæster faktisk må gå.

Markér evt. **indgange** som POI med kategori `info` ved hovedindkørsel.

---

## 3. Tilføj huse (nummer + beboer)

1. Vælg **Tilføj sted**
2. Tap på husets placering på kortet
3. Udfyld:

| Felt | Eksempel |
|------|----------|
| Navn | `Hytten` (valgfrit kaldenavn) |
| Husnummer | `12` |
| Beboer | `Anna Jensen` |
| Kategori | **home** (Bolig) |

Gentag for alle huse. Søgning virker på **nummer, beboernavn og husnavn**.

Til fælles steder (toilet, køkken, info):

| Sted | Kategori |
|------|----------|
| Fælleshus / køkken | `food` eller `info` |
| Toilet | `toilet` |
| Infobod | `info` |

---

## 4. Publicér

1. **Gem** kortet
2. **Publicér** → du får link og QR-kode  
   Eksempel: `https://plotspotting.vercel.app/e/friland`

---

## 5. Gæster på telefon

Gæster åbner appen → **Åbn som besøgende** → slug `friland`

Eller scan QR-koden ved infobod.

Søg fx:

- `12` → finder hus nr. 12
- `Anna` → finder beboer
- `Hytten` → finder kaldenavn

Tryk **Vis rute** → gå-rute langs **jeres** stier med GPS.

---

## 6. Guide på hjemmesiden

En simpel landingsside ligger i `website/friland/index.html`.

På friland.dk kan I embedde et søgefelt der sender gæster til appen:

```
https://plotspotting.vercel.app/e/friland?search=12
```

Indtil appen er udgivet i App Store, kan I:

1. Linke til TestFlight / APK
2. Vise QR-kode til det publicerede kort
3. Bruge landingssiden som instruktion + download-link

**Deep link i appen:** Åbn med slug `friland` og forudfyldt søgning via query-parameter (understøttet i appen).

---

## Hvorfor det er bedre end Google Maps

| Google Maps | Event Map (Friland) |
|-------------|---------------------|
| Vejnavigation til adresser | Gangruter på stier |
| Kendte vejnavne | Jeres egne stier |
| Husnumre matcher ikke altid | I placerer præcist |
| Guider forkert ind | Rute kun langs mappede stier |

---

## Anbefalet rækkefølge (ca. 2–3 timer)

1. Hovedstier (30 min)
2. Sidegrene til huse (30 min)
3. Alle huse med nummer + beboer (60 min)
4. Test med 2 gæster på pladsen (30 min)
5. Publicér + QR på hjemmeside

---

## Koordinater (reference)

Centrum af Friland-området (til kort-start):

- **Lat:** 56.3612
- **Lng:** 10.5274

Justér ved at zoome ind på [Google Maps-området](https://maps.app.goo.gl/ddeJr98bqsHZGEyF7) og sammenligne med OSM-baggrunden i editoren.
