# Illustrated kort med Gemini

Du kan lave et vandfarve-lignende kort **uden Google Maps API** — præcis som du allerede har testet med Gemini.

## Workflow (Friland-eksempel)

### 1. Tag screenshot af området

- Åbn området i Google Maps, Apple Maps eller OpenStreetMap
- Zoom så hele området (fx Friland) er synligt
- Tag et **screenshot** (samme udsnit som du vil vise gæster)

### 2. Generér tegning i Gemini

Upload screenshotet til [Gemini](https://gemini.google.com) med en prompt som:

```
Tegn dette kort som et smukt håndtegnet vandfarve-kort set oppefra.
Behold præcis samme layout, vejforløb, bygninger, skov og vand.
Stil: blød akvarel, håndskrevne vejnavne, grønne marker, varme jordfarver.
Ingen satellitfoto-look — kun illustration.
Format: samme proportioner som input-billedet.
```

Gem det genererede billede på telefonen (PNG/JPG).

### 3. Vælg område i appen

1. Åbn event i kort-editoren
2. Menu (⋮) → **Vælg kortområde**
3. Zoom kortet så det matcher **samme udsnit** som dit Gemini-billede
4. Tryk **Gem synligt område**

### 4. Upload illustrated kort

1. Menu → **Upload illustrated kort (Gemini)**
2. Vælg billedet fra dit fotobibliotek
3. Appen georefererer det til det gemte område

### 5. Map stier og steder

- **Start mapping** → gå stierne fysisk
- **Tilføj sted** undervejs
- Stier og pins ligger **ovenpå** dit illustrated kort

### 6. Publicér

Besøgende ser dit illustrated kort + søgning + navigation.

---

## Tips til god georeferering

| Problem | Løsning |
|---------|---------|
| Stier passer ikke | Screenshot og «Gem synligt område» skal have **samme zoom** |
| Billede er forskudt | Justér zoom i trin 3 og upload igen |
| Gemini ændrer layout | Bed den om «behold præcis samme forhold og placering af alle elementer» |
| For mange detaljer | Bed om simplificeret stil — detaljer kommer fra jeres POI'er |

---

## Teknisk

- Billedet gemmes i Supabase Storage (`event-basemaps/{eventId}/basemap.png`)
- `events.bounds` bruges til georeferering (4 hjørner)
- MapLibre viser billedet som lag under stier og pins

---

## Fremtid: auto-generering i appen

Senere kan appen selv:
1. Gemme område + tage kort-snapshot
2. Sende til Gemini API
3. Vise resultat til godkendelse før upload

Det kræver `GEMINI_API_KEY` og er ikke nødvendigt for at komme i gang — manuel Gemini + upload virker allerede.
