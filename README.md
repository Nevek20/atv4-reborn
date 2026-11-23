# ATV4 Reborn

**A Godot 4 remake of *ATV Offroad Fury 4* (PS2, 2006), built from the original game's own data and reverse-engineered code.**

🇧🇷 [Leia em português](LEIA-ME.md)

The goal is to be **100% faithful to the PS2 game**. Physics, cameras, parts
and liveries come from the game's XML files, and behavior is ported from the
disassembled executable (PAL, `SCES_546.88`) using Ghidra. Every number has a
source: an XML file, a function in the exe, a PCSX2 save state or a frame of
gameplay video. Anything that is our own invention is marked as such in the
code and docs.

> **Status:** playable. One track (RX01, Rallycross) with a full race: intro
> flyover, countdown, 7 AI rivals, laps, the game's HUD, Score, results
> screen and pause menu. 12 buggies, 12 trucks, one unused truck rescued
> from the game files and one extra car of our own. ATVs and bikes are next.

## Highlights

**Ported from the game**

- Vehicle physics: tires and drifting, engine, clutch, gearbox, wheel spin,
  suspension, anti-pitch, air control, aerodynamic drag, per-surface friction.
  Runs at 50 Hz like the PAL version (60 Hz for NTSC comparisons)
- Race camera: orbit, speed-based distance and zoom, height damping, ground
  clearance, detach/reattach and speed shake
- Race mode on RX01: intro camera, countdown, AI rivals (racing line,
  overtaking, catch-up), lap counting through the checkpoint, automatic
  respawn (off track, wrong way, missed checkpoint) and respawn boxes
- The game's HUD, Score (Slide and AirTime), results screen, pause menu and
  Race Again screen, laid out from the game's own files and checked against
  RAM from save states
- Track objects that break (fences, hay bales), crowd, sky and fog
- Factory parts and upgrades, tires, rims, bumpers and Tune & Setup per vehicle
  (`vehicles.xml` + `upgrades.xml`)
- Visual suspension, collision hulls, driver model with the steering
  animation, tire/suspension/landing/crash sounds (989snd), dust, stones,
  debris and dirt buildup
- Liveries and driver outfits built from the game's layer system (colors,
  logos, number)

**Our own improvements** (clearly marked in the code and docs)

- Cockpit camera with G-force head movement, speed FOV and blur, free look
- Camera orbit on the right stick
- Engine sounds recorded per car in Engine Simulator
- Working dashboards, steering wheels that turn with the driver's hands,
  brake/reverse/head lights, exhaust smoke, engine vibration, animated fans
  and wheel motion blur
- A workshop screen (paint, logos, driver, upgrades, tuning) until the
  game's garage menu is ported

**Validated against the real game**

PCSX2 save states (mass, center of mass, gear ratios, rpm, suspension travel,
per-wheel forces, camera, HUD, AI, menus) and frame-by-frame reads from
gameplay videos. `tests/` holds about 50 headless tests that compare the
remake to those references.

## Requirements

- **Your own copy of ATV Offroad Fury 4 (PS2).** The tools in `tools/`
  extract the models, textures and sounds from your copy of the game.
- [Godot 4.7](https://godotengine.org/) (Forward+)
- Python 3 with Pillow and zstandard (`pip install pillow zstandard`)
- The C++ physics library comes prebuilt in `bin/` (Windows and Linux).
  Without it the game falls back to GDScript. Building it is described in
  `docs/comandos.md`.

## Getting started

`<unpacked>` is the game's unpacked archive and `<textures>` the folder
created in step 1.

```
:: 1. textures from the game archive (~6 min)
python tools\gob_tex2png.py <unpacked>\gob --out <textures>

:: 2. buggies and trucks (body, parts, brakes, wheels, tires, livery)
python tools\gerar_buggies.py <unpacked> <textures>
python tools\gerar_buggies.py <unpacked> <textures> --classe truck

:: 3. driver, sounds and effects
python tools\piloto.py <unpacked>
python tools\sfx_jogo.py <unpacked>
python tools\fx_jogo.py <unpacked>

:: 4. RX01 track objects and sky, HUD and menu screens
python tools\rx01_objetos.py <unpacked>
python tools\hud_jogo.py <unpacked>
python tools\fex_jogo.py <unpacked>
```

Then open `project.godot` in Godot, wait for the import and press **F5**.
Press **Enter** to start a race. Without the extracted assets the car shows
up as a box and a basic HUD is used.

## Controls

| Key | Action |
|---|---|
| W / S or arrows | throttle / brake (hold S when stopped to reverse) |
| A / D | steer |
| Space | clutch (tap while turning and accelerating for a Clutch Turn) |
| E / Q | gear up / down (manual) · M toggles auto/manual |
| C | camera: near, far, hood, bumper, cockpit |
| Enter | start a race (skips the intro) · Continue on the results |
| Esc | pause during a race · quit outside a race |
| R | respawn (in a race only below 40 mph, like the game) |
| T / Backspace | back to the start / leave the race |
| Tab / V | vehicle menu / next vehicle |
| O | workshop (paint, logos, driver, upgrades, tuning) |
| H | headlights · B steering wheel style · G cockpit effects · N mute |
| F1 / F2 / F3 | HUD modes / FPS and timings / C++ physics on and off |

Gamepads work too: triggers, left stick, A = clutch (and skips the intro),
Start = pause, right stick = camera orbit, Select = camera.

## Project layout

```
main.gd / main.tscn   the scene: terrain, car, camera, HUD, menus
carro/                the vehicle: physics ported from the exe, model, driver, parts, liveries
camera/               race camera (from the exe) and our cockpit/orbit cameras
pista/                RX01 terrain and objects, race logic, AI rivals, respawn, Score
menu/                 game HUD, results/pause screens, workshop
efeitos/, som/        dust, stones, debris, smoke; game sounds and engine sounds
fisica_cpp/, bin/     the physics in C++ (GDExtension) and the prebuilt libraries
data/                 game XML/JSON used at runtime (physics, cameras, parts, track, HUD)
tools/                Python extractors (models, textures, liveries, sounds, track, HUD, save states)
tests/                headless tests (python tests/rodar_tudo.py runs them all)
re/                   reverse-engineering helpers (Ghidra scripts, exe_util, RAM readers)
docs/                 history of every decision, exe map, commands, asset formats
```

`docs/historico.md`, `docs/engenharia_reversa.md` and `CLAUDE.md` (in
Portuguese) are the full technical notes: memory offsets, function addresses
and the reasoning behind each decision.

## Roadmap

1. ATVs and bikes, until every vehicle is complete
2. The game's menus, with video, audio and control options, profile and saves
3. Every track
4. Every game mode, then the career
5. Graphics options (a "faithful" and an "enhanced" mode), then polish
6. Local split-screen multiplayer is planned from the start; online
   multiplayer comes last

## Legal

This is a non-commercial fan project made for study and preservation. It is
not affiliated with, endorsed by or sponsored by Sony Interactive
Entertainment or Climax Racing. *ATV Offroad Fury* and all related names,
models, textures, sounds and data belong to their respective owners.

No game executable, disc image or decompiled source code is distributed
here, and models, textures and sounds are extracted from your own copy by
the tools. The repository does include some data files taken from the game
that the remake reads at runtime (XML/JSON in `data/`) and the RX01 terrain
(`assets/pista/terreno`). You need your own legally obtained copy of the
game.

## License

The original code in this repository (GDScript, C++, Python, Java and shell
scripts) is released under the [MIT License](LICENSE). Game data and assets
derived from *ATV Offroad Fury 4* are **not** covered by this license and
remain the property of their owners.
