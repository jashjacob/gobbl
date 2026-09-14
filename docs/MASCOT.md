# Gob — character brief and production pipeline

Gob is the pet that lives in Gobbl's notch. Today it is drawn procedurally
(`Gobbl/Pet/GobView.swift`); this brief is for replacing that stand-in with
production art, animated in **Rive** as one state machine. Every call site
already passes a `Mood`, a species colour, a hat, and look/anticipation
inputs, so the renderer can be swapped without touching the rest of the app.

## The character

Gob is a **little computer with a face on its screen** — the original blob was
retired on 2026-09-14. Three eras (`PetCharacter`): **Classic** (late-70s
keyboard base with a boxy monitor), **Compact** (mid-80s all-in-one with a
floppy slot) and **Candy** (late-90s rounded, candy-coloured shell with a CD
slot). The face is glowing lime phosphor: pixel eyes, blush, a small mouth.
It eats files through its slot. No arms (reactions are squash, bounce and
face). Friendly, a bit greedy, never scary. It must read at **24 pt** (the
collapsed notch) and look great at **84–230 pt**. Agent states: **thinking**
= eyes up, eyebrow raised, "…" bubble; **coding** = Matrix rain fills the
screen with eyes squinting through; **typing** = a hop per key, keycaps pop off.

### Second character: Retro

`PetCharacter.retro` is a little 80s desktop computer: a pastel case tinted by
species, a recessed CRT with a glowing lime pixel face (same moods), vents,
a floppy slot it eats files through (a disk slides in while it's eating), a
drive light that blinks while it's busy, and two small feet. Users pick
a model after unboxing (first run: a shipping box opens and the screen powers on), in Settings, or from Gob's right-click menu.

**Keep it generic, not Apple's.** The 1984 Macintosh's shape, the "Happy Mac"
face and the handwritten "hello" are Apple trade dress and trademarks. Never
add an Apple logo, rainbow stripes, the Happy Mac face or "hello" script, and
never market it as "the Mac Steve Jobs introduced". When this goes to an
artist, push it further from the Macintosh 128K silhouette (for example a
chunkier case, a keyboard wedge in front, or a side-mounted disk drive).

## States (Rive state machine)

One state per `Mood` case in `Packages/GobblCore/Sources/GobblCore/Mascot/MascotBrain.swift`:

| Mood | What it looks like | Loop? |
|---|---|---|
| `idle` | Slow breathing, a blink every ~4 s | loop, **must settle** between blinks |
| `curious` | Eyes wide, follow the pointer (`lookX`) | loop |
| `eating` | Mouth chomps open/shut, cheeks puff | 1.2 s one-shot |
| `burping` | Small "o" mouth, bubbles | 0.9 s one-shot |
| `happy` | ^ ^ eyes, wide smile, little bounce | 1.5 s |
| `love` | ^ ^ eyes, floating hearts | 1.6 s |
| `dancing` | Side-to-side sway and bob, notes | loop |
| `sleepy` | Heavy lids, drooping antenna | loop |
| `sleeping` | Closed eyes, slow breathing, "z" | loop, near-static |
| `alert` | Wide eyes, jitter, "!" (agent needs you, meeting soon) | 3–6 s |
| `celebrating` | Jump, confetti (level up, agent done) | 2.5 s |
| `dizzy` | Spiral/X eyes, wobble (mouse shake) | 2 s |
| `working` | Eyes down, antenna glowing/spinning, typing dots (AI agent busy) | loop |
| `sweaty` | Worried wobbly mouth, sweat drop (CPU pegged) | loop |
| anticipating (bool) | Stretched tall, mouth wide open (file dragged over) | hold |

### Inputs

- `mood` — number or enum matching the table
- `lookX`, `lookY` — −1…1, pupils follow the pointer
- `anticipating` — bool
- `stage` — 0 baby, 1 teen (glowing bobble), 2 grown-up
- Species colours via **data binding** (one view model): `bodyTop`, `bodyBottom`,
  `antenna`, `cheeks`; `shiny` bool turns on a sparkle layer. The 8 species are
  in `PetGenome.swift` (hues: Mochi pink, Sprout green, Ember orange, Frost
  blue, Bubble teal, Sunny yellow, Plum purple, Cosmo indigo).
- `hat` — enum selecting a Component inside a Solo: party, bow, beanie,
  headphones, sunglasses, halo, crown, flower, pumpkin, diya, santa (`Wardrobe.swift`).

### Performance rules

- The collapsed notch shows Gob **all day**: idle must let the state machine
  *settle* between blinks (Gobbl drives blinks on a timer if needed). Target
  ~0% CPU at rest; profile with Instruments before shipping.
- Keep the file small (< 150 KB); no raster images inside.
- Keep a static fallback frame for 24 pt / Reduce Motion.

## Pipeline (researched Sept 2026)

1. **Concept — ~1 week, ~$20–40.** Nano Banana Pro (Gemini 3 Pro Image) holds
   a character across poses best (up to 14 reference images). Produce a
   turnaround, an expression sheet with all states above, and the 8 colour
   studies. Midjourney V8 is fine for moodboards but drifts on model sheets.
2. **Vector master — ~1 week.** Optional first pass in Recraft V4 Vector (use a
   paid plan: free-plan output isn't yours to use commercially), then **redraw
   by hand** in Rive/Figma with separate named layers (body, eyes, lids,
   pupils, glints, mouth, cheeks, antenna). Hand-made final art also keeps the
   mascot copyrightable (purely AI output isn't, in the US).
3. **Rig + state machine — 3–6 weeks.** Either hire (Rive Experts directory,
   Contra's Rive network; e.g. one studio lists $250 for 2 states + $100 per
   extra state, so ~$1.5–3k for this scope) or build in-house on Rive Cadet
   ($9/mo) using Rive's AI coding agent for scripts like pointer-following eyes.
4. **Species + hats** through data binding and Components: one `.riv`, no
   per-species art.
5. **Integrate** with `rive-ios` (macOS 13.1+, SwiftUI): swap `GobView`'s
   Canvas for a `RiveViewModel`, map `Mood` → `mood` input. Test on an Intel
   Mac (renderer support there is unverified).
6. **Marketing video.** Veo 3.1 "Ingredients to video" with three references
   (Gob sheet, a MacBook notch scene, a style frame). Short loops for socials
   also come straight from Gobbl's Clip Studio (Tools → Share → Make a Clip).

Sources: Google Nano Banana Pro announcement; Rive docs (Apple runtime, data
binding, components, AI agent); Recraft ownership FAQ; US Copyright Office AI
report part 2; riveanimator.com pricing; Duolingo's Rive character write-ups.
