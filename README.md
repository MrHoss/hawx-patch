# Tom Clancy's H.A.W.X. — HLSL fixes for wined3d/vkd3d

Makes the game (Steam/GOG, 2012) run under **wined3d** (`PROTON_USE_WINED3D=1`) on
Linux. The game ships 638 `.fx` shaders as *plain-text HLSL* and compiles them at
runtime with `D3DCompile`, which on Proton resolves to **vkd3d-shader**.

vkd3d's HLSL compiler rejects several constructs that Microsoft's `fxc` accepts,
and it does so with a hard abort (`VKD3D_SHADER_ERROR_NOT_IMPLEMENTED`). The game
stops at the **first** failing shader, so one broken file blocks the whole game.

## Symptom

A full-screen black panel with a compiler error, e.g.

```
<anonymous>:28:3: E5017: Aborting due to not yet implemented feature:
Size change on the LHS.
```

`<anonymous>` means the engine compiles the source without passing a filename.

## What is fixed

| # | vkd3d error | Root cause | Files |
|---|---|---|---|
| 1 | `E5017: Size change on the LHS` | `(float3x3)m = ...` — casting an **lvalue** to a smaller matrix. Legal in HLSL, unimplemented in vkd3d. | 29 |
| 2 | `E5017: Multiple register() reservations` | `bool bHDR : register(b0) : register(c31);` — two bindings for one variable. | 20 |
| 3 | *(compiles, but wrong)* | `bHDR` bound to `b0`, a register the engine **never writes**. The HDR flag actually arrives as a **float** in `c31`. Causes the menu to flicker bright/dark. | 6 (subset of #2) |

### 1. Size change on the LHS

The engine computes a view matrix in a wider `float3x4` and then truncates it
with a cast on the left-hand side — this is the single most common pattern in the
game's vertex shaders:

```hlsl
float3x4 WorldViewMat;
(float3x3)WorldViewMat = mul((float3x3)ViewMat, (float3x3)WorldMat);   // E5017
```

Replaced with an explicit temporary. Semantics are identical: in HLSL `m[i]`
indexes a **column**, so copying the three columns back reconstructs exactly the
`float3x3` sub-matrix, and the `.w` components that the original left undefined are
immediately overwritten by the following three statements:

```hlsl
float3x4 WorldViewMat;
float3x3 _hawx_wvm3 = mul((float3x3)ViewMat, (float3x3)WorldMat);
WorldViewMat[0] = float4(_hawx_wvm3[0], 0.0);
WorldViewMat[1] = float4(_hawx_wvm3[1], 0.0);
WorldViewMat[2] = float4(_hawx_wvm3[2], 0.0);
```

Column 3 (`WorldViewMat[3]`) is never read by the consuming function, in the
original either, so leaving it untouched is faithful.

### 2. Multiple register() reservations

```hlsl
bool bHDR : register(b0) : register(c31);   // E5017 in vkd3d
```

The engine keeps the value in **both** a bool register and a float register for
legacy reasons. See `Statics/Utils/BooleanDamage_Util.fx`, where the original
author did exactly this by hand:

```hlsl
// bool	CromaKey : register(b0) : register(c31);
  float	CromaKey : register(c31);	// [reliade]
```

The second binding is dropped, keeping the first.

### 3. `bHDR` reads the wrong register

A `WINEDEBUG=+d3d9` trace of the running game settles which one is live:

```
1664x  d3d9_device_SetPixelShaderConstantF  reg_idx 31   (c31)
   0x  d3d9_device_SetBoolConstant                    (b0 is NEVER written)
```

So the flag is a float in `c31`, and `b0` is never set at all — leaving `bHDR`
reading uninitialised state. Since

```hlsl
float3 EncodeRGB10(float3 color) { return saturate(color * HDRScale.y); }
```

an intermittently-true flag made the menu HUD alternate between HDR-encoded and
raw output: the reported *flickering*. Fix #3 therefore rebinds rather than
drops:

```hlsl
float bHDR : register(c31);
```

The 14 terrain vertex shaders also declare `bool bYFOG : register(b0) : register(c19);`.
Only binding #1 is removed there — a trace does not show `c19` being written, but
it does not cover gameplay either, so there is no evidence to act on. If height
fog looks wrong, that is the line to change.

## Every part of this is load-bearing

Bisected **subtractively** on a real prefix, starting from the full patch and
removing one group at a time. Each missing group produces its own distinct
symptom, so nothing masks anything else:

| full patch minus… | missing | symptom |
|---|---|---|
| — | nothing | correct: menu and gameplay both clean |
| `wvm` | #1 | `E5017: Size change on the LHS` compile error |
| `reg` | #2 | black rectangle in the gameplay view |
| `depth` | DepthMS | hangs on a black screen before the trailer |
| `hdr` | #3 | menu elements flicker bright/dark |

There is no smaller set: **all 53 files are needed.**

An earlier *additive* pass was much less informative and is worth not repeating:
`wvm` alone behaved exactly like the pristine tree, because the trailer hang is
caused by the DepthMS shaders and masks everything upstream of it. Each group
only becomes visible once the ones below it are present.

Note that #2 and #3 overlap: in the 6 HUD shaders #3 rewrites the whole
declaration, so it subsumes #2 there. That does not shrink the patch — the other
14 files still need #2 on its own.

`tools/variant.sh` mounts any subset for a bisect round:

```sh
./tools/variant.sh wvm+depth      # full minus reg and hdr
./tools/variant.sh pristine        # untouched
```

It always rebuilds from a pristine copy, so rounds cannot contaminate each other.

## Usage

```sh
./apply.sh                          # auto-detects the game under ~/Games
./apply.sh "/path/to/H A W X"       # explicit path
./apply.sh --with-depthms           # also apply the DepthMS stub below
./apply.sh --revert                 # undo
```

After applying, `apply.sh` reverse-dry-runs both patches and **exits 1** if either
is not fully applied. This matters: `patch --forward` reports "already applied"
even when the context does not match because the tree was already *partially*
fixed, which silently ships half a patch. On a partial tree, restore first:

```sh
cd "/path/to/Tom Clancys H A W X"
rm -rf Data/Shaders_PC && cp -a Data/Shaders_PC.hawxbackup Data/Shaders_PC
```

Equivalent by hand:

```sh
cd "/path/to/Tom Clancys H A W X"
patch -p1 < patches/hawx-wined3d-shader-fix.patch
```

A copy of the untouched `Data/Shaders_PC` is saved once to
`Data/Shaders_PC.hawxbackup`. The script is idempotent — re-running it is a no-op.

## `DepthMS*ToLinDepth_PS.fx`

Kept as a **separate** patch (`--with-depthms`) because it is a behaviour change,
not a compile fix.

The originals declare `Texture2DMS<float, N>`, which vkd3d-shader's HLSL parser
cannot handle. The workaround replaces the four shaders with a stub returning a
constant, which disables MSAA depth linearisation (soft particles / depth-based
fades).

Measured behaviour: without the stub the game clears the intro logos and then
hangs on a black screen before the trailer; with it, it reaches the menu. Since
this trades away soft particles, it stays opt-in rather than being folded into the
main patch.

## Known remaining incompatibilities

After the patch, 7 non-fatal errors remain (from `tools/scan.py`). None of them
stop the game — it reaches the menu and plays:

- `PostProcess/HDRDOFPPMissilePS.fx` — `E5015 space 115`. Declares
  `sampler2D NoiseTexture : register(s8)` and `ScanLineTexture : register(s9)`,
  colliding with `SceneAlphaMask : register(t8)` / `RainDistmask : register(t9)`
  from `PostProcess/HDRCommon.h`. In SM4 a `sampler2D` occupies both a texture and
  a sampler slot, so the two collide.
- `Statics/SmoothShadow*_VS.fx` (4 files) — `E5013 INDEX`. They use
  `SV_VertexID`, which only compiles for `vs_4_0` (+`dxbc-tpf`), but the engine
  asks for `vs_3_0`. `TEXCOORD0`/`COLOR0` do compile for `vs_3_0`, but the
  engine's vertex-declaration mapping for them is unknown, so rewriting it is a
  guess that risks wrong geometry.
- `Statics/SmoothShadowMipMap_PS.fx` — `E5030: Unknown modifier "asm"` plus
  `E5000`. Uses `asm { tfetch2D ... }` for four point samples and a max. A HLSL
  rewrite needs the texel size, which PS SM3 does not expose.

Each of these needs knowledge of the engine's actual binding (vertex semantics,
texture/sampler allocation, texel size) to fix safely, so they are left alone
rather than patched blind.

