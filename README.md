# FEver

FEver is a Godot tactical RPG engine for desktop and mobile. It runs FE6 and FE7 campaigns in Classic and Rogue modes using data imported from a player-supplied GBA ROM. No ROMs, extracted game media, dialogue catalogs or static chapter packages are included.

The project uses **Godot 4.6.2**, GDScript and the Compatibility renderer. It implements its own battle and campaign systems; it is not a GBA emulator. Event presentation, AI and optional gameplay rules can differ from the original hardware.

FEver is independent of Nintendo and Intelligent Systems. Third-party names identify compatible games. The bundled application artwork is custom project media; original game artwork and sound are read locally from the selected cartridge.

## Getting started

1. Open this folder's `project.godot` with Godot 4.6.2 and let resource import finish.
2. Run the project with **F5 / Run Project** to open the cartridge library.
3. Select **Insert Cartridge**, choose a supported `.gba` file and wait for import.
4. Choose a campaign and difficulty, or continue a save for that cartridge.

From a terminal in this folder:

```sh
godot --editor --path .
# Run without opening the editor:
godot --path .
```

Keep ROM files outside the project. Desktop imports retain the selected file path; mobile imports keep a validated private copy.

## Dynamic ROM import

All supported cartridges use the same dynamic import pipeline for their game and region.

| Game | Supported native layout |
| --- | --- |
| FE6 | Japanese base (`AFEJ`), including compatible translated or modified cartridges |
| FE7 | Japanese (`AE7J`) and US/English (`AE7E`) bases |

Compatibility depends on native structures and engine behavior, not just the filename or header. The importers follow table pointers and read current records, including supported relocated or edited data. Known native helpers are validated before their behavior is adapted; unsupported layouts, changed helper implementations and malformed data produce compatibility errors. Arbitrary engine rewrites and additional regional layouts are not supported automatically. FE8 will be supported in the future.

The runtime reads:

- Chapter directories, map geometry, terrain, deployments and supported objectives, events, routes and rewards.
- Character, class and item records, names, weapon rules, promotions, supports and ending records.
- Dialogue, portraits, backgrounds, title artwork, map sprites, supported battle animation data, music sequences and samples.
- Native difficulty settings, deployment/stat banks and supported campaign progression conditions.

FE6 and FE7 support Classic Normal, Classic Hard, Rogue Normal and Rogue Hard. FE7 exposes all three campaign routes, including supported side chapters and the two-stage finale. Branch choices, army transfers, recruitment and ending progression use the selected cartridge's data and the engine's saved state.

Gallery indexes are discovered when first opened. Images and audio are decoded as needed, and malformed optional gallery artwork is isolated from the campaign decoder. Generated chapter resources use private temporary storage; decoded media is not installed as a persistent asset cache or written into the project.

Native hardware-only visual effects and some choreography are approximated. Audio sequencing, PSG synthesis and envelopes are not bit-perfect hardware emulation, and stat rolls use the port's deterministic random generator. These limits do not imply support for arbitrary ROM hacks.

## Playing

### Classic campaigns

**Classic Normal** and **Classic Hard** provide campaign play with familiar tactical systems: deployment, movement and terrain, combat forecasts, weapon ranks and durability, healing and support actions, rescue and trade, recruitment, promotions, shops, supply, and chapter objectives. The available campaign routes and chapters depend on the loaded cartridge.

Select a friendly unit to inspect its movement and commands. Preview a destination, choose an action, and inspect the combat forecast before committing. Enemy ranges and unit details help with planning. The battle record and conversation log let you review what happened.

The interface supports mouse clicks and touch input. Drag to pan the battlefield; use the mouse wheel or a two-finger pinch to zoom. Save/resume, chapter restart, and action Undo are available through the interface. Mode-specific limits apply to Undo and restarts in Rogue mode.

### Quality of life

Settings let you adjust presentation and gameplay without editing files. Options include:

