# Shader packs in a real game

Whether the shaders the installer links actually load and compile in a Proton game. This is the one
area no stub can check: a merged folder can look right and still fail to compile in ReShade.

**Auto:** `scripts/diagnostics/compile_check.sh` runs the real ReShade under GE-Proton over any packs
and reports each effect that fails. Run it first (`--packs all` takes 5 to 15 minutes), then spot-check
in a real game with the items below.

## Automated compile check

- [ ] **SHADER-01 P0** `compile_check.sh --packs all --software` ends with `COMPILE_CHECK_RESULT=PASS`: every
  effect compiled, none failed, none unreported. (Use `--software` on GPUs where DXVK does not start.)
- [ ] **SHADER-02 P1** `compile_check.sh --packs <new pack>` passes for every pack added to the registry
  since the last release. Adding a pack is a review event: read its licence and file list too.
- [ ] **SHADER-03 P1** `compile_check.sh --packs luluco250-fx --include-broken` reports `GrainSpread.fx` as
  an expected failure; an effect reported as `NOW COMPILES` is removed from `SHADER_BROKEN_EFFECTS`.

## In the game (Proton)

Install with the default first-run packs, apply the launch option from the completion dialog, and start
the game.

- [ ] **SHADER-10 P0** The ReShade banner appears ("ReShade 6.x ... Press 'Home' to start the tutorial")
  and Home opens the overlay.
- [ ] **SHADER-11 P0** In the overlay's Home tab the effect list is populated and no effect shows a red error
  after Reload (Ctrl+Shift+Backspace or the Reload button).
- [ ] **SHADER-12 P0** Effects that live in **sub-folders** are listed (for example SweetFX's `LumaSharpen`,
  which sits in `Shaders/SweetFX/`). The paths in Settings end in `\**`.
- [ ] **SHADER-13 P0** Enabling one effect from each installed pack changes the picture and shows no compile
  error. Note any that fail, with the log at `ReShade.log` next to the game executable.
- [ ] **SHADER-14 P1** A texture-based effect (a LUT from prod80, or a CRT pack) finds its texture.
- [ ] **SHADER-15 P1** Depth-based effects (MXAO, RTGI) work after setting the depth buffer, in a DX11 and a DX9
  game.
- [ ] **SHADER-16 P1** `ReShade.log` contains no "could not open included file".

## Packs that need other packs

- [ ] **SHADER-20 P0** Selecting only a small pack (for example `detintx`) still compiles: the core headers
  (`ReShade.fxh`, `ReShadeUI.fxh`) are present in the merged folder.
- [ ] **SHADER-21 P0** Selecting Ann-ReShade also brings CShade; BFBFX brings ZenteonFX; ReshadeTFAA and Shades
  bring iMMERSE (the LAUNCHPAD effect); Optical Flow brings qUINT; lordbean Shaders bring SweetFX. They
  are cloned and merged without appearing ticked in the picker.
- [ ] **SHADER-22 P1** Two packs that ship different copies of one header (BFBFX and ZenteonFX, RSUnity and
  GShade) print "Warning: NAME ships its own FILE ... the first copy is used". Both packs still load.
- [ ] **SHADER-23 P1** Effects known not to compile (`SHADER_BROKEN_EFFECTS`) are absent from the effect list,
  with a "Skipping effect that fails to compile" line in the install output.

## Different APIs and DLLs

- [ ] **SHADER-30 P0** DX11 game with `dxgi.dll` works. **P0** DX9 game with `d3d9.dll` works.
- [ ] **SHADER-31 P1** DX12 game with `dxgi.dll` (ReShade's DX12 path) and an OpenGL game with `opengl32.dll`.
- [ ] **SHADER-32 P1** 32-bit games get `ReShade32.dll` and the 32-bit `d3dcompiler_47.dll`.
- [ ] **SHADER-33 P2** A game launched through another prefix tool (Lutris, Bottles) with `WINEDLLOVERRIDES` set
  by hand.

## After changes

- [ ] **SHADER-40 P1** Update a pack (`UPDATE_RESHADE=1`) and confirm the game still loads its shaders; a pack whose
  upstream history was rewritten recovers without losing local work.
- [ ] **SHADER-41 P1** Remove a pack from the selection and confirm its effects disappear after a reinstall.
- [ ] **SHADER-42 P2** `External_shaders/` files you added are merged and survive updates.