## Runtime notes

Measured on GE-Proton10-27 / Proton 10.0 (vkd3d-shader **1.18**) and
Proton-CachyOS (vkd3d-shader **2.0**):

- CachyOS's vkd3d 2.0 compiles all 638 shaders **without** this patch — and then
  the game hangs on a black screen anyway. So the patch is not only a
  compile-error workaround; something in it also fixes the hang.
- Proton 10.0 launched **without** `PROTON_USE_WINED3D` still routes the game's
  `D3DCompile` through Wine's `d3dcompiler_47` → vkd3d-shader, producing the same
  errors. The patch is needed on that path too.
- `1280x720` does exist as a mode under XWayland, so it is not a resolution
  problem.

## Running it on another machine

Nothing here is tied to a particular install. `apply.sh` finds the game in this
order, and you can stop at whichever suits you:

```sh
./apply.sh --with-depthms                    # autodetect
./apply.sh --with-depthms "/path/to/H A W X" # explicit path (game root)
./apply.sh --with-depthms "/path/to/Shaders_PC"
HAXW_GAME_DIR="/path/to/H A W X" ./apply.sh --with-depthms
```

If you would rather not pass anything, copy `apply.sh` and `patches/` **into the
game folder** — it locates itself from there (`<game>/hawx-patch/apply.sh` also
works, as does running it from `<game>/Data/Shaders_PC`). Autodetection searches
`~/Games`, `~/Games/Heroic/Prefixes`, `~/GOG Games`, the Steam common folder,
`/mnt`, `/media` and `/run/media/$USER`.

