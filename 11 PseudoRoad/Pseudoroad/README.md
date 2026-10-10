# Pseudo 3D Road - game and editors

Eight programs share five units. Put **all files in one folder**, for example
`F:\Claude\Lazarus\01 PseudoRoad\`, together with `SDL3.dll`.

| File | What it is |
|---|---|
| `PseudoRoad.lpr` | the game |
| `AudioEditor.lpr` | edits `data\audio.ini` with a live test drive (engine, gears, grass, kerb, crash) |
| `MusicEditor.lpr` | edits `data\music.ini` as a piano roll with chords and bass, plays the song |
| `CameraEditor.lpr` | edits `data\camera.ini` with the real road, traffic and car behind the sliders |
| `TrackEditor.lpr` | edits `data\track.txt`: section list, map, height profile, 3D fly-through |
| `ModelEditor.lpr` | edits `data\models\*.car` as text with a live 3D view; the line under the cursor glows yellow |
| `SceneryEditor.lpr` | edits `trees.ini`, `bushes.ini`, `signs.ini` with sliders and colour pickers, live road view and gallery |
| `ShapeEditor.lpr` | edits `data\shapes\*.shape` as text with a live picture in every season, by day and by night, or on the road |
| `p3d_common.pas` | settings, data files, track format, default model/shape/bitmap writers |
| `p3d_world.pas` | road renderer, vehicle models, scenery shapes, bitmaps, traffic, mirror, minimap |
| `p3d_audio.pas` | engine / ground / crash sound and the music player |
| `p3d_gui.pas` | buttons, sliders and spinners for the editors |
| `p3d_textedit.pas` | the text editor used by the shape editor |

## Building each program in Lazarus

For each `.lpr` file:

1. **Project > New Project from File...**, pick the `.lpr`, choose *Simple Program*.
2. **Project > Project Inspector > Add > New Requirement**, add the SDL3 package.
3. Compile. Every exe must end up in the same folder so they share the `data` folder.

## The data folder

Created next to the exe on the first run. Missing files are always re-created
with the defaults, so deleting a file resets it. Press **F5** in the game
(or the Reload button in an editor) after editing a file by hand.

| File | Contents |
|---|---|
| `camera.ini`, `camera_default.ini` | camera position and angles |
| `vehicles.ini` | player model and colour, traffic count, speeds, vehicle types and how often each appears |
| `trees.ini`, `bushes.ini`, `signs.ini` | where scenery goes, plus the colours the shapes use (`$pine.trunk`, `$bush.dark`, ...) |
| `audio.ini`, `music.ini` | sound settings and the song |
| `seasons.ini` | the chosen season and time, the colours of each season (sky, grass, road, leaf tint, flowers, weather) and of the night |
| `track.txt` | the map, one road section per line |
| `models\*.car` | vehicle geometry: sedan, sports, van, pickup, truck, bus |
| `shapes\*.shape` | scenery geometry: pine, tree, bush, flowerbush, billboard, lamp, chevron, warning |
| `bitmaps\poster0..3.bmp` | billboard posters (352 x 176, edit with any paint program) |

Every model and shape file starts with comments explaining its commands.

**New vehicle type:** copy e.g. `models\van.car` to `models\camper.car`, edit it, and
add `camper:2` to `types=` in `vehicles.ini`. Set `model=camper` under `[player]` to drive it.

**New scenery shape:** the game places scenery by name, so only the eight names
pine, tree, bush, flowerbush, billboard, lamp, chevron and warning appear on the road.
To try a new look, edit one of those (or "Save as" a copy first to keep the original).

**Glows at night:** `glow <col> cx cy r` in a shape draws a soft light at night only
(lamp heads, billboard spotlights). Old shape files get these lines added automatically.

## Seasons and day / night

Spring has blossom petals and flowering bushes, summer is green, autumn turns the leaves
orange and drops them, winter has snow on the ground and on the pines. At night the sky
gets stars and a moon, the scenery darkens, lamps and billboards glow and your car's
headlights light the road. Choose in the game with **F6** (season) and **F7** (day/night)
or in the C menu; the choice is saved in `seasons.ini`.

**New poster:** change `variants 4` to `variants 5` in `shapes\billboard.shape` and
add `bitmaps\poster4.bmp`.

## Keys

- **Game:** Arrows/WASD drive, R reset, C camera / world menu, F5 reload data, F6 next season,
  F7 day/night, M mute, N music, Esc quit
- **Audio editor:** Up/W gas, Down/S brake, G grass, K kerb, X crash, N music, F2 save, F5 reload
- **Music editor:** Space play/stop, Left/Right page, F2 save, F5 reload; left-click note, right-click rest
- **Camera editor:** Space drive/stop, H hide panel, F2 save, F5 reload
- **Track editor:** Up/Down select, Space play preview, J jump to section, Shift = bigger steps, F2 save, F5 reload
- **Model editor:** click the text and type; F2 save, F5 reload, Esc leaves the text (again to quit);
  drag the 3D view to turn the model, wheel zooms, Space spins; "Save as" makes a new model file
- **Scenery editor:** 1/2/3 tabs, G road/gallery, Space drive, F2 save tab, F5 reload all, F6 season, F7 day/night
- **Shape editor:** click the text and type; F2 save, F5 reload, Esc leaves the text (again to quit);
  outside the text: Left/Right variant, S road side, 1-4 season, N day/night, Space drive; wheel zooms
