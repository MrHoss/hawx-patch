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

## Usage

```sh
./apply.sh                          # auto-detects the game under ~/Games
./apply.sh "/path/to/H A W X"       # explicit path
./apply.sh --with-depthms           # also apply the optional workaround below
./apply.sh --revert                 # undo
```

Equivalent by hand:

```sh
cd "/path/to/Tom Clancys H A W X"
patch -p1 < patches/hawx-wined3d-shader-fix.patch
```

A copy of the untouched `Data/Shaders_PC` is saved once to
`Data/Shaders_PC.hawxbackup`. The script is idempotent — re-running it is a no-op.

## Optional: `DepthMS*ToLinDepth_PS.fx`

Kept as a **separate** patch (`--with-depthms`) because it is a behaviour change,
not a compile fix.

The originals use `Texture2DMS<float, N>`, which sends vkd3d's HLSL parser into
an infinite loop in `hlsl_sm1_base_type`. The workaround replaces the four
shaders with a stub returning a constant, which disables MSAA depth
linearisation (soft particles / depth-based fades). Needed to get past the hang;
kept opt-in so it is an explicit decision.

## Known remaining incompatibilities

Found with `tools/scan.py`, not triggered at default settings:

- `asm { vfetch ... }` — `Water/Water_VS.fx`, `Water/Waves_VS.fx`,
  `Forest/forestgl*`, `Forest/ForestGLCVS.fx`, `Forest/ForestGLIVS.fx`,
  `Statics/SmoothShadowMipMap_PS.fx`. vkd3d does not implement `asm`
  (`E5030: Unknown modifier "asm"`). These back the vertex-fetch instancing path.
- `Outline/Dilate_PS.fx` — `E5017: SM4 half4 maximum expression` /
  `SM4 half dot expression`, `ps_4_0` only.
- `Terrain/FH_Terrain*_VS.fx` — `E5016: Invalid packoffset() reservation:
  Variables Instance and OneInstance overlap` (`OneInstance` and `Instance[16]`
  both bound to `c32`), `vs_4_0` only. Compiles clean for `vs_3_0`.

DXVK is unaffected by all of this — it ships its own HLSL compiler (DXC), so this
patch is only needed for the wined3d path.

## Repository layout

```
apply.sh                                     entry point
patches/hawx-wined3d-shader-fix.patch        the 49-file fix (semantics-preserving)
patches/hawx-wined3d-depthms-workaround.patch  optional, opt-in
tools/fix_wvm.py                             generator: fix #1
tools/fix_reg.py                             generator: fix #2
tools/fix_hdr.py                             generator: fix #3
tools/scan.py                                scan every .fx, report vkd3d errors
tools/verify.py                              compile specific shaders
```

`tools/*.py` are idempotent and are the source of truth for the patches; the
`.patch` files are generated from them with `diff -ruN` against a pristine copy of
`Data/Shaders_PC`.

## Credits

Diagnosed against **vkd3d 1.19** `vkd3d-compiler` (Arch `vkd3d` package), which
is the same HLSL front end Proton ships as `libvkd3d-shader-1.dll`.