- Grid visibility, dialogue speed, music and sound volumes, screen shake, and when battle animations play.
- Skipping tutorials, automatic weapon selection, and automatic lord promotion at level 20.
- Permadeath in Classic mode. With it disabled, defeated allies miss the next battle and then return; required allies still need to survive.
- Support growth across the map and additional support conversations while retaining the five-rank combat-bonus limit.
- Reinforcement behavior: same-turn attacks, same-turn attacks with warnings, or attacks starting on the following turn.
- Separate weapon and item durability settings, including paid/free chapter-start repairs and unlimited durability.
- Supply access, using keys from Supply, and free ordinary door/chest unlocking. Mission gates and special locks retain their required triggers.

A separate **Cheats** panel provides options such as extra gold, temporary free movement, combat advantages, and clearing current enemies. Difficulty changes take effect on a chapter restart or when entering a new chapter. Some preferences are constrained by the selected mode.

### Rogue mode

**Rogue Normal** and **Rogue Hard** add a persistent upgrade system to the campaigns. Characters gain personal skills and acquired abilities; enemies can carry skills too. Choose from upgrade cards as the run progresses, with periodic army-wide rewards alongside individual upgrades.

Upgrades can affect movement, combat, weapon training, growths, support gain, fog vision, and other systems. Some rewards offer skill exchanges, training, or recovery of fallen allies. Personal skills stay associated with their characters. The in-game Rogue skill library describes the available effects.

Rogue mode enforces permadeath and tracks allowances for Undo, arena visits, and training. These limits and the upgrade choices are part of the run's progression, rather than unrestricted Classic-mode preferences.

## Libraries

The startup **cartridge library** lets you reopen imported games. Within a game, **Settings → Library** provides:

| Category | What you can browse |
| --- | --- |
| Original backgrounds / CGs | Scene artwork decoded from the cartridge |
| Original portraits | Cartridge character portraits |
| Original maps | Map artwork and chapter/route entries |
| Music listener | Music from the loaded ROM |
| Items glossary | Item information |
| Supports | Support partners and conversations |
| Character voices | Clips from an imported voice pack |
| Rogue skills | Personal and acquired skill information |

Enabled artwork imports also appear in their corresponding imported-library categories. Availability depends on the loaded game and installed packs; voice clips are supplied by the player.

## Custom imports

Open **Settings → Custom** to manage customization. Artwork and voices are imported into private application storage, so personal packs do not need to be added to the project or included in an exported build.

- **Character art:** replace dialogue portraits and unit-card portraits, with separate controls for scale, position, and flipping.
- **Background art:** replace backgrounds, CGs, title artwork, and supported battle backgrounds/platforms.
- **Character voices:** provide Ogg, WAV, or MP3 clips for supported actions such as selection, attacks, critical hits, damage, defeat, and status. A voice ZIP can contain `voices.json` at its root or inside a parent folder; clip paths are relative to that manifest.
- **Custom translations:** import/export a JSON configuration of literal word or phrase replacements, with whole-word and case-sensitive options. These affect displayed text; they do not patch a ROM or enable another ROM revision.
- **FE7 tactician name:** the default is **Tactician**. Add a custom translation from `Tactician` to your preferred name to change its display in dialogue and logs.
- **Personal skills:** use **Settings → Advanced** to export a configuration, edit supported fields, import overrides, or restore defaults. Character keys and personal `effect_id` references use `fe6_unit_<id>` or `fe7_unit_<id>`, based on the ROM character ID. Name-based character keys are not accepted.

Artwork and voice imports use ZIP packs with JSON manifests and referenced media, rather than an arbitrary archive of images or sounds. Artwork uses PNG files. Pack formats are implemented in `runtime/character_art_import.gd`, `runtime/portrait_store.gd`, `runtime/map_art_store.gd`, `runtime/sprite_store.gd`, and `runtime/voice_store.gd`. Use the controls in the import panel to enable or disable custom artwork and restore the original presentation.

ZIP manifest and media paths match regardless of capitalization. Valid voice clips, artwork entries, translation replacements, and personal skill overrides can import even when other entries fail validation; the import result reports what was skipped. A pack with no valid entries leaves the previous selection active. Unreadable manifests, unsafe archives, and storage failures still stop the import. ROMs and saves must validate as complete, internally consistent files.

The voice import panel also offers **Delete all imported voices (both games)**. This removes active and inactive voice media from private app storage; your source ZIP files remain untouched.

