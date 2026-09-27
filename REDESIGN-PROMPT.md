# Timeathon — full redesign brief

Paste everything below the line into Claude Code / Copilot in VS Code, with this
repo open. It is deliberately self-contained: the agent cannot see any mockup, so
every colour, font and size it needs is written out here.

---

You are redesigning an existing, working web app. Read this whole brief before you
change a single line.

## The codebase

- One file: `index.html`, ~12,700 lines, ~870 KB. That is the entire app.
- React 18 + Babel Standalone compiled **in the browser**. There is no build step,
  no bundler, no npm. Ship-ready = the file loads and runs.
- Firebase (auth + Realtime Database + storage), Leaflet for maps, Web Bluetooth
  for Garmin/Wahoo sensors.
- Deployed as GitHub Pages at timeathon.com.
- All styling today is **inline `style={{}}` objects** plus one `<style>` block in
  `<head>` holding CSS custom properties (`--tm-*`) and a few classes
  (`.tm-nav`, `.tm-nav-btn`, `.tri-wp-panel`, `.tri-setup-grid`, `.tm-clock`).

## The single most important rule

**Do not break working functionality.** This app times real races for real kids.
Everything below must still work when you are done:

Firebase email/password auth · race publishing and the live spectator feed ·
6-character race codes · athlete self-registration · GPS waypoint auto-splits ·
bike distance measurement and lap counting · Leaflet maps, course drawing and the
printable course export · Garmin watch pairing and Wahoo/BLE sensors · CSV import ·
certificate generation and printing (including the base64 logo path) · localStorage
persistence · the swim meet lane timer · the bike live feed with speed-coloured
trails and BRouter snapping.

If a redesign choice would require changing timing, GPS or Firebase logic — don't.
Restyle the presentation and leave the logic alone.

## What this redesign is

Two things at once:

1. **A new look** — "Sunlight". Specified exactly below.
2. **A new structure** — role-first navigation. Specified exactly below.

Both apply to **the entire app**: the Triathlon Timer, the Swim Meet Timer, AND the
Bike Live Feed, plus login, profile, join, watch, devices, manual entry, archive,
the athlete library and race photos. Not one sub-app. All of them. Every screen
ends up on the same tokens, the same components, the same spacing.

---

# PART 1 — The "Sunlight" design system

This app is used **outdoors, in direct sun**, on phones. That is the governing
constraint and it is why the palette looks the way it does. In glare, a dark screen
reflects ambient light into a grey wash and loses most of its contrast, thin strokes
bloom and vanish, and pale grey text disappears. So: bright ground, near-black text,
heavy weights, big type, thick borders. Do not "tastefully" soften any of this.

## Colour tokens

Replace the existing `--tm-*` custom properties with these. Keep them as CSS custom
properties in the `<head>` `<style>` block, and add a matching plain JS object so
inline styles can reference them by name instead of hardcoding hex.

```
--tm-bg           #FFFFFF   page ground — maximum reflectance, do not tint
--tm-bg-alt       #EFEDE8   section bands, inset panels, input wells
--tm-ink          #0B0D10   all primary text, 19:1 on white
--tm-ink-muted    #3D434B   secondary text ONLY — 10:1 on white. Never lighter.
--tm-line         #C9C5BC   borders. Always 2px or 3px. Never 1px hairlines.

--tm-swim         #0B3FCC   cobalt        (white text on it = 8.0:1)
--tm-bike         #B44A00   deep orange   (white text on it = 5.4:1)
--tm-run          #04613F   deep green    (white text on it = 7.8:1)
--tm-live         #B3001B   deep red — LIVE badges, recording, alerts
--tm-warn         #8A5A00   amber-brown for warnings (white text = 5.6:1)
```

Rules:

- White text goes on `--tm-swim`, `--tm-bike`, `--tm-run`, `--tm-live`, `--tm-warn`
  and `--tm-ink` only. Never on `--tm-bg-alt` or `--tm-line`.
- Dark text (`--tm-ink`) goes on `--tm-bg` and `--tm-bg-alt` only.
- Every discipline colour must also be distinguishable by **position or label**, not
  colour alone — some athletes' parents are colourblind and everyone is squinting.
