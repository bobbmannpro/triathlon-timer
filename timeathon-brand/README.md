# Timeathon — Brand Package

Drop-in logo, icon, and theme assets for the Timeathon app
(Triathlon Timer · Swim Meet Timer · Bike Route Timer).

## What's in here

```
timeathon-brand/
├── assets/
│   ├── logo-primary.svg          full wordmark + mark (scalable)
│   ├── app-icon.svg              rounded square icon, mark only
│   ├── app-icon-1024.png         1024×1024 (store submission)
│   ├── splash.svg                portrait splash screen
│   └── splash-1290x2796.png      iPhone-res splash
├── icons/
│   ├── favicon.svg               modern SVG favicon
│   ├── favicon.ico               legacy multi-size (16/32/48)
│   ├── favicon-16.png
│   ├── favicon-32.png
│   ├── apple-touch-icon.png      180×180
│   ├── icon-192.png              PWA
│   ├── icon-512.png              PWA
│   └── site.webmanifest          PWA manifest
├── css/
│   └── theme.css                 CSS variables: colors, type, buttons, clock, chips
├── HEAD-SNIPPET.html             paste-in <head> block for favicons + theme
├── preview.html                  open in a browser to see everything wired up
└── README.md
```

## Quick start (VS Code)

1. Copy the whole `timeathon-brand/` folder into your project
   (e.g. into `public/` for a Vite/React app, or the repo root for a static site).
2. Open `preview.html` in a browser (Live Server extension, or just drag it in)
   to confirm the assets render.
3. Paste the contents of `HEAD-SNIPPET.html` into your app's `<head>`,
   fixing the paths to match where you put the folder.
4. Start using the theme variables — see below.

## Using the theme

`css/theme.css` exposes everything as CSS custom properties under `:root`.
Reference them anywhere:

```css
.timer-display { color: var(--tm-live); font-family: var(--tm-font-mono); }
.go-button     { background: var(--tm-accent-grad); }
```

Ready-made classes you can use directly:
- `.tm-clock`        — the big running clock (mono, tabular numerals, glow)
- `.tm-btn-primary`  — gradient primary button
- `.tm-chip[data-active]` — mode selector chips (Triathlon / Swim Meet / Bike Route)
- `.tm-lane`         — lane-line hairline divider (signature motif)

Discipline colors for the three legs / modes:
`--tm-swim (#00C6FF)`, `--tm-bike (#00E5CC)`, `--tm-run (#7DF9C4)`.

## Fonts

The theme references **Archivo** (display), **Inter** (body), and
**JetBrains Mono** (the clock). Add this to your `<head>`, or swap for your own:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Archivo:wght@700;900&family=Inter:wght@400;600;800&family=JetBrains+Mono:wght@700&display=swap" rel="stylesheet">
```

## React / JSX note

To use the logo in a component, either import the SVG directly:

```jsx
import logo from './timeathon-brand/assets/logo-primary.svg';
<img src={logo} alt="Timeathon" />
```

or import the stylesheet once at your app root:

```jsx
import './timeathon-brand/css/theme.css';
```

## Colors at a glance

| Token | Hex | Use |
|-------|-----|-----|
| Navy base | `#0A1628` | app background |
| Raised | `#0D2240` | cards / panels |
| Cyan | `#00C6FF` | accent / swim |
| Teal | `#00E5CC` | accent / bike / live |
| Run green | `#7DF9C4` | run leg |
| Gold/Silver/Bronze | `#FFCB45` / `#C7D4E0` / `#D98A4B` | results |