The artwork and voice delete buttons show the stored size of the packs they will remove, including inactive imports.

## Saves and local data

Each cartridge has a separate save namespace keyed by game and ROM SHA-256: `user://saves/<game>-<rom-sha256>/suspend.json`. A changed ROM is a different cartridge identity, even when its title is unchanged.

FEver saves are separate from GBA cartridge saves and emulator save states. Use **Settings → Advanced → Export Save / Import Save** to transfer a game between installations. The cartridge library's information panel also provides **Export Saves** and diagnostics export.

Saves, preferences, temporary ROM resources and custom imports live under Godot's private `user://` storage. Export saves before clearing application data or uninstalling a mobile build. The receiving installation needs the identical supported cartridge; save exports do not include ROMs or custom media packs.

## Building

Use Godot **4.6.2** and matching export templates. Install templates through **Editor → Manage Export Templates**. No private developer scripts or reference tools are required to open or export this folder.

The project includes one Android export preset. Create desktop presets locally. Exported builds must include `*.json,notices/*.txt` in the non-resource filter: these contain personal-skill configuration, shared text encodings and offline engine notices. Preserve exclusions for development content and tests, and keep ROMs, saves, custom packs and signing credentials outside the project.

### Desktop

1. Open **Project → Export** and add a preset for your target platform and architecture.
2. Set the resource filters described above and choose an output directory outside this project.
3. Export the application. If using a separate `.pck`, distribute it with the executable.

For example, after creating a preset named **Windows Desktop** and an output folder:

```sh
godot --headless --path . --export-release "Windows Desktop" ../build/windows/FEver.exe
```

Windows is the primary development platform. Validate Linux and macOS exports on their target systems.

### Android

The included **Android** preset targets ARM64 and defaults to `../build/fever-debug.apk`. Network permissions are disabled. The verified local build uses Godot 4.6.2, matching export templates, OpenJDK 21 and an installed Android SDK.

1. Set **Java SDK Path** and **Android SDK Path** in **Editor Settings → Export → Android**.
2. Configure a debug keystore in those settings, resolve export configuration errors and create the output folder.
3. Export from **Project → Export → Android**, or run:

```sh
godot --headless --path . --export-debug "Android" ../build/fever-debug.apk
```

Keep `textures/vram_compression/import_etc2_astc=true` enabled in `project.godot`. Keep keystores and credentials private. Local Windows sandbox safe-save/rename failures can require running the export in a normal PowerShell session with access to the project, temporary directory and installed SDK/JDK.

Install on an ARM64 device for testing. Check the native ROM picker, portrait/landscape layouts, touch dragging, audio, save/resume and private storage. Desktop/headless checks do not establish physical-device behavior. Release signing must be configured separately from the debug build.

### iOS

No iOS preset or verified iOS build is included. This requires a macOS/Xcode environment, export configuration, signing and device validation.

### Verify an export

Start without a previously imported ROM and confirm the cartridge library opens. Import a supported cartridge, start a chapter, exercise movement and combat, then save, close and resume. Confirm **Third-party notices** is available offline. Each player supplies their own cartridge.

## License and notices

No license has been decided yet for FEver's own code. Godot Engine and its bundled components have their own licenses; their notices are included in [notices/](notices/README.md) and available in the application's information/settings panels. Keep these files in exported builds and update them when changing the engine/template version.

## Project layout

| Path | Purpose |
| --- | --- |
| `project.godot` | Engine settings and cartridge-library startup scene |
| `export_presets.cfg` | Android export configuration |
| `engine/` | Battle rules, campaign state, skills and save handling |
| `runtime/` | Shared ROM decoding, galleries, text encodings, resource loading and storage |
| `runtime/fe6/` | FE6-specific profiles, readers and event adapters |
| `runtime/fe7/` | FE7-specific regional profiles, readers and event adapters |
| `ui/` | Battle interface, menus, libraries and customization panels |
| `audio/` | Music, sound and voice playback |
| `config/` | Project personal-skill definitions |
| `art/branding/` | Generated application branding |
| `notices/` | Godot Engine and dependency notices |

The `.gitignore` excludes local caches, extracted development content, ROMs, saves, build products and signing credentials. Preserve these exclusions when preparing a source checkout.
