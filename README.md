# Tom Clancy's H.A.W.X. — HLSL fixes for wined3d

Makes the game (Steam/GOG, 2012) run under **wined3d** on Linux
(`PROTON_USE_WINED3D=1` for Proton, or any Wine build with vkd3d).

The game ships 638 `.fx` shaders as *plain-text HLSL* and compiles them at
runtime with `D3DCompile`, which on Linux resolves to **vkd3d-shader**.
vkd3d's HLSL compiler rejects several constructs Microsoft's `fxc` accepts, and
does so with a hard abort (`VKD3D_SHADER_ERROR_NOT_IMPLEMENTED`). The game stops
at the **first** failing shader, so one broken file blocks the whole game.

## Which folder do I point this at?

The **game folder** — the one that contains `Data/Shaders_PC`:

```
.../Tom Clancys H A W X/                                ← Steam / GOG install
.../drive_c/Program Files (x86)/DODI-Repacks/Tom Clancys H A W X/
                                                     ← inside a Wine prefix
                                                     (Heroic, Lutris, Bottles, …)
```

Not sure? Ask the filesystem:

```sh
find ~ -type d -name Shaders_PC -path '*/Data/*' 2>/dev/null
```

If that returns nothing, the game is not installed, or its files are inside a
container/flatpak — in that case point the tool at the path *inside* the
prefix, as your launcher exposes it.

## Install

```sh
./install.sh /path/to/the/game
```

That is the whole procedure. It creates `Data/Shaders_PC.hawxbackup` next to the
shaders (so you can always get the originals back) and prints `RESULT: complete`
only if every fix actually applied.

Equivalent by hand, if you prefer plain `patch`:

```sh
cd "/path/to/the/game"
patch -p1 < patches/hawx-wined3d-shader-fix.patch
patch -p1 < patches/hawx-wined3d-depthms-workaround.patch
```

If you would rather not pass a path, copy `install.sh` and `patches/` **into the
game folder** and run it with no arguments — it locates itself.

Undo:

```sh
./install.sh --revert /path/to/the/game     # back to the game as shipped
rm -rf Data/Shaders_PC && cp -a Data/Shaders_PC.hawxbackup Data/Shaders_PC
```

### Options

| option | effect |
|---|---|
| *(none)* | apply both patches (this is what you want) |
| `--no-depthms` | skip the `DepthMS*` stub — see the tradeoff below |
| `--revert` | undo |
| `-h`, `--help` | usage |

## What is fixed

