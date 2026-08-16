# Vercel-deploy (Plotspotting web)

## Projekt

- **Root directory:** `app`
- **Production:** https://plotspotting.vercel.app
- **Preview:** `https://plotspotting-*.vercel.app` (kan kræve Vercel-login hvis Deployment Protection er slået til)

## Miljøvariabler (Vercel → Settings → Environment Variables)

| Variabel | Eksempel |
|----------|----------|
| `SUPABASE_URL` | `https://….supabase.co` |
| `SUPABASE_ANON_KEY` | Supabase anon key |
| `PUBLIC_WEB_BASE_URL` | `https://plotspotting.vercel.app` (skift til `https://plotspotting.dk` når domænet peger hertil) |

Build-scriptet (`scripts/vercel-build.sh`) skriver `assets/env.json` og bygger Flutter web.

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