- Delete the old navy/cyan palette entirely. No `#0A1628`, `#0D2240`, `#113052`,
  `#00C6FF`, `#00E5CC`, `#8FB0CC`, `#4E6B85` should survive anywhere in the file.
  Grep for them and make sure the count is zero.

## Type

One family: **Archivo**, weights 500/600/700/800/900. Replace the current Google
Fonts link with:

```html
<link href="https://fonts.googleapis.com/css2?family=Archivo:wght@500;600;700;800;900&display=swap" rel="stylesheet">
```

Drop Inter and JetBrains Mono entirely.

```
Display / page titles   Archivo 900, UPPERCASE, letter-spacing -1.2px
                        42–50px phone. line-height 0.92.
Section headings        Archivo 800, UPPERCASE, letter-spacing 0.4px, 20–27px
Body                    Archivo 500 or 600, 16px. NEVER below 14px anywhere.
Secondary / captions    Archivo 600, 14px, colour --tm-ink-muted
Labels above fields     Archivo 800, UPPERCASE, 14px, letter-spacing 1.2px
Big numerals (clocks,   Archivo 900, letter-spacing -2.6px,
splits, leaderboard)    font-variant-numeric: tabular-nums   ← required, so
                        digits don't jitter as the clock ticks
```

There is no 11px, 12px or 13px text in the finished app. Audit for it.

## Components

- **Buttons** — min-height 56px primary / 46px secondary. Archivo 800, 17px.
  Square or 6px radius. Primary: `--tm-ink` background, white text. Secondary:
  transparent with a **3px** `--tm-ink` border. On a coloured block: white
  background with the block's colour as the text.
- **Inputs** — white background, 6px radius, no border when sitting on a coloured
  block; 2px `--tm-line` border when on white. Archivo 800, 28px for numbers,
  16px for text. Min-height 46px. Every input keeps a real `<label>`.
- **Toggles / segmented controls** — the selected option is a solid fill with
  reversed text; the unselected one is a 2px outline. No subtle tints.
- **Cards / rows** — 2px `--tm-line` border. Where a row has a status, carry it as
  an **8px left border** in the discipline colour, not a background tint.
- **Progress bar (wizard)** — 5 equal segments, 8px tall, no gaps between fills:
  `--tm-swim` when done, `--tm-line` when not.
- **Full-bleed colour blocks** — the primary navigation device. Edge to edge, no
  side margin, stacked with no gap between them.
- Touch targets ≥46px everywhere. This is used with wet hands.

---

# PART 2 — The new structure

## The flow

```
Login  →  "Pick your lane"  →  the app for that role
```

### Role selection

After login, if the user has no saved role, show a full-screen role picker:
three **full-bleed colour blocks**, in this order:

| Block | Colour | Title | Subtitle |
|---|---|---|---|
| 1 | `--tm-swim` | HOST | I'm running the race |
| 2 | `--tm-bike` | ATHLETE | I'm racing today |
| 3 | `--tm-run` | SPECTATOR | Watching — no account needed |

Each block: 22px/24px padding, an inline stroke SVG icon at 28px on the left,
title Archivo 900 27px uppercase, subtitle Archivo 600 15px, a right-pointing
arrow icon. Whole block is one `<a>`/`<button>` — the entire block is the target.

