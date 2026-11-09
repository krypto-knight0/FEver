# Godot notices

These files apply to Godot Engine and its third-party components.

The following files are unmodified copies from Godot's `4.6.2-stable` release:

- [GODOT_LICENSE.txt](GODOT_LICENSE.txt): [upstream LICENSE.txt](https://github.com/godotengine/godot/blob/4.6.2-stable/LICENSE.txt)
- [GODOT_COPYRIGHT.txt](GODOT_COPYRIGHT.txt): [upstream COPYRIGHT.txt](https://github.com/godotengine/godot/blob/4.6.2-stable/COPYRIGHT.txt)

The copyright file includes the full upstream component inventory and license
texts, including components that may not be used by a particular export.

Both files are available offline through **Third-party notices**, in the
cartridge library's information menu and **Settings → Advanced** during a game.
Keep `notices/*.txt` in every export preset's non-resource include filter.
For desktop distributions, also retain this directory alongside the executable
when providing standalone copies of the notices.

When changing the Godot editor/export-template version, replace both files with
the corresponding upstream release's files and update the version and links
above. Custom engine builds or added dependencies may require further notices.

See Godot's [license-compliance guide](https://docs.godotengine.org/en/4.6/about/complying_with_licenses.html).
