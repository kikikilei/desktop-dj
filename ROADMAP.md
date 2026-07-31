# Roadmap

## Next: interactive deck MVP

1. Add four native hit targets over the deck buttons.
2. Give every button a pressed state and short light response.
3. Connect three buttons to Previous, Play/Pause, and Next.
4. Use the fourth button as a DJ-style Cue action that seeks to the beginning
   of the current track. This mapping can change after design review.
5. Connect the right-hand slider to the macOS default output volume.
6. Handle output-device changes and gracefully disable the slider for devices
   that do not expose software volume control.
7. Clip the current album artwork into the platter's center label and rotate it
   slowly only while playback is active.

The platter itself remains noninteractive in this phase.

## Then: layered deck

- Move the cat, static console, platter rim, album art, button lights, and
  slider knob into separate render layers.
- Derive deck accent colors from the album cover.
- Preserve a flattened-animation fallback so existing skins keep working.

## Later

- Complete Ragdoll Cat and Orange Tabby skin packages.
- Add a documented skin import/export format.
- Explore platter scrubbing only after reliable seeking and interaction
  feedback are proven.
- Treat BPM-aware animation as an experiment: Now Playing metadata does not
  reliably include BPM, so it may require external metadata lookup or local
  audio analysis.
