# shellcheck shell=bash

function init_runtime_config() {
    local _backend_value _backend_rc

    _has_tty=0
    [[ -t 0 && -t 1 ]] && _has_tty=1
    _backend_value=$(chooseUiBackend "$_has_tty")
    _backend_rc=$?
    [[ $_backend_rc -eq 0 ]] || return $_backend_rc
    _UI_BACKEND="$_backend_value"

    _CURL_PROG=(--progress-bar)
    [[ $_UI_BACKEND != cli ]] && _CURL_PROG=(--silent)

    # Shared runtime globals are consumed by the main script after sourcing this file.
    # shellcheck disable=SC2034
    COMMON_OVERRIDES="d3d8 d3d9 d3d11 d3d12 ddraw dinput8 dxgi opengl32"
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
https://github.com/AnastasiaGals/Ann-ReShade|ann-reshade||Ann-ReShade|Artistic effects, requires CShade;\
https://github.com/Filoppi/PumboAutoHDR|pumbo-autohdr||AdvancedAutoHDR|AutoHDR and HDR tonemapping helpers;\
https://github.com/Zenteon/ZenteonFX|zenteon-fx||ZenteonFX|TurboGI, XenonBloom, SSAO, LocalContrast;\
https://github.com/Mortalitas/GShade-Shaders|gshade-shaders||GShade-Shaders|Legacy GShade collection;\
https://github.com/PthoEastCoast/Ptho-FX|ptho-fx||Ptho-FX|DownsampleSSAA;\
https://github.com/GimleLarpes/potatoFX|potato-fx||potatoFX|HDR-compatible color and noise shaders;\
https://github.com/nullfrctl/reshade-shaders|anagrama-shaders||Anagrama Collection|Cinematic anamorphic and blur effects;\
https://github.com/MaxG2D/ReshadeSimpleHDRShaders|maxg3d-hdr-shaders||Reshade Simple HDR Shaders|HDR Bloom, MotionBlur, Saturation;\
https://github.com/BarbatosBachiko/Reshade-Shaders|barbatos-shaders||reshade-shaders by Barbatos|GI, SSR, SSAO, XeGTAO, Deband, NVSharpen;\
https://github.com/smolbbsoop/smolbbsoopshaders|smolbbsoop-shaders||smolbbsoopshaders|HDR to SDR converter, RadialBlur;\
https://github.com/yplebedev/BFBFX|bfbfx-shaders||BFBFX|RTGI and SSAO, requires ZenteonFX;\
https://github.com/outmode/rendepth-reshade|rendepth||Rendepth|Stereoscopic 2D to 3D conversion;\
https://github.com/P0NYSLAYSTATION/Scaling-Shaders|scaling-shaders||Crop and Resize|Downsample, crop and resize;\
https://github.com/umar-afzaal/LumeniteFX|lumenite-fx||LumeniteFX|RTAO, LSAO, SSR, AnamorphicBloom"}
    RESHADE_VERSION=${RESHADE_VERSION:-"latest"}
    RESHADE_ADDON_SUPPORT=${RESHADE_ADDON_SUPPORT:-0}
    FORCE_RESHADE_UPDATE_CHECK=${FORCE_RESHADE_UPDATE_CHECK:-0}
    PROGRESS_UI=${PROGRESS_UI:-1}
    RESHADE_DEBUG_LOG=${RESHADE_DEBUG_LOG:-""}
    # shellcheck disable=SC2034
    RESHADE_URL="https://reshade.me"
    # shellcheck disable=SC2034
    RESHADE_URL_ALT="https://static.reshade.me"
    WINEPREFIX=${WINEPREFIX:-""}
    # shellcheck disable=SC2034
    BUILTIN_GAME_DIR_PRESETS="1091500|bin/x64;292030|bin/x64;275850|Binaries;1245620|Game;306130|The Elder Scrolls Online/game/client;2623190|OblivionRemastered/Binaries/Win64"
}