`tools/fix_*.py` take the same treatment: `HAWX_GAME_DIR`, or a positional
`dir_Shaders_PC`, and they fail loudly instead of doing nothing when the
directory is missing.

### Heroic pre-launch hook

`heroic-hook.sh` re-applies the patch before every launch, which is what you want
after a reinstall wipes the shaders. Point Heroic's per-game "before launch
script" at it, then set `GAME_DIR` near the top to your game path.

The hook deliberately does **not** rely on autodetection: with two installs
present it would pick the alphabetically first one, patch that (already patched,
so "fine"), and leave the real one broken without a word.

Two bugs it had before, both silent:

- its private copy of `fix_hdr.py` only matched `float bHDR`, but `fix_reg.py`
  rewrites the declaration to `bool bHDR : register(b0)` first — so after a
  reinstall `hdr` was skipped and the menu flickered again, with output sent to
  `/dev/null`;
- it looked for settings under `users/daniel/Documents`, but the prefix's user
  is `steamuser`, so the resolution fix never applied either. It now derives the
  prefix root from `GAME_DIR` and searches.

Both are fixed by delegating to `apply.sh`, which verifies the result and exits
non-zero if any fix did not stick.

## Repository layout

```
apply.sh                                     entry point
heroic-hook.sh                               re-apply before each Heroic launch
patches/hawx-wined3d-shader-fix.patch        fixes #1+#2+#3 (49 files, semantics-preserving)
patches/hawx-wined3d-depthms-workaround.patch  DepthMS stubs (4 files, opt-in)
tools/fix_wvm.py                             generator: fix #1
tools/fix_reg.py                             generator: fix #2
tools/fix_hdr.py                             generator: fix #3
tools/scan.py                                scan every .fx, report vkd3d errors
tools/verify.py                              compile specific shaders
tools/manifest.sh                            sha256 of every .fx/.h, sorted by path
tools/diffprefix.sh                          compare two shader trees
tools/postinstall.sh                         one-shot setup for a fresh prefix
tools/verifyrun.sh                           launch the game, report Proton + vkd3d errors
tools/variant.sh                            mount any subset of fixes, for a bisect round
tools/shaderab.sh                           swap in a reference shader tree, restore on exit
tools/flicker.sh, tools/ymean.py             mean window brightness (Wayland/XWayland)
```

`tools/*.py` are idempotent and are the source of truth for the patches; the
`.patch` files are generated from them with `diff -ruN` against a pristine copy of
`Data/Shaders_PC`. The generators take an optional `dir_Shaders_PC` argument and
default to dry-run; pass `--apply` to write.

**Note on automatic bisecting:** `tools/bisect.sh` and the brightness-based
verdict in `verifyrun.sh` are *not* trustworthy here. Launched from a plain shell
rather than through Heroic, they classified a configuration that is known to work
as "hung". Use them for logs, not for verdicts — judge shader changes by
launching from Heroic.

## Credits

Diagnosed against vkd3d-shader **1.18** and **2.0** `vkd3d-compiler`, the same
HLSL front end Proton ships as `libvkd3d-shader-1.dll`.