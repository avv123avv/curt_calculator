# Curta Calculator — Godot simulation

Interactive model of the Curta mechanical calculator (Curt Herzstark, 1948). Built on the same
pattern as `D:\projects\lukyanov_integrator` (copy its conventions: CLAUDE.md, README ru/en, i18n,
tests, CI/release workflows, F1 manual from `docs/build_instruction.py`).

## Stack
- Godot 4.7, GDScript only, statically typed; tabs; code comments in Russian.
- Viewport 1920×1080, stretch `canvas_items` + `keep`, `gl_compatibility`, Steam Deck target
  (touch → mouse emulation on).
- UI strings in Russian wrapped in `I18n.t("…")`, English in `I18n.EN` (i18n.gd copied from
  lukyanov_integrator). Every new string needs an EN entry — a test scans the sources for missing keys.

## Done
- `curta_model.gd` (`class_name CurtaModel`, RefCounted, no rendering): Type I (8 sliders /
  6 counter / 11 result) and Type II (11 / 8 / 15). Digits arrays, index 0 = units.
  `turn()`: stepped drum gives n teeth (add) or 9−n (subtract, crank up) + extra "+1" tooth at
  the carriage's lowest digit → full-width complement, carry ripples, top carry lost (`overflow`).
  Counter ±1 at digit `carriage`; `counter_reverse` flips sign (for division / square root).
  `clear_registers()` (clearing lever: result + counter), `clear_result()`, `clear_counter()`,
  `clear_sliders()`, `type_digit()`/`backspace()`, `result_signed()`, CSV log
  `n,op,carriage,setting,result,counter` → `save_csv(path)`.
- `curta_calculator.gd` (`class_name CurtaCalculator`, Node2D) + `main.tscn`: abstract 2D schematic
  (registers by column, sliders shifted by carriage, unrolled drum ribs per slider), keyboard only:
  0–9/Backspace type, ←→ select slider, ↑↓ value, Enter turn, Tab ±, [ ] carriage, C clear,
  X sliders, V counter reverse, T type, S CSV (`user://curta_log.csv`), L language.
- `curta_3d.gd` (`class_name Curta3D`, Node3D) + `curta_3d.tscn` — **main scene**. Units = cm, all parts
  built in code (`_build()`, rebuilt on type switch). Angles: `_polar(a, r, y)` = (r·sin a, y, r·cos a), front = +Z;
  slider i at `slider_angle(i)` (highest digit left), value n at `slider_y(n)` (0 top, 9 bottom). Carriage node
  rotates by `carriage·pitch`; result/counter digit j sits at local `slider_angle(j)`. Crank angle `crank_angle`
  grows clockwise from above (node `rotation.y = −crank_angle`), ratchet + 15° home detent (`CRANK_DETENT`);
  `crank_locked()` blocks carriage, mode, clearing and type switch. Cutaway (K): `_cut_mats` go alpha 0.16,
  `_inner` (stepped drum + pinions on square shafts) becomes visible and pickable. Drum: add rib r on levels n ≥ r,
  complement rib on n ≤ 9 − r half a step lower; drum lifts `_step/2` in subtract mode.
  Picking: `pick(screen)` = ray vs `_parts` (local AABB / vertical cylinder), body occludes `inner` parts.
  Test helpers: `part_point(id)`, `screen_of(world)`, `press_button(id)`; `_process(dt)` drives all animation.
  HUD copies lukyanov_integrator's layout and is drawn in `_draw_hud()` on one Control `_overlay`: status line
  (FS_BIG, y 44), version at `RIG_RIGHT`, one row of flat buttons from `_buttons()` at `BTN_Y` 62 (hover = lighter,
  active mode = yellow outline; wraps only if a row passes `RIG_RIGHT`), toast under the row, footer hints + yellow
  "F1" line, register panel at `PANEL_X` 1440 behind a divider ("#" lines = headers). Clicks hit buttons before 3D.
  The model is centred in the area left of the panel with an off-axis frustum (`frustum_offset`), not `h_offset`
  (that moves the eye). Godot's `project_ray_*` ignore `frustum_offset`, so rays come from `ray_dir(screen)`.
  F1 overlay (Controls) shows `docs/pages/<lang>/page_N.png`.
