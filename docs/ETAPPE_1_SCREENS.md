# Etape 1 — Skærm-specifikation (Udendørs MVP)

Målgruppe: **spejderlejr** — GPS, OSM-baggrund, arrangør tegner stier, besøgende søger og navigerer.

---

## Skærmflow

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│  1. Home    │────▶│ 2. Opret     │────▶│ 3. Kort-editor  │
│             │     │    event     │     │    (mapper)     │
└──────┬──────┘     └──────────────┘     └────────┬────────┘
       │                                           │
       │              ┌──────────────┐             │
       └─────────────▶│ 6. Besøger   │◀────────────┤
                      │    kort      │   publicér  │
                      └──────┬───────┘             │
                             │                     ▼
                      ┌──────┴───────┐     ┌─────────────────┐
                      │ 5. Navigation│◀────│ 4. Publicér &   │
                      │    (rute)    │     │    del          │
                      └──────────────┘     └─────────────────┘
```

Besøgende springer 1–5 over og lander direkte på **6** via QR/link.

---

## Skærm 1 — Home

**Formål:** Indgang til appen for arrangører.

| Element | Adfærd |
|---------|--------|
| "Opret nyt event" | → Skærm 2 |
| "Rediger eksisterende" | Indtast edit-kode → Skærm 3 |
| "Åbn event som besøgende" | Indtast slug / scan QR → Skærm 6 |
| Seneste events (lokal cache) | Hurtig genåbning |

**Tom tilstand:** Kun de tre primære knapper.

---

## Skærm 2 — Opret event

**Formål:** Minimal opsætning.

| Felt | Validering |
|------|------------|
| Event-navn | Påkrævet, max 80 tegn |
| Beskrivelse | Valgfri |
| Type | Låst til "Udendørs" i Etape 1 |

**Handlinger:**
- "Opret og tegn kort" → opretter draft i Supabase, viser edit-kode **én gang**, → Skærm 3
- Edit-kode vises i callout: "Gem denne kode — den vises ikke igen"

**Kort-center:** Kortet centreres på brugerens GPS ved første åbning af editor.

---

## Skærm 3 — Kort-editor (mapper)

**Formål:** Kernen — tegn stier og placér POI'er på OSM-baggrund.

### Kortlag
- MapLibre + OSM tiles
- Stier (edges) som blå linjer
- Vertices som små prikker ved knudepunkter
- POI'er som kategorikoner

### Toolbar (bund)

| Værktøj | Adfærd |
|---------|--------|
| **Tegn sti** | Tap = ny vertex; snap til eksisterende inden for 5 m; "Afslut" stopper segment |
| **Tilføj sted** | Tap på kort → bottom sheet (Skærm 3b) |
| **Vælg / rediger** | Tap vertex/POI → flyt eller slet |
| **Fortryd** | Fjerner sidste vertex/ handling |

### Topbar
- Event-navn
- "Gem" (sync til Supabase)
- "Publicér" → Skærm 4
- Antal stier / POI'er som status

### Gestures
- Pan / zoom kort (standard)
- Long-press på POI → rediger

---

## Skærm 3b — Tilføj / rediger POI (bottom sheet)

| Felt | |
|------|--|
| Navn | Påkrævet |
| Kategori | Picker: aktivitet, mad, toilet, info, andet |
| Beskrivelse | Valgfri |

**Handlinger:** Gem / Annuller / Slet (ved redigering)

Ved gem: beregn `access_vertex_id` (snap til nærmeste sti).

---

## Skærm 4 — Publicér & del

**Formål:** Gør kortet tilgængeligt for besøgende.

### Pre-flight checklist
- [ ] Mindst én sti tegnet
- [ ] Mindst ét POI (valgfri advarsel)
- [ ] Kort gemt

| Element | |
|---------|-----|
| Preview | Mini-kort med stier + POI |
| Public URL | `https://app…/e/{slug}` |
| QR-kode | Til print på infobod |
| Edit-kode | Påmindelse om at gemme |

**"Publicér"** → `status = published`, slug genereres fra navn.

---

## Skærm 5 — Navigation (rute)

**Formål:** Vis gå-rute fra brugerens position til valgt POI.

| Element | |
|---------|-----|
| Kort | OSM + highlightet rute (accent farve) |
| Start | GPS-position (blå prik), snapped til sti |
| Mål | POI-markør |
| Info-bar | "{distance} m · ca. {minutes} min gang" |
| Instruktioner (valgfri Etape 1) | "Gå mod syd langs hovedstien" — kan udelades i MVP |
| "Afslut navigation" | Tilbage til Skærm 6 |

GPS opdateres hvert 3–5 sek → re-snap + re-route hvis afvigelse > 15 m.

---

## Skærm 6 — Besøger-kort

**Formål:** Søg og find — primær skærm for deltagere.

**Adgang:** Deep link `/e/{slug}` eller QR.

| Element | Adfærd |
|---------|--------|
| Søgefelt | Filtrer POI'er på navn (client-side) |
| Kategori-chips | Hurtigfilter: toilet, mad, … |
| POI-liste | Scrollbar under kort (half-sheet) |
| Kort | Stier + POI'er, bruger-position |
| Tap POI | Marker på kort + "Vis rute" → Skærm 5 |

**Offline:** Hvis event tidligere hentet, vis cached graf (Etape 4 — i MVP: kræv net ved første load).

---

## MVP-afgrænsning (bevidst udeladt)

- Walk & trace (Etape 3)
- Indendørs plantegning (Etape 2)
- Offline-download (Etape 4)
- Flere samtidige editorer
- Brugerkonti / login (edit-kode er nok)
- Push-notifikationer

---

## Acceptkriterier (Etape 1 færdig)

1. Arrangør kan oprette event, tegne stier og tilføje ≥10 POI'er
2. Publicering giver fungerende QR/link
3. Besøgende kan søge POI og få rute langs **kun** tegnede stier
4. Rute afviger ikke til OSM-veje uden for lejren
5. Hele flow testet på rigtig lejrplads med dårlig/forstyrret GPS
