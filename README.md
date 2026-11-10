# ATV4 Reborn

**A Godot 4 remake of *ATV Offroad Fury 4* (PS2, 2006), built from the original game's own data and reverse-engineered code.**

🇧🇷 [Leia em português](LEIA-ME.md)

The goal is to be **100% faithful to the PS2 game**. Physics, cameras, parts
and liveries come from the game's XML files, and behavior is ported from the
disassembled executable (PAL, `SCES_546.88`) using Ghidra. Every number has a
source: an XML file, a function in the exe, a PCSX2 save state or a frame of
gameplay video.

> **Status:** playable prototype. One track (RX01), 12 buggies, 12 trucks,
> one unused truck rescued from the game files and one extra car of our own.

## Highlights

**Ported from the game**

- Vehicle physics: tires and drifting, engine, clutch, gearbox, wheel spin,
  suspension, anti-pitch, air control, aerodynamic drag, per-surface friction
  and drag. Runs at 50 Hz like the PAL version (60 Hz for NTSC comparisons)
- Race camera: orbit, speed-based distance and zoom, height damping, ground
  clearance, detach/reattach and speed shake
- Factory parts and upgrades per vehicle (`vehicles.xml` + `upgrades.xml`)
- Visual suspension (A-arms, shocks, solid axles), collision hulls, driver
  model with the steering animation, tire/suspension/landing sounds (989snd),
  tire dust and dirt buildup
- Liveries generated from the game's layer system (colors, logos, number)

**Our own improvements** (clearly marked in the code and docs)

- Cockpit camera with G-force head movement, speed FOV and blur, free look
- Forza-style camera orbit on the right stick
- Engine sounds recorded per car in Engine Simulator
- Working dashboards, steering wheels that turn with the driver's hands,
  brake/reverse/head lights, exhaust smoke, engine vibration and animated fans

**Validated against the real game**

PCSX2 save states (mass, center of mass, gear ratios, rpm, suspension travel,
per-wheel forces, camera) and frame-by-frame HUD reads from gameplay videos.
`tests/` holds headless tests that compare the remake to those references.

## Requirements

- **Your own copy of ATV Offroad Fury 4 (PS2).** The tools in `tools/`
  extract the models, textures and sounds from your disc image.
- [Godot 4.7](https://godotengine.org/) (Forward+)
- Python 3 with Pillow and zstandard (`pip install pillow zstandard`)

## Getting started

```
:: 1. textures from the game archive (~6 min)
python tools\gob_tex2png.py <game>\unpacked\gob --out <game>\texturas

:: 2. buggies and trucks (body, suspension parts, brakes, wheels, livery)
python tools\gerar_buggies.py <game>\unpacked <game>\texturas
python tools\gerar_buggies.py <game>\unpacked <game>\texturas --classe truck

:: 3. driver, sounds and effects
python tools\piloto.py <game>\unpacked
python tools\sfx_jogo.py <game>\unpacked
python tools\fx_jogo.py <game>\unpacked
```

Then open `project.godot` in Godot, wait for the import and press **F5**.
Without the extracted assets the car shows up as a box.

## Controls

| Key | Action |
|---|---|
| W / S or arrows | throttle / brake (hold S when stopped to reverse) |
| A / D | steer |
| Space | clutch (tap while turning and accelerating for a Clutch Turn) |
| E / Q | gear up / down (manual) · M toggles auto/manual |
| C | camera: near, far, hood, bumper, cockpit |
| Tab / V | vehicle menu / next vehicle |
| H | headlights · B steering wheel style · G cockpit effects · N mute |
| R / T | flip the car back / restart |
| Esc | quit |

Gamepads work too: triggers, left stick, A = clutch, right stick = camera
orbit, Select = camera.

## Project layout

```
car.gd, game_camera.gd ...  gameplay scripts (physics and camera ported from the exe)
data/                       game XMLs used at runtime (physics, cameras, parts)
tools/                      Python extractors (models, textures, liveries, sounds, save states)
tests/                      headless physics tests + rodar_testes.py
re/                         reverse-engineering helpers (Ghidra scripts, exe_util)
docs/                       exe map, drifting logic, asset formats, engine sounds
som/                        Engine Simulator engines and recorded loops
```

`CLAUDE.md` and `docs/engenharia_reversa.md` (Portuguese) are the full
technical notes: memory offsets, function addresses and the reasoning behind
each decision.

## Legal

This is a non-commercial fan project made for study and preservation. It is
not affiliated with, endorsed by or sponsored by Sony Interactive
Entertainment or Climax Racing. *ATV Offroad Fury* and all related names,
models, textures, sounds and data belong to their respective owners. No game
executable, disc image or decompiled source code is distributed here; you
need your own legally obtained copy of the game.

## License

The original code in this repository (GDScript, Python, Java and shell
scripts) is released under the [MIT License](LICENSE). Game data and assets
derived from *ATV Offroad Fury 4* are **not** covered by this license and
remain the property of their owners.