- `tests/run_tests.gd` — 64 checks (incl. the button row: position, hover, click, active outline) (incl. manual pages/PDFs exist, Shift+C): add/sub, 0−1, ×/÷ (counter reverse), √ by odd numbers (Toepler, sliders and
  carriage shifted by k), counter carry/borrow, type switch, CSV, 3D drags (slider, crank incl. ratchet/lock,
  hub, carriage, reverse, clearing lever), cutaway picking, pinion n/10, orbit/zoom, buttons, i18n completeness
  (scans `I18n.t("…")` in the sources). Run: `godot --headless --path . --import` then
  `godot --headless --path . -s tests/run_tests.gd`. Godot on this machine:
  `C:/Users/avv12/Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe`.
- `I18n.EN` is filled for both scenes; `icon.svg` exists (placeholder, can be improved).
- `main.tscn` (2D schematic) is kept as the abstract view.

- `docs/build_instruction.py` → `docs/instruction_{ru,en}.pdf` (15 pages, A4 landscape) + `docs/pages/<lang>/page_N.png`
  (1054 px high, shown by F1). Every text is an `L(ru, en)` pair; `FONT_K = 1.6`; font Arial, falls back to Liberation Sans.
  Example tables (add/sub, 0−1, 123×456, 123×99, 56090:123, √15129) come from `class Curta` — a Python mirror of
  `curta_model.gd` with asserts, so keep the two in sync. Sections: history, parts, stepped drum (drawn unrolled with
  reportlab.graphics), complement subtraction, controls, add/sub, multiplication, division, square root (Toepler).
  Images `docs/scheme_<lang>.png`, `docs/cutaway_<lang>.png` come from `docs/screenshot.gd`:
  `godot --path . -s docs/screenshot.gd -- --lang=ru` (with a window, not headless). After editing text or the model,
  rerun `python docs/build_instruction.py` (needs `pip install reportlab pypdfium2`), then `godot --headless --path . --import`.
- Shift+C clears only the counter (`Curta3D.clear_counter()`), needed to load a dividend/radicand.

- README.md (en + ru, screenshots `docs/scheme_<lang>.png`), `export_presets.cfg` ("Windows Desktop" →
  `build/CurtaCalculator.exe`, embed_pck, `modify_resources=false`, excludes `docs/scheme_*`, `docs/cutaway_*`,
  `docs/screenshot.gd`), `.github` copied from lukyanov_integrator (see below). Local check of the CI script:
  put a `godot` wrapper in PATH and run `bash .github/scripts/test_and_build.sh`.

## CI and releases (GitHub Actions)
- `.github/workflows/ci.yml` — on every PR and push to `main`: Godot 4.7.1 (Linux) + Windows export templates
  (`.github/actions/setup-godot`, cached), then `.github/scripts/test_and_build.sh`: import → tests →
  `--export-release "Windows Desktop"`. The test `.exe` is attached to the run as an artifact (7 days).
- `.github/workflows/release.yml` — when a PR is **merged into `main`**: bumps the version from the latest
  `vX.Y.Z` tag, writes it into `application/config/version`, re-runs tests + export, zips `CurtaCalculator.exe` +
  both PDFs + README, creates tag `vX.Y.Z` and a GitHub Release. First release (no tags) is `v0.1.0`.
### Release rules for Claude
- Never create tags or releases by hand and never edit `config/version` in `project.godot` — it stays `"dev"`.
- Work on a branch and open a PR into `main`; pick the bump with a PR label: `release:major` (CSV columns,
  scene/control renames), `release:minor` (new feature, manual section), no label = patch, `release:none`
  (docs-only/housekeeping). Say in the PR description which bump was chosen and why.
- Before opening a PR run the tests; if the manual text or the model changed, rerun `docs/build_instruction.py`
  and commit the PDFs and pages (CI does not regenerate them — it needs fonts and pip packages).

- GitHub: https://github.com/avv123avv/curt_calculator (public), labels `release:major`, `release:minor`,
  `release:none` created; releases at https://github.com/avv123avv/curt_calculator/releases.

## TODO (next session)
1. Possible polish: setting-check digits on the carriage side window, real "+1" tens-complement tooth in the drum,
   clearing-lever ratchet, Steam Deck touch check.

## Notes
- The habr article 41694 could not be fetched (rate limit); 31415 has history only (no mechanism).
