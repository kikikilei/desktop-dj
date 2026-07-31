# Design handoff

This file describes the preferred asset handoff for the next interactive DJ
deck iteration.

## Current animation format

- Canvas: `512 × 384 px`
- Playback: `12 fps`
- Pixel edges: nearest-neighbor; do not add smoothing
- Framing: keep the cat and deck aligned to the existing Cow Cat animations
- Loops: the first and last poses should connect without a visible jump
- Preferred delivery: transparent-background animated WebP, PNG sequence, or
  ProRes 4444 MOV
- Also accepted: MP4 or MOV with a clean, evenly lit green background

Every skin may have different fur, ears, tail, glasses, headphones, and deck
styling, but should remain on the same canvas. The skin JSON defines a tolerant
interaction rectangle, so fur can extend slightly outside the visible body
without making dragging or right-clicking frustrating.

## Layered deck assets

For future skins, export every layer on the full `512 × 384 px` canvas so the
app can stack them without manual coordinate matching:

1. `deck-base.png` — static console body, with no album art, button glow, or
   slider knob.
2. `platter-frame.png` — platter rim and any parts that should appear above the
   rotating cover.
3. `deck-lights.png` — transparent colored highlights in their fully lit state.
4. `button-1-on.png` through `button-4-on.png` — transparent lit/pressed
   overlays, one per button.
5. `slider-track.png` — the static rail and markings.
6. `slider-knob.png` — the knob by itself at its neutral orientation.
7. Cat animation — cat and any foreground paw/hand that must appear above the
   platter, without a baked-in album cover or button glow.

Do not animate the button press, glow, or slider travel in a video. The app
will move and fade those layers so the visuals remain synchronized with the
actual command and system volume.

If separating the whole cat from the existing flattened video is too costly,
the first implementation can keep the current video and place a small rotating
cover only inside the platter's center label. Full-size cover art under the
cat's paw should wait for the layered version.

## What to prepare next

For the first interactive pass, the minimum useful design delivery is:

- One reference image labeling the intended function of each of the four
  buttons.
- One off-state deck image and four separate on/pressed button overlays.
- One slider track and one separate slider knob.
- The minimum and maximum knob positions marked in pixels.
- A decision on whether changing volume should also change light color or
  brightness.
- Optional: a transparent platter rim that defines where the circular album
  cover should be clipped.

No additional cat animation is required for the buttons or volume slider.

