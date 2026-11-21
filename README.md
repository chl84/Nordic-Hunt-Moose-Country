# Nordic Hunt: Moose Country

A first-person moose hunt in a procedurally built Scandinavian valley: spruce and
golden birch, misty lakes, a red cabin by the water and snow on the peaks.
Arcade-leaning, with the emphasis on how the rifles feel.

Built with **Godot 4** (GDScript, Compatibility / OpenGL renderer) and tuned for
integrated graphics - Medium quality holds 60 fps at 1080p on Intel Iris Xe.

## Play

```
./play.sh
```

Needs Godot 4.4 or newer on the PATH (`sudo pacman -S godot` on Arch / Omarchy).
The game also shows up in the app launcher as *Nordic Hunt: Moose Country*.

## The hunt

A hunting day runs from dawn to dusk (12 minutes by default). Find moose, take
clean shots, and bring home the best score you can. Points become *kroner* that
buy rifles and equipment in **Gear**.

- **Score**: bigger animals, longer shots and better placement pay more. Heart,
  lung, brain and spine shots get a multiplier; one-shot kills, unaware animals
  and running targets add bonuses. Walk up to the moose and press **E** to tag it
  for another 20 %.
- **Moose** graze, wander, lift their heads when they hear or see you, and bolt
  when startled. They never attack. A wounded animal leaves a blood trail.
- **Tracking**: **E** on hoof prints tells you their age and heading and lights
  up that animal's trail; **Q** reveals every track around you.
- **Ballistics**: bullets take time to arrive and drop with distance. Scopes show
  hold-over marks labelled in metres.

### Rifles

| Rifle | Action | Sights | Price |
|---|---|---|---|
| Varg .308 | bolt | 3-6x scope | starter |
| Finnskog .45-70 | lever | open sights | 2 500 |
| Storm 9.3 Auto | semi-auto | red dot | 6 000 |
| Tordenskjold .470 | double rifle | express sights | 9 500 |
| Nordlys .300 Magnum | bolt | 4-16x scope | 14 000 |

Equipment: binoculars, laser rangefinder, birch-bark moose call, felt-sole boots.

## Controls

| | |
|---|---|
| WASD | move |
| Mouse | look |
| Left / right mouse | fire / aim |
| Mouse wheel | scope zoom (aiming) or next rifle (once you own two) |
| Shift | sprint - or hold your breath while aiming |
| Ctrl | crouch (quiet) |
| Space | jump |
| R | reload |
| 1-5 | the rifles you own - you start with one, the rest are bought in **Gear** |
| E | interact: tag, examine tracks, climb tower |
| Q | reveal tracks nearby |
| B | binoculars (hold) - bought in **Gear** |
| V | moose call - bought in **Gear** |
| M / Tab | map |
| Esc | pause, settings |

## Settings

Presets Low / Medium / High / Ultra, plus render scale, MSAA, shadows, view
distance, tree detail, ground cover and water quality. *Dynamic resolution* (on
by default) lowers the render scale a little whenever the frame rate dips under
60 and restores it when there is headroom. Settings and progress are stored in
`~/.local/share/godot/app_userdata/Nordic Hunt- Moose Country/`.

Measured on an i7-1265U / Iris Xe at 1920x1080 (sustained): Low ~120 fps,
Medium ~85 fps, High ~60 fps, Ultra ~45 fps.

## How it is made

Everything is generated - there are no imported models, textures or samples.

- `scripts/world/` - height field, terrain chunks with two detail levels, lakes,
  sky and day cycle, trees as MultiMeshes with near/far models, streamed ground
  cover, the cabin and its yard (turf roof, porch, woodshed, outhouse), pier and
  hunting towers, hoof prints and blood.
- `scripts/moose/` - skinned procedural moose, procedural gaits, senses and
  behaviour, hit zones, and a Verlet ragdoll that drives the skeleton.
  The moose body is one lofted skin round a 15-bone skeleton: deep chest on long
  legs, the hump over the shoulders, a mane, the long head with its overhanging
  muzzle, the bell, cupped antler palms edged with tines. `moose.gdshader` draws
  the coat (hair and tufts from the rest-pose position, a soft sheen, fur glowing
  at the outline against the light) and the antlers, hooves, eyes and nose.
