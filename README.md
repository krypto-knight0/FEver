# FEver

Retro SRPG campaigns for desktop and Android.

Play FE6 and FE7 with full mouse or touch controls. Choose a Classic campaign or build an army through Rogue mode, then customize difficulty, artwork, voices, translations, and more.

## Start playing

1. Open FEver and select **Insert Cartridge**.
2. Choose a supported `.gba` file and let the import finish.
3. Select a campaign and difficulty, or continue an existing save.

Imported games appear in the cartridge library for quick access. FEver reads maps, units, dialogue, artwork, and music from the cartridge you select.

### Supported cartridges

| Game | Game code | Cartridge |
| --- | --- | --- |
| Flux Echo 6 | `FX6E` | Sci-fi prototype/test campaign based on FE6 |
| FE6 | `AFEJ` | Japanese base |
| FE7 | `AE7J` | Japanese base |
| FE7 | `AE7E` | US/English base |

Each cartridge has its own saves and progress. Some modified and translated roms are also compatible, outside of custom ARM/Thumb logic.

### Run from source

Use **Godot 4.6.2**. Open [godot/project.godot](godot/project.godot), let resource import finish, and press **F5**.

## Choose your mode

**Classic Normal** and **Classic Hard** offer campaign play with deployment, terrain, weapon ranks and durability, rescue and trade, recruitment, promotions, supports, shops, and chapter objectives. FE7 includes all three starting campaign routes.

**Rogue Normal** and **Rogue Hard** add personal skills, acquired abilities, upgrade cards, and army-wide rewards. Build around movement, combat, growths, support bonuses, and other combinations. Rogue runs use permadeath and track allowances for Undo, arena visits, and training. Browse the **Rogue skills** library for each ability's effects.

## Controls and settings

Select a friendly unit to see its movement and commands. Choose a destination, pick an action, and review the combat forecast. Drag to pan the battlefield; use the mouse wheel or a two-finger pinch to zoom. Enemy ranges, unit details, the battle record, and conversation log help you plan and review your turn.

Settings include:

- Dialogue and animation speed, music and sound volume, grid visibility, and screen shake.
- Battle animation preferences, tutorial skipping, automatic weapon selection, and automatic lead-unit promotion.
- Classic-mode permadeath, reinforcement timing and warnings, support growth, durability, and chapter-start repairs.
- Supply access, keys, and ordinary door/chest unlocking.
- Save/resume, chapter restart, Undo, and a separate **Cheats** panel.

## Libraries and customization

Open **Settings → Library** to browse portraits, backgrounds, maps, music, items, support conversations, character voices, and Rogue skills.

Use **Settings → Custom** to import portrait and background artwork, character voices, and text replacements. Artwork and voice packs use ZIP files containing JSON manifests and their media. Artwork uses PNG; voice clips can use Ogg, WAV, or MP3. Import panels let you enable, disable, and remove packs.

**Settings → Advanced** provides personal-skill configuration export/import. Custom translations can also change displayed words and names, including the FE7 tactician name.

## Save and transfer progress

Use **Settings → Advanced → Export Save / Import Save** to move a save between installations. The cartridge library also provides **Export Saves** and diagnostics export.

Load the same cartridge file on the receiving device to continue its save. Artwork and voice packs can be imported separately through **Settings → Custom**.

## Project layout

| Path | Contents |
| --- | --- |
| [godot/](godot/) | Playable application and Android export preset |
| [godot/engine/](godot/engine/) | Battles, campaigns, skills, and saves |
| [godot/runtime/](godot/runtime/) | Cartridge import, galleries, and storage; game-specific readers are in `fe6/` and `fe7/` |
| [godot/ui/](godot/ui/) | Battlefield controls, menus, and customization panels |
| [godot/audio/](godot/audio/) | Music, sound, and voice playback |
| [godot/config/](godot/config/) | Personal-skill definitions |
| [godot/art/branding/](godot/art/branding/) | FEver artwork and icons |
| [godot/notices/](godot/notices/) | Godot Engine and component notices |
| [tests/fe6/shared/](tests/fe6/shared/) | Shared FE6 checks |
| [tools/](tools/) | Test runners and their shared helpers |

## Check your setup

The shared tests work with FE6 `AFEJ` and Flux Echo 6 `FX6E` cartridges. They cover importing, edited data, the opening chapter, progression, presentation, libraries, interactions, campaign routes, and Rogue mode.

Use **Python 3.11 or newer** and **Godot 4.6.2**. Python's standard library is sufficient.

List the available suites:

```sh
python tools/run_fe6_tests.py --list
```

Run a quick import and opening-chapter check:

```sh
python tools/run_fe6_tests.py --rom "/path/to/Flux Echo 6.gba" --suites routing chapter1 --output build/tests
```

Run all shared suites:

```sh
python tools/run_fe6_tests.py --rom "/path/to/Flux Echo 6.gba" --output build/tests
```

The runner finds `godot` or `godot4` on PATH. Use `--godot "/path/to/godot-console"` to select an engine executable. Results and logs appear under the output directory you choose.

[tools/test_fe6_dynamic.py](tools/test_fe6_dynamic.py) runs individual suites, including a focused Rogue check with `--rogue --focused`. PowerShell users can use [tools/validate-fe6.ps1](tools/validate-fe6.ps1). See the [shared test guide](tests/fe6/README.md) for all options.

## Build an application

Install Godot 4.6.2 and its matching export templates through **Editor → Manage Export Templates**.

For desktop builds, add your platform under **Project → Export** and choose an output location. The included **Android** preset targets ARM64. Android export also uses an installed Android SDK, OpenJDK 21, and a signing keystore configured in Godot's editor settings.

For an Android debug build, create `build/` beside this README and run:

```sh
godot --headless --path godot --export-debug "Android" ../build/fever-debug.apk
```

## Third-party notices

Godot Engine and its bundled components have their own licenses. Their [notices](godot/notices/README.md) are included with FEver and available in the application's information/settings panels.
