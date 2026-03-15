# shellcheck shell=bash

function init_runtime_config() {
    _has_tty=0
    [[ -t 0 && -t 1 ]] && _has_tty=1
    _UI_BACKEND=$(chooseUiBackend "$_has_tty")

    _CURL_PROG=(--progress-bar)
    [[ $_UI_BACKEND != cli ]] && _CURL_PROG=(--silent)

    # Shared runtime globals are consumed by the main script after sourcing this file.
    # shellcheck disable=SC2034
    COMMON_OVERRIDES="d3d8 d3d9 d3d11 d3d12 ddraw dinput8 dxgi opengl32"
    # shellcheck disable=SC2034
    REQUIRED_EXECUTABLES=(7z curl file git grep sed sha256sum)
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
    local _tmp_path="${MAIN_PATH#/home/"$USER"/}"
    # shellcheck disable=SC2034
    WINE_MAIN_PATH="${_tmp_path//\//\\\\}"

    UPDATE_RESHADE=${UPDATE_RESHADE:-1}
    VULKAN_SUPPORT=${VULKAN_SUPPORT:-0}
    GLOBAL_INI=${GLOBAL_INI:-"ReShade.ini"}
    SHADER_REPOS=${SHADER_REPOS:-"https://github.com/CeeJayDK/SweetFX|sweetfx-shaders||SMAA, CAS, LumaSharpen, Technicolor, FilmGrain;https://github.com/martymcmodding/iMMERSE|immerse-shaders||SMAA, MXAO ambient occlusion, depth-aware Sharpen;https://github.com/BlueSkyDefender/AstrayFX|astrayfx-shaders||DLAA+, RadiantGI, Clarity, Smart_Sharp;https://github.com/prod80/prod80-ReShade-Repository|prod80-shaders||Full colour-grading suite, LUTs, Bloom, Sharpening;https://github.com/crosire/reshade-shaders|reshade-shaders|slim|Official built-ins: Deband, DisplayDepth, UIMask;https://github.com/Fubaxiusz/fubax-shaders|fubax-shaders||FilmicSharpen, Prism, Aspect Ratio, SimpleGrain;https://github.com/FransBouma/OtisFX|otis-fx||CinematicDOF, AdaptiveFog, Emphasize, DepthHaze;https://github.com/martymcmodding/qUINT|quintfx||Lightroom grading, SSR, MXAO, Bloom, Deband;https://github.com/LordOfLunacy/Insane-Shaders|insane-shaders||Oilify, ReVeil, ContrastStretch, BilateralComic;https://github.com/mj-ehsan/NiceGuy-Shaders|niceguy-shaders||Volumetric Fog V2, NGLighting, NiceGuy Lamps;https://github.com/Daodan317081/reshade-shaders|daodan-shaders||ColorIsolation, Comic outlines, AspectRatioComposition;https://github.com/rj200/Glamarye_Fast_Effects_for_ReShade|glamarye-fx||All-in-one FXAA + Sharpen + AO + DoF (low GPU cost);https://github.com/luluco250/FXShaders|luluco250-fx||NeoBloom, HexLensFlare, NormalMap, ArcaneBloom;https://github.com/LordKobra/CobraFX|cobra-fx||Gravity, ColorSort, RealLongExposure;https://github.com/originalnicodr/CorgiFX|corgi-fx||FreezeShot, MagnifyingGlass, AspectRatioMultiGrid;https://github.com/TheGordinho/MLUT|mlut-shaders||Multi-LUT pack: film, Instagram, cinematic presets;https://github.com/AlucardDH/dh-reshade-shaders|alucard-shaders||DH_UBER_RT (GI + AO + SSR combined), dh_anime;https://github.com/lordbean-git/reshade-shaders|lordbean-shaders||HQAA (Hybrid FXAA+SMAA), FSMAA, ASSMAA"}
    RESHADE_VERSION=${RESHADE_VERSION:-"latest"}
    RESHADE_ADDON_SUPPORT=${RESHADE_ADDON_SUPPORT:-0}
    FORCE_RESHADE_UPDATE_CHECK=${FORCE_RESHADE_UPDATE_CHECK:-0}
    # shellcheck disable=SC2034
    RESHADE_URL="https://reshade.me"
    # shellcheck disable=SC2034
    RESHADE_URL_ALT="https://static.reshade.me"
    WINEPREFIX=${WINEPREFIX:-""}
    # shellcheck disable=SC2034
    BUILTIN_GAME_DIR_PRESETS="1091500|bin/x64;292030|bin/x64;275850|Binaries;1245620|Game;306130|The Elder Scrolls Online/game/client;2623190|OblivionRemastered/Binaries/Win64"
}