- `scripts/player/` - kinematic first-person controller, rifle models and
  animation, recoil, sway, and simulated bullets (drag, drop, travel time).
- `scripts/ui/`, `scripts/fx/`, `scripts/core/` - HUD, menus, particles,
  settings, save game and the sound bank.
- `shaders/` - terrain, water, sky, foliage, grass, tracks and the scope mask;
  `structure` draws the buildings (the vertex alpha picks paint, weathered wood,
  stone, turf, bark...) and `window_glass` paints reflections, curtains and
  lamplight into the windows.
  Spruce, pine and birch are a solid trunk and limbs plus foliage cards
  (`foliage_card`) cut out of textures painted in code (`flora_textures.gd`);
  beyond the tree-detail distance each tree is a single card showing a picture
  of the full model, taken at load time (`impostors.gd`, `impostor` shader).
  Spruces come in three forms: open-grown with boughs to the ground, narrow
  "comb" spruces with hanging curtains of twigs, and forest-grown ones whose
  lower trunk is bare (only deep inside dense forest). Junipers and dwarf birch
  are built the same way; boulders are noise-shaped with their own `rock` shader.
  Shadows of the sky's clouds drift over the land (the shaders' `light()` lets them
  take only direct sunlight), gusts roll through the grass and on across the
  meadows, and the shade and fallen leaves and needles under every tree are baked
  into a map at load (`vegetation.gd`, read by the ground shader).
  `nature_fx.gd` adds mist lying over the lakes and bogs at dawn and dusk (`mist`
  shader), breath smoking in the cold morning air - the hunter's, and that of any
  moose nearby - and birch leaves coming down on the wind (`leaf` shader).
  The lakes mirror their far shores: the water shader walks out along each reflected
  ray across the forest map to the edge of the trees and checks the ray against
  their ragged tops, coloured gold or dark green from the baked litter map.
  `atmo.gdshaderinc` is the shared atmosphere: one sky gradient that the sky is
  drawn with, the landscape fades into and the lakes mirror.
- `tools/gen_audio.py` - synthesises every sound (rifles, mechanics, footsteps,
  birds, moose, wind, water) into `audio/`. Re-run it with `python3
  tools/gen_audio.py` (needs numpy).

### Developer switches

Arguments after `--` are read by the game:

```
./play.sh -- --hunt                    # skip the menu
./play.sh -- --test=play --out=/tmp/x  # scripted run, screenshots to /tmp/x
./play.sh -- --test=gfx --out=/tmp/x   # a handful of fixed views for judging the look (--views=peaks,peaks2: mountainsides through a long lens; --views=cliff,cliff_near: the steepest bank)
./play.sh -- --test=price --out=/tmp/x # what each part of the scene costs on the GPU, measured in one run
./play.sh -- --test=trees --out=/tmp/x # the three big trees up close
./play.sh -- --test=trees --kinds=spruce,spruce_b,spruce_c --out=/tmp/x   # the three spruce forms
./play.sh -- --test=cabin --out=/tmp/x # the cabin from all sides, close up and at dusk
./play.sh -- --test=rocks --out=/tmp/x # boulders up close, from 15 m and out in the valley
./play.sh -- --test=props --out=/tmp/x # juniper and dwarf birch (--kinds=...) up close and from 12 m
./play.sh -- --test=nature --out=/tmp/x # dawn mist, breath, falling leaves (--views=mist,breath,leaves)
./play.sh -- --test=mooseshow --out=/tmp/x # moose portraits: group, profiles, head (3/4 and side), backlit, 68 m (no HUD)
./play.sh -- --check                   # compile every script and shader, then quit
./play.sh -- --inputlog                # print every key press and what the game did with it (never saves)
```

Tests: `world`, `gfx`, `trees`, `far`, `cabin`, `cabinwalk`, `menu`, `weapon`, `gear`, `moose`, `play`, `perf`. Useful extras:
`--allgear`, `--rich`, `--seed=N`, `--minutes=N`, `--time=0..1`, `--nocache`.

## License

[MIT](LICENSE) - free to use, change and share, as long as the copyright notice
comes along. Everything in the game, sounds included, is generated by the code in
this repository, so the same license covers all of it. Godot itself is MIT
licensed too.
