# Changelog

## 3.0.0 - 2026-11-22

- Speed is now driven only by the game's own time-warp field (`game.DBG_TIME_MULT`), re-applied every
  frame while a level runs and cleared at 1x. The timer hook was removed: this build does not call
  `love.timer.step` per frame, so scaling it did nothing.
- Added a probe on `game.simulation:update` that logs the delta the simulation actually receives, so
  the multiplier can be verified from `kro_speed.log`.
- Key input now hooks `love.handlers.keypressed` (the dispatcher) instead of only `love.keypressed`,
  because the game replaces `love.keypressed` after the mod loads. The first key events are logged.

## 2.1.0 - 2026-11-22

- Added a global `love.keypressed` hook so R also works in menus and during loading, not only in levels.
- Added an engine-side delta counter to `kro_speed.log` (`engine dt ... ms avg`) that measures the frame
delta the game loop actually receives.

## 2.0.0 - 2026-11-22

- Speed is now applied at the engine timer level (`love.timer.step` / `getDelta`), so the game
  simulation really runs 2x / 3x / 5x instead of relying only on an internal debug field.
- Automatic fallback to `game.DBG_TIME_MULT` when a build does not call the timer functions.
- R is read both through `keypressed` and by polling `love.keyboard.isDown`, so a dropped key event
  cannot disable the hotkey.
- Speed persists across levels and menus; it no longer resets when a level ends.
- Diagnostics in `kro_speed.log`: load, speed changes, level transitions and average frame delta.
- Installer retires the 1.x `kro_xbox_speed.lua` module and keeps a backup of it.

## 1.0.0 - 2026-11-22

- First attempt: `custom_script` hook plus `game.DBG_TIME_MULT`, native HUD badge, R hotkey.