| # | problem | fix | files |
|---|---|---|---|
| 1 | `E5017: Size change on the LHS` — `(float3x3)m = …` casts an **lvalue** to a smaller matrix. Legal HLSL, unimplemented in vkd3d. | explicit temporary, column by column | 29 |
| 2 | `E5017: Multiple register() reservations` — `bool bHDR : register(b0) : register(c31);` binds one variable twice. | drop the second binding | 20 |
| 3 | `bHDR` was read from `b0`, a register the engine **never writes**. The flag actually arrives as a **float** in `c31`, so the shader alternated between HDR-encoded and raw output. | rebind to `float bHDR : register(c31)` | 6 (subset of #2) |
| 4 | `DepthMS*ToLinDepth_PS.fx` uses `Texture2DMS`, whose MSAA path vkd3d cannot handle. | constant stub | 4 |

### 1. Size change on the LHS

The engine computes a view matrix in a wider `float3x4` and truncates it with a
cast on the left-hand side — the most common pattern in the game's vertex
shaders:

```hlsl
float3x4 WorldViewMat;
(float3x3)WorldViewMat = mul((float3x3)ViewMat, (float3x3)WorldMat);   // E5017
```

Replaced with an explicit temporary. Semantics are identical: in HLSL `m[i]`
indexes a **column**, so copying the three columns back reconstructs exactly the
`float3x3` sub-matrix, and the `.w` components the original left undefined are
immediately overwritten by the following three statements:

```hlsl
float3x4 WorldViewMat;
float3x3 _hawx_wvm3 = mul((float3x3)ViewMat, (float3x3)WorldMat);
WorldViewMat[0] = float4(_hawx_wvm3[0], 0.0);
WorldViewMat[1] = float4(_hawx_wvm3[1], 0.0);
WorldViewMat[2] = float4(_hawx_wvm3[2], 0.0);
```

Column 3 is never read by the consuming function, in the original either, so
leaving it untouched is faithful.

### 2. Multiple register() reservations

```hlsl
bool bHDR : register(b0) : register(c31);   // E5017 in vkd3d
```

The engine keeps the value in both a bool register and a float register for
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

`b0` is never set at all, so `bHDR` reads uninitialised state. Since

```hlsl
float3 EncodeRGB10(float3 color) { return saturate(color * HDRScale.y); }
```

an intermittently-true flag made the menu HUD alternate between HDR-encoded and
raw output — the reported *flickering*. Fix #3 therefore rebinds rather than
drops:

```hlsl
float bHDR : register(c31);
```

The 14 terrain vertex shaders also declare `bool bYFOG : register(b0) : register(c19);`.
Only binding #1 is removed there; gameplay renders correctly with that.

### 4. `DepthMS*ToLinDepth_PS.fx`

Four shaders declare `Texture2DMS<float, N>`, the MSAA path. The workaround
replaces them with a stub returning a constant.

**Tradeoff:** this disables MSAA depth linearisation, so soft particles and
depth-based fades are gone. It is kept as a separate patch because it is a
behaviour change rather than a compile fix. Without it the game clears the intro
logos and then hangs on a black screen before the trailer; with it, it reaches
the menu. `--no-depthms` exists for people who would rather not lose the effect
and accept the hang.

## Every part of this is load-bearing

Verified by bisecting **subtractively** on a real install, starting from the full
patch and removing one group at a time. Each missing group has its own distinct
symptom, so nothing masks anything else:

| full patch minus… | symptom |
|---|---|
| — | correct: menu and gameplay both clean |
| fix #1 | `E5017: Size change on the LHS` compile error |
| fix #2 | black rectangle in the gameplay view |
| `DepthMS` stub | hangs on a black screen before the trailer |
| fix #3 | menu elements flicker bright/dark |

There is no smaller set: **all 53 files are needed.**

An earlier *additive* pass was much less informative and is worth not
repeating: fix #1 alone behaved exactly like the untouched game, because the
`DepthMS` hang masks everything upstream of it. Each group only becomes visible
once the ones below it are present.

Note that #2 and #3 overlap: in the 6 HUD shaders #3 rewrites the whole
declaration, so it subsumes #2 there. That does not shrink the patch — the other
14 files still need #2 on its own.

## Known remaining incompatibilities

After the patch, 7 non-fatal errors remain. None of them stop the game:

- `PostProcess/HDRDOFPPMissilePS.fx` — `E5015 space 115`. Declares
  `sampler2D NoiseTexture : register(s8)` and `ScanLineTexture : register(s9)`,
  colliding with `SceneAlphaMask : register(t8)` / `RainDistmask : register(t9)`
  from `PostProcess/HDRCommon.h`. In SM4 a `sampler2D` occupies both a texture
  and a sampler slot, so the two collide.
- `Statics/SmoothShadow*_VS.fx` (4 files) — `E5013 INDEX`. They use
  `SV_VertexID`, which only compiles for `vs_4_0` (+`dxbc-tpf`), but the engine
  asks for `vs_3_0`. `TEXCOORD0`/`COLOR0` do compile for `vs_3_0`, but the
  engine's vertex-declaration mapping for them is unknown, so rewriting it
  guesses and risks wrong geometry.
- `Statics/SmoothShadowMipMap_PS.fx` — `E5030: Unknown modifier "asm"` plus
  `E5000`. Uses `asm { tfetch2D … }` for four point samples and a max; an HLSL
  rewrite needs the texel size, which PS SM3 does not expose.

Each needs knowledge of the engine's actual binding (vertex semantics,
texture/sampler allocation, texel size) to fix safely, so they are left alone
rather than patched blind.

## Version notes

Measured against vkd3d-shader **1.18** (GE-Proton10-27, Proton 10.0) and
**2.0** (Proton-CachyOS):

- vkd3d 2.0 compiles all 638 shaders **without** this patch — and then the game
  hangs on a black screen anyway. So the patch is not only a compile-error
  workaround; something in it also fixes the hang.
- Proton 10.0 launched **without** `PROTON_USE_WINED3D` still routes the game's
  `D3DCompile` through Wine's `d3dcompiler_47` → vkd3d-shader and produces the
  same errors. The patch is needed on that path too.
- DXVK is unaffected by all of this — it ships its own HLSL compiler (DXC).

## Reusing the generators

`tools/fix_*.py` produced the patches and are the source of truth for them. They
take the shader directory explicitly and are dry-run unless `--apply` is given:

```sh
python3 tools/fix_wvm.py /path/to/Data/Shaders_PC        # dry-run
python3 tools/fix_wvm.py --apply /path/to/Data/Shaders_PC # write
```

| file | role |
|---|---|
| `install.sh` | the entry point |
| `patches/hawx-wined3d-shader-fix.patch` | fixes #1+#2+#3, 49 files, semantics-preserving |
| `patches/hawx-wined3d-depthms-workaround.patch` | `DepthMS` stubs, 4 files, opt-in |
| `tools/fix_wvm.py` | generator for #1 |
| `tools/fix_reg.py` | generator for #2 |
| `tools/fix_hdr.py` | generator for #3 |
| `tools/manifest.sh` | sha256 of every `.fx`/`.h`, sorted by path |
| `tools/diffprefix.sh` | compare two shader trees |

The `.patch` files were generated from the `fix_*.py` with `diff -ruN` against
a pristine copy of `Data/Shaders_PC`.

## Credits

Diagnosed against vkd3d-shader `vkd3d-compiler`, the same HLSL front end Proton
ships as `libvkd3d-shader-1.dll`.