The chosen role is **remembered** (localStorage + the user's Firebase profile) and
the app goes straight there on every later login. A "Switch role" control lives in
the header and in Profile. It must always be reachable — never trap someone.

### Spectators do not need an account

This is a real change to the auth gate, not just styling. A spectator must be able
to land on the site, tap SPECTATOR, type a 6-character race code, and watch — with
no signup, no email, no password. Use Firebase anonymous auth behind the scenes if
the database rules need a user; do not show them an account screen. Signing up stays
available but is never required to watch.

### The timer type moves

Today the app asks everyone to choose Triathlon / Swim Meet / Bike Live Feed before
anything else. **Delete that as a top-level screen.** A race code already encodes
which kind of race it is, so athletes and spectators must never be asked.

It becomes a question **only the host answers, only when creating a new race** —
step 1 of the wizard: "What kind of race?" → Triathlon / Swim Meet / Bike Ride.

### Each role gets a different app

**Host** — the full app. Bottom or top nav with: My Races · Setup · Race · Results ·
Athletes. Lands on "My Races": a `+ NEW RACE` block, then saved races, then finished
races.

**Athlete** — three screens only. Enter a code (or tap a race already joined) → my
race screen (my elapsed time, my leg, my GPS, my position) → my results. No nav bar
with six tabs; a back arrow is enough.

**Spectator** — two screens. Enter a code → watch live. That is the entire app. No
nav bar at all.

Do not give athletes or spectators host-only tabs. Do not show "Setup", "Devices" or
"Manual Entry" to anyone who is not a host.

### The host setup wizard

Replace the current single long Setup screen with 5 numbered steps, Back/Next at the
bottom, the 5-segment progress bar at the top, and `STEP n OF 5` in Archivo 800
uppercase `--tm-swim` above the title:

1. **What kind of race?** — Triathlon / Swim Meet / Bike Ride, plus race name
2. **Who's racing?** — roster, add athlete, import CSV, open self-registration
3. **How far is each leg?** — distances + unit toggles, on full-bleed discipline
   colour blocks (swim cobalt, bike orange, run green)
4. **Age groups & certificate** — groups, event name, organisation, logo
5. **Course map** — optional GPS waypoints and drawn course; clearly skippable

Then a single full-width `GO TO RACE →`.

Keep a "jump to any step" affordance so an experienced host isn't forced through all
five to fix one number. Editing an existing race should land on a step list, not
step 1.

The swim meet and bike ride flows get the **same** 5-step wizard shape with their own
step content. Do not leave them on the old layout.

---

# PART 3 — How to do it without breaking the app

Work in **phases**. After every phase, load the page and confirm it still renders and
the console has no new errors. The only pre-existing console message is a Babel note
about the script exceeding 500KB — that one is expected and harmless.

Commit after each phase so any breakage is bisectable.

- **Phase 1 — tokens.** Swap the `<head>` custom properties and the font link. Add
  the shared JS style object. Do not touch layout yet. App must still work, just
  look half-changed.
- **Phase 2 — shell.** Header, nav, buttons, inputs, cards. Every screen inherits it.
- **Phase 3 — role gate.** Role picker, remembered role, spectator anonymous auth,
  per-role navigation. Remove the old timer-type picker screen.
- **Phase 4 — host wizard.** Split Setup into the 5 steps. Triathlon first.
- **Phase 5 — swim meet.** Same tokens, same components, same wizard shape.
- **Phase 6 — bike live feed.** Same again.
- **Phase 7 — the rest.** Join, watch, devices, profile, manual entry, archive,
  athlete library, race photos, certificates. Nothing left on the old palette.

## Definition of done

- Grep the file for every old hex listed above — zero hits.
- Grep for `fontSize: 1[0-3]` and similar — no text under 14px.
- Every one of these renders on the new system: login · role picker · host My Races ·
  wizard steps 1–5 · race screen · results · certificate · join · watch · devices ·
  profile · manual entry · archive · athlete library · photos · swim meet home,
  setup, race, results, lane, watch, archive · bike rides, riders, setup, ride, feed.
- A spectator can watch a race having never created an account.
- An athlete never sees a host-only screen.
- Timing, GPS, Firebase, Bluetooth, CSV and certificates all still work.
- The page still loads with no build step, straight from `file://` or GitHub Pages.

If you hit something where the redesign and the working code genuinely conflict,
**stop and ask** rather than guessing. Losing a feature is worse than an inconsistent
screen.

## Note on the current working tree

`index.html` has uncommitted changes from an earlier pass: a collapsible Setup
screen, clearer button labels, de-duplicated Home cards, a reworked nav. The
**labels and de-duplication are good — keep that thinking.** The collapsible Setup
is superseded by the wizard in Part 2; replace it.
