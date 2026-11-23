# Kingdom Rush Origins - Speed Mod (Xbox / Microsoft Store PC)

Press **R** to cycle the game speed:

**1x -> 2x -> 3x -> 5x -> 1x ...**

The current speed is shown on a small badge next to the next-wave button. The choice sticks across
levels until you change it again.

Built for the **Xbox app / Microsoft Store (GDK) Windows version** of Kingdom Rush Origins
(`kr3-gdk.exe`, game 6.0.03, package `IronhideS.A.KingdomRushOrigins`). It is not the Steam build.

## Install

1. Close Kingdom Rush Origins completely.
2. Double-click `install.cmd`.
3. Launch the game and press **R** in a level.

The installer only writes to the game's own save folder:

```text
%LOCALAPPDATA%\Packages\IronhideS.A.KingdomRushOrigins_kg1k62egjne32\LocalCache\Local\LOVE\kingdom_rush_origins
```

It backs up `settings.lua`, copies `kro_speed.lua` there and adds the `custom_script` entry the game
uses to load it. No EXE, DLL, asset or game script is modified.

## Uninstall

1. Close the game.
2. Double-click `uninstall.cmd`.

Save slots are never touched.

## How it works

The mod is a plain Lua custom script loaded through the game's built-in `custom_script` hook. It sets
`game.DBG_TIME_MULT`, the engine's own time-warp field (the same value the game's hidden
`z/Z: time warp` debug key changes), re-applies it every frame while a level runs and clears it at 1x.

R is read through the LÖVE key dispatcher, a `love.keypressed` wrapper and a per-frame
`love.keyboard.isDown` check, so it works even if the engine replaces its key handler after the mod
loads. The actual speed is per-frame re-applied, so the game's own debug keys cannot silently reset it.

It also wraps `storage_io_generic.write_file` so the game cannot drop `custom_script` from
`settings.lua` when it saves its settings.

## Troubleshooting

- **R does nothing:** check `kro_speed.log` in the save folder. It logs load, key events, speed
  changes and a `simulation dt ... ms avg` line about every 120 frames in a level. At 60 fps that
  delta should grow with the multiplier (~16.7 / 33.3 / 50 / 83.3 ms).
- **After a game update:** Xbox/Store updates replace the package but keep the save folder. Run
  `install.cmd` again.
- **Speed resets:** reinstall, or re-add `["custom_script"] = "kro_speed";` to `settings.lua` while
  the game is closed.

## Files

| File | Purpose |
| --- | --- |
| `kro_speed.lua` | The mod itself (the only file copied into the save folder). |
| `install.ps1` / `install.cmd` | Installer with backups and loader patching. |
| `uninstall.ps1` / `uninstall.cmd` | Removes the module and the loader entry. |
| `CHANGELOG.md` | Version history. |

## Credits

The idea of using the game's `custom_script` hook together with `game.DBG_TIME_MULT` comes from the
Steam-only [KingdomRushOrigins-2xSpeedMod](https://github.com/aeoliannn/KingdomRushOrigins-2xSpeedMod).
The GDK/Xbox port (this repo), its multi-step speed cycle, HUD badge, installer and diagnostics were
written from scratch for the Microsoft Store build, which loads custom scripts from a different folder
and needs its own key handling.
