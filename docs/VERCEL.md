# Vercel-deploy (Plotspotting web)

## Projekt

- **GitHub:** https://github.com/NikolajHygebjerg/plotspotting
- **Production:** https://plotspotting.vercel.app
- **Konfig:** `vercel.json` i repo-roden (Vercel Root Directory = `.` / tom)

> **Vigtigt:** Hvis `plotspotting.vercel.app` viser «To get started, send a prompt…» er projektet stadig det gamle **v0/Next.js**-projekt — ikke Flutter-appen fra GitHub. Se fejlsøgning nedenfor.

## Første gangs opsætning i Vercel

1. Gå til [vercel.com/new](https://vercel.com/new) → **Import** `NikolajHygebjerg/plotspotting`
2. **Framework Preset:** Other
3. **Root Directory:** lad stå tom (repo-roden) — `vercel.json` ligger i roden
4. **Environment Variables** (Production + Preview):

| Variabel | Værdi |
|----------|--------|
| `SUPABASE_URL` | `https://gjbtmmmhplhqpbaqzsqj.supabase.co` |
| `SUPABASE_ANON_KEY` | Supabase → Settings → API → anon key |
| `PUBLIC_WEB_BASE_URL` | `https://plotspotting.vercel.app` |

5. Klik **Deploy** og vent 5–15 min (Flutter downloades første gang)

## Eksisterende v0-projekt?

Hvis du allerede har et «plotspotting»-projekt fra v0:

1. Vercel → **plotspotting** → **Settings** → **Git**
2. **Connect Git Repository** → vælg `NikolajHygebjerg/plotspotting`
3. Fjern eventuel **Root Directory** override (skal være tom)
4. **Deployments** → **Redeploy** på seneste commit

Alternativt: slet v0-projektet og importér GitHub-repoet på ny.

## Tjek at deploy virker

Build-log skal vise:

```
Installing Flutter SDK...
flutter build web --release
✓ Built build/web
```

Live test:

```
https://plotspotting.vercel.app/e/friland?embed=1
```

Forventet: Plotspotting splash / kort — **ikke** «To get started, send a prompt».

## Fejlsøgning: «Vercel har ikke deployet»

| Symptom | Løsning |
|---------|---------|
| Ingen nye deployments efter git push | Git ikke forbundet — Settings → Git → Connect |
| Build fejler med `flutter: not found` | Root Directory skal være tom (repo-root), ikke `app` alene uden root `vercel.json` |
| Siden viser v0-placeholder | Forkert projekt/kilde — forbind GitHub-repoet |
| Build fejler mangle env | Tilføj `SUPABASE_URL` + `SUPABASE_ANON_KEY` |
| Vercel login på preview | Slå Deployment Protection fra for Production |

## Miljøvariabler

Build-scriptet (`app/scripts/vercel-build.sh`) skriver `assets/env.json` og bygger Flutter web.

## Publicerede kort

```
https://plotspotting.vercel.app/e/{slug}
https://plotspotting.vercel.app/e/{slug}?embed=1
https://plotspotting.vercel.app/e/{slug}/jagt/{jagt-slug}?embed=1
```

## Iframe

```html
<iframe
  src="https://plotspotting.vercel.app/e/friland?embed=1"
  width="100%"
  height="600"
  style="border:0;"
  allow="geolocation"
  loading="lazy"
  title="Plotspotting kort">
</iframe>
```

## Deployment Protection

Hvis preview-URL’er viser Vercel-login, slå **Deployment Protection** fra for Production under Vercel → Project → Settings → Deployment Protection — ellers kan besøgende ikke åbne kortene.

## Custom domain

Tilføj `plotspotting.dk` som domain alias og sæt `PUBLIC_WEB_BASE_URL=https://plotspotting.dk`.
