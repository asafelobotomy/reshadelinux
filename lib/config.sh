# shellcheck shell=bash
# SPDX-License-Identifier: GPL-2.0-or-later

function init_runtime_config() {
    local _backend_value _backend_rc

    _has_tty=0
    [[ -t 0 && -t 1 ]] && _has_tty=1
    _backend_value=$(chooseUiBackend "$_has_tty")
    _backend_rc=$?
    [[ $_backend_rc -eq 0 ]] || return $_backend_rc
    _UI_BACKEND="$_backend_value"

    if [[ ${UI_AUTO_CONFIRM:-0} == 1 ]]; then
        printf '%bWarning: UI_AUTO_CONFIRM=1 answers every dialog automatically. It is a testing hook.%b\n' "$_YLW" "$_R" >&2
    fi

    _CURL_PROG=(--progress-bar)
    [[ $_UI_BACKEND != cli ]] && _CURL_PROG=(--silent)

    # Shared runtime globals are consumed by the main script after sourcing this file.
    # shellcheck disable=SC2034
    COMMON_OVERRIDES="d3d8 d3d9 d3d11 d3d12 ddraw dinput8 dxgi opengl32"
    EXTRA_DLL_OVERRIDES=${EXTRA_DLL_OVERRIDES:-""}
    _appendExtraDllOverrides
    # shellcheck disable=SC2034
    REQUIRED_EXECUTABLES=(7z curl file git grep python3 sed sha256sum)
    XDG_DATA_HOME=${XDG_DATA_HOME:-"$HOME/.local/share"}
    UI_BACKEND=${UI_BACKEND:-auto}

    if [[ -z ${MAIN_PATH+x} ]]; then
        local _flatpak_data="$HOME/.var/app/com.valvesoftware.Steam/.local/share"
        local _flatpak_ok=0 _native_ok=0
        [[ -d "$_flatpak_data/Steam" ]] && _flatpak_ok=1
        [[ -d "$XDG_DATA_HOME/Steam" ]] && _native_ok=1
        if [[ $_flatpak_ok -eq 1 && $_native_ok -eq 0 ]]; then
            MAIN_PATH="$_flatpak_data/reshade"
            printf '%bDetected Flatpak Steam — using Flatpak data dir for MAIN_PATH.%b\n' "$_CYN" "$_R"
        elif [[ $_flatpak_ok -eq 1 && $_native_ok -eq 1 ]]; then
            if [[ $_UI_BACKEND != cli ]]; then
                local _fpChoice
                _fpChoice=$(ui_radiolist "ReShade" \
                    "Both Flatpak and native Steam installs were detected. Which installation should ReShade target?" \
                    14 78 2 \
                    flatpak "Flatpak Steam -> $_flatpak_data/reshade" ON \
                    native "Native Steam -> $XDG_DATA_HOME/reshade" OFF) || exit 0
                [[ $_fpChoice == flatpak ]] \
                    && MAIN_PATH="$_flatpak_data/reshade" \
                    || MAIN_PATH="$XDG_DATA_HOME/reshade"
            else
                printf '%bBoth Flatpak and native Steam installs detected.%b\n' "$_YLW$_B" "$_R"
                printf '  1) Flatpak Steam  → %s/reshade\n' "$_flatpak_data"
                printf '  2) Native Steam   → %s/reshade\n' "$XDG_DATA_HOME"
                local _installChoice
                _installChoice=$(checkStdin "Which installation? (1/2): " "^(1|2)$") || exit 1
                if [[ $_installChoice == "1" ]]; then
                    MAIN_PATH="$_flatpak_data/reshade"
                else
                    MAIN_PATH="$XDG_DATA_HOME/reshade"
                fi
            fi
        else
            MAIN_PATH="$XDG_DATA_HOME/reshade"
        fi
    fi

    # shellcheck disable=SC2034
    RESHADE_PATH="$MAIN_PATH/reshade"
    UPDATE_RESHADE=${UPDATE_RESHADE:-1}
    GLOBAL_INI=${GLOBAL_INI:-"ReShade.ini"}
    LINK_PRESET=${LINK_PRESET:-""}
    DELETE_RESHADE_FILES=${DELETE_RESHADE_FILES:-0}
    FIRST_RUN_SHADER_REPOS=${FIRST_RUN_SHADER_REPOS:-"reshade-shaders,sweetfx-shaders,quintfx,prod80-shaders,astrayfx-shaders"}
    SHADER_REPOS=${SHADER_REPOS:-"\
https://github.com/crosire/reshade-shaders|reshade-shaders|slim|ReShade Shaders|Official built-ins: Deband, DisplayDepth, UIMask;\
https://github.com/CeeJayDK/SweetFX|sweetfx-shaders||SweetFX|SMAA, CAS, LumaSharpen, Technicolor, FilmGrain;\
https://github.com/crosire/reshade-shaders|reshade-shaders-legacy|legacy|Legacy Effects|AdaptiveSharpen, AmbientLight, MagicBloom, DOF, Bloom;\
https://github.com/FransBouma/OtisFX|otis-fx||OtisFX|CinematicDOF, AdaptiveFog, Emphasize, DepthHaze;\
https://github.com/BlueSkyDefender/Depth3D|depth3d-shaders||Depth3D|SuperDepth3D stereoscopic 3D and VR depth;\
https://github.com/luluco250/FXShaders|luluco250-fx||FXShaders|NeoBloom, HexLensFlare, NormalMap, ArcaneBloom;\
https://github.com/Daodan317081/reshade-shaders|daodan-shaders||Daodan Shaders|ColorIsolation, Comic outlines, AspectRatioComposition;\
https://github.com/brussell1/Shaders|brussell-shaders||Shaders by brussell|EyeAdaption, UIDetect;\
https://github.com/Fubaxiusz/fubax-shaders|fubax-shaders||Fubax Shaders|FilmicSharpen, Prism, Aspect Ratio, SimpleGrain;\
https://github.com/martymcmodding/qUINT|quintfx||qUINT|Lightroom grading, SSR, MXAO, Bloom, Deband;\
https://github.com/AlucardDH/dh-reshade-shaders|alucard-shaders||DH ReShade Shaders|DH_UBER_RT (GI + AO + SSR combined), dh_anime;\
https://github.com/Radegast-FFXIV/Warp-FX|warp-fx||Warp-FX|Swirl, TinyPlanet, ZigZag, Ripple, Wave;\
https://github.com/prod80/prod80-ReShade-Repository|prod80-shaders||prod80 ReShade Repository|Full colour-grading suite, LUTs, Bloom, Sharpening;\
https://github.com/originalnicodr/CorgiFX|corgi-fx||CorgiFX|FreezeShot, MagnifyingGlass, AspectRatioMultiGrid;\
https://github.com/LordOfLunacy/Insane-Shaders|insane-shaders||Insane Shaders|Oilify, ReVeil, ContrastStretch, BilateralComic;\
https://github.com/LordKobra/CobraFX|cobra-fx||CobraFX|Gravity, ColorSort, RealLongExposure;\
https://github.com/BlueSkyDefender/AstrayFX|astrayfx-shaders||AstrayFX|DLAA+, RadiantGI, Clarity, Smart_Sharp;\
https://github.com/akgunter/crt-royale-reshade|crt-royale||CRT-Royale-ReShade|CRT-Royale monitor emulation port from Libretro;\
https://github.com/Matsilagi/RSRetroArch|rsretroarch-shaders||RSRetroArch|Curated RetroArch CRT and retro effects;\
https://github.com/retroluxfilm/reshade-vrtoolkit|vrtoolkit||VRToolkit|VR HMD clarity and sharpness;\
https://github.com/AlexTuduran/FGFX|fgfx-shaders||FGFX|Large-scale perceptual obscurance and irradiance;\
https://github.com/papadanku/CShade|cshade||CShade|DLAA, FXAA, optical flow, motion stabilization;\
https://github.com/EndlesslyFlowering/ReShade_HDR_shaders|reshade-hdr-shaders||ReShade HDR Shaders|HDR analysis, inverse tone mapping, SDR to HDR;\
https://github.com/martymcmodding/iMMERSE|immerse-shaders||iMMERSE|SMAA, MXAO ambient occlusion, depth-aware Sharpen;\
https://github.com/vortigern11/vort_Shaders|vort-shaders||vort_Shaders|Static and Motion effects;\
https://github.com/liuxd17thu/BX-Shade|bx-shade||BX-Shade|Curve tools, 1D and 3D LUTs;\
https://github.com/IAmTreyM/SHADERDECK|shaderdeck||SHADERDECK|Film emulation, FSR1 upscaling;\
https://github.com/martymcmodding/METEOR|meteor-shaders||METEOR|ChromaticAberration, FilmGrain, Halftone, LongExposure, NVSharpen;\
https://github.com/AnastasiaGals/Ann-ReShade|ann-reshade||Ann-ReShade|Artistic effects, requires CShade|cshade;\
https://github.com/Filoppi/PumboAutoHDR|pumbo-autohdr||AdvancedAutoHDR|AutoHDR and HDR tonemapping helpers;\
https://github.com/Zenteon/ZenteonFX|zenteon-fx||ZenteonFX|TurboGI, XenonBloom, SSAO, LocalContrast;\
https://github.com/Mortalitas/GShade-Shaders|gshade-shaders||GShade-Shaders|Legacy GShade collection;\
https://github.com/PthoEastCoast/Ptho-FX|ptho-fx||Ptho-FX|DownsampleSSAA;\
https://github.com/GimleLarpes/potatoFX|potato-fx||potatoFX|HDR-compatible color and noise shaders;\
https://github.com/nullfrctl/reshade-shaders|anagrama-shaders||Anagrama Collection|Cinematic anamorphic and blur effects;\
https://github.com/MaxG2D/ReshadeSimpleHDRShaders|maxg3d-hdr-shaders||Reshade Simple HDR Shaders|HDR Bloom, MotionBlur, Saturation;\
https://github.com/BarbatosAWLS/Reshade-Shaders|barbatos-shaders||reshade-shaders by Barbatos|GI, SSR, SSAO, XeGTAO, Deband, NVSharpen;\
https://github.com/smolbbsoop/smolbbsoopshaders|smolbbsoop-shaders||smolbbsoopshaders|HDR to SDR converter, RadialBlur;\
https://github.com/yplebedev/BFBFX|bfbfx-shaders||BFBFX|RTGI and SSAO, requires ZenteonFX|zenteon-fx;\
https://github.com/outmode/rendepth-reshade|rendepth||Rendepth|Stereoscopic 2D to 3D conversion;\
https://github.com/P0NYSLAYSTATION/Scaling-Shaders|scaling-shaders||Crop and Resize|Downsample, crop and resize;\
https://github.com/umar-afzaal/LumeniteFX|lumenite-fx||LumeniteFX|RTAO, LSAO, SSR, AnamorphicBloom;\
https://github.com/JakobPCoder/Reshade-Shades|jakobpcoder-shades||Shades|TFAA temporal anti-aliasing, requires a depth buffer and iMMERSE LAUNCHPAD|immerse-shaders;\
https://github.com/vertver/verfx|verfx||verfx Shaders|Faithful NTSC and retro filters;\
https://github.com/rj200/Glamarye_Fast_Effects_for_ReShade|glamarye-fast-effects|main|Glamarye Fast Effects|Fast FXAA, AO, sharpening, DOF and fake GI in one shader;\
https://github.com/lordbean-git/reshade-shaders|lordbean-shaders|main|lordbean Shaders|Quality-focused AA and effects, requires SweetFX|sweetfx-shaders;\
https://github.com/clshortfuse/renofx|renofx||RenoFX|HDR toolkit ported from RenoDX;\
https://github.com/martymcmodding/ReShade-Optical-Flow|optical-flow||ReShade Optical Flow|Optical flow motion vectors, requires qUINT|quintfx;\
https://github.com/bituq/ZealShaders|zeal-shaders||ZealShaders|Collection of personal effects;\
https://github.com/murchalloo/murchFX|murchfx||murchFX|Assorted colour and lens effects;\
https://github.com/Zenteon/QuarkFX|quarkfx||QuarkFX|Archived ZenteonFX predecessor: 3D lighting and stylisation;\
https://github.com/WhiteMagicRaven/fakebilinear2|fakebilinear2||fakebilinear2|Fake bilinear filtering for upscaled pixel art;\
https://github.com/thatshaman/ReShadeShaders|thatshaman-shaders||shaman ReShade Shaders|Custom effects by thatshaman;\
https://github.com/KaiserThompson/Reshade-Shaders|kaiserthompson-shaders||KaiserThompson Shaders|UI detection and overall effect, requires ReShade Shaders;\
https://github.com/DespairArdor/QD-OLED-APL-FIXER|qd-oled-apl-fixer||QD-OLED APL Fixer|Emulates the EOTF Boost feature of QD-OLED monitors;\
https://github.com/Matsilagi/RSJankShaders|rsjank-shaders||RSJankShaders|Ported Shadertoy and misc effects;\
https://github.com/Matsilagi/RSUnityShaders|rsunity-shaders||RSUnityShaders|Effects ported from Unity, RetroTV;\
https://github.com/JakobPCoder/ReshadeTFAA|reshade-tfaa||ReshadeTFAA|Temporal AA add-on, requires iMMERSE LAUNCHPAD|immerse-shaders;\
https://github.com/JakobPCoder/ReshadeMotionEstimation|reshade-motion-estimation||ReshadeMotionEstimation|Motion estimation library and effect;\
https://github.com/JakobPCoder/ReshadeBUR|reshade-bur||ReshadeBUR|Bad Upscaling Replacer: better spatial upscaling with FSR1;\
https://github.com/artzox/CRT-Standalone|crt-standalone||CRT-Standalone|Full CRT signal chain with phosphors and black frame insertion;\
https://github.com/Riskdiver/CRT-Dusha|crt-dusha||CRT-Dusha|Motion-clarity CRT simulation;\
https://github.com/Zackin5/Filmic-Tonemapping-ReShade|filmic-tonemapping||Filmic Tonemapping|Gamma-correct filmic tonemapping operators;\
https://github.com/Zackin5/Misc-ReShade-Shaders|zackin5-misc-shaders||Zackin5 Misc Shaders|Night vision and thermal vision effects;\
https://github.com/guestrr/ReshadeShaders|guestrr-shaders||guestrr Shaders|CRT and scanline effects;\
https://github.com/aston89/Smart-vibrance-for-reshade|smart-vibrance||Smart Vibrance|Vibrance that spares already saturated colours;\
https://github.com/grebord/LXAA-Antialiasing-Shader|lxaa||LXAA|Efficient FXAA v3 based anti-aliasing;\
https://github.com/grebord/Fast-Adaptive-AA|fast-adaptive-aa||Fast Adaptive AA|FXAA v3 variant with a different edge detector;\
https://github.com/chuusou/DeTintX|detintx||DeTintX|Removes colour tint while preserving brightness"}
    RESHADE_VERSION=${RESHADE_VERSION:-"latest"}
    RESHADE_ADDON_SUPPORT=${RESHADE_ADDON_SUPPORT:-0}
    FORCE_RESHADE_UPDATE_CHECK=${FORCE_RESHADE_UPDATE_CHECK:-0}
    PROGRESS_UI=${PROGRESS_UI:-1}
    RESHADE_DEBUG_LOG=${RESHADE_DEBUG_LOG:-""}
    BUILTIN_SHADER_EFFECT_EXCLUDES=${BUILTIN_SHADER_EFFECT_EXCLUDES:-"306130|BX_XIV_ChromakeyPlus.fx,GrainSpread.fx,NTSCCustom.fx,NTSC_XOT.fx"}
    SHADER_EFFECT_EXCLUDES=${SHADER_EFFECT_EXCLUDES:-"$BUILTIN_SHADER_EFFECT_EXCLUDES"}
    # Packs whose headers every other pack includes (ReShade.fxh, ReShadeUI.fxh ...). They are
    # always cloned and their headers linked, but their effects only appear when selected.
    SHADER_CORE_REPOS=${SHADER_CORE_REPOS:-"reshade-shaders"}
    # Effects that fail to compile under ReShade 6.8 with the native d3dcompiler_47.dll on
    # Proton (checked by running every pack), so they are left out instead of showing an error.
    # ZenWork.fx (BFBFX) redefines OCTtoUV, which the current ZenteonFX header also defines.
    # Set it empty to keep them. Paths are relative to a pack's Shaders folder.
    SHADER_BROKEN_EFFECTS=${SHADER_BROKEN_EFFECTS-"GrainSpread.fx,NTSCCustom.fx,NTSC_XOT.fx,BX_XIV_ChromakeyPlus.fx,TrooCullers.fx,CameraFilterPack/OilPaint.fx,ZenWork.fx"}
    # shellcheck disable=SC2034
    RESHADE_URL="https://reshade.me"
    # shellcheck disable=SC2034
    RESHADE_URL_ALT="https://static.reshade.me"
    WINEPREFIX=${WINEPREFIX:-""}
    # shellcheck disable=SC2034
    BUILTIN_GAME_DIR_PRESETS="1091500|bin/x64;292030|bin/x64;275850|Binaries;1245620|Game;306130|The Elder Scrolls Online/game/client;2623190|OblivionRemastered/Binaries/Win64"
}
