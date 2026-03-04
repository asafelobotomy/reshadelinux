#!/bin/bash
cat > /dev/null <<LICENSE
    Copyright (C) 2021-2022  kevinlekiller

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
    https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html
LICENSE
cat > /dev/null <<DESCRIPTION
    Bash script to download ReShade and ReShade shaders then links them to a game directory for games using Wine or Proton on Linux.
    By linking, re-running this script will update ReShade / shaders for all games.

    Requirements:
        grep   : Used in various parts of the script.
        7z     : Used to extract exe files
        curl   : Used to download files.
        git    : Used to clone ReShade shader repositories.
        wine   : Only used if the game uses Vulkan (to insert Windows Registry entries).

    Notes:
        Vulkan / ReShade currently is not functional under wine.
        It might become possible in the future, so this information is provided in the event that happens.
        See https://github.com/kevinlekiller/reshade-steam-proton/issues/6
            Vulkan games like Doom (2016) : When asked if the game uses the Vulkan API, type y.
            Tell the script if the executable is 32 bit or 64 bit (by using the file command on the exe file or check on https://www.pcgamingwiki.com)
            Provide the WINEPREFIX to the script, for Steam games, the WINEPREFIX's folder name is the App ID and is stored in ~/.local/share/Steam/steamapps/compatdata/
            For example, on Doom (2016) on Steam, the WINEPREFIX is ~/.local/share/Steam/steamapps/compatdata/379720

        OpenGL games require the dll to be named opengl32.dll (Wolfenstein: The New Order for example).
        You will want to respond 'n' when asked for automatic detection of the dll.
        Then you will write 'opengl32' when asked for the name of the dll to override.
        You can check on pcgamingwiki.com to see what graphic API the game uses.

        Some 32 bit games use Direct3D 11 (Leisure Suit Larry: Wet Dreams Don't Dry for example),
         you'll have to manually specify the architecture (32) and DLL name (dxgi).

        Adding shader files not in a repository to the Merged/Shaders folder:
            For example, if we want to add this shader (CMAA2.fx) https://gist.github.com/kevinlekiller/cbb663e14b0f6ad6391a0062351a31a2
            Create the External_shaders folder inside the MAIN_PATH folder (by default $HOME/.local/share/reshade)
            Add the shader to it: cd "$HOME/.local/share/reshade/External_shaders" && curl -LO https://gist.github.com/kevinlekiller/cbb663e14b0f6ad6391a0062351a31a2/raw/CMAA2.fx
            Run this script, the shader will then be linked to the Merged folder.

        When you enable shaders in Reshade, this is a rough ideal order of shaders :
            color -> contrast/brightness/gamma -> anti-aliasing -> sharpening -> film grain

    Usage:
        Download the script
            Using curl:
                curl -LO https://github.com/kevinlekiller/reshade-steam-proton/raw/main/reshade-linux.sh
            Using git:
                git clone https://github.com/kevinlekiller/reshade-steam-proton
                cd reshade-steam-proton
        Make it executable:
            chmod u+x reshade-linux.sh
        Run it:
            ./reshade-linux.sh

        Installing ReShade for a DirectX / OpenGL game:
            Example on Back To The Future Episode 1:

                Find the game directory where the .exe file is.
                    If using Steam, you can open the Steam client, right click the game, click Properties,
                    click Local Files, clicking Browse, find the directory with the main
                    exe file, copy it, supply it to the script.

                    Or you can run : find ~/.local/share/Steam/steamapps/common -iregex ".*Back to the future.*.exe$"
                    We see BackToTheFuture101.exe is in "/home/kevin/.local/share/Steam/steamapps/common/Back to the Future Ep 1/"

                Run this script: ./reshade-linux.sh

                Type n when asked if the game uses the Vulkan API.

                Type i to install ReShade.
                    If you have never run this script, the shaders and ReShade will be downloaded.

                Supply the game directory where exe file is, when asked:
                    /home/kevin/.local/share/Steam/steamapps/common/Back to the Future Ep 1

                Select if you want it to automatically detect the correct dll file for ReShade or
                  to manually specity it.

                Set the WINEDLLOVERRIDES environment variable as instructed.

                Run the game, set the Effects and Textures search paths in the ReShade settings if required.

        Uninstalling ReShade for a DirectX /OpenGL game:
            Run this script: ./reshade-linux.sh

            Type n when asked if the game uses the Vulkan API.

            Type u to uninstall ReShade.

            Supply the game path where the .exe file is (see instructions above).

        Installing ReShade for a Vulkan game:
            Example on Doom (2016) on Steam:

                Run this script ./reshade-linux.sh

                When asked if the game is using the Vulkan API, type y

                Supply the WINEPREFIX:
                To find the WINEPREFIX for Doom on Steam, do a search on https://steamdb.info for Doom : https://steamdb.info/app/379720/
                We see the App ID listed there as 379720, we can now search for the folder: find ~/.local/share/Steam -wholename *compatdata/379720
                    /home/kevin/.local/share/Steam/steamapps/compatdata/379720

                Supply the exe architecture (32 or 64 bits):
                To find the exe architecture for the game, we can run: file ~/.local/share/Steam/steamapps/common/DOOM/DOOMx64vk.exe
                    /home/kevin/.local/share/Steam/steamapps/common/DOOM/DOOMx64vk.exe: PE32+ executable (GUI) x86-64, for MS Windows
                x86-64 is 64 bits, Intel 80386 would be 32 bits.

                Type i when asked if you want to install ReShade.

        Uninstall ReShade for a Vulkan game:
                Run this script ./reshade-linux.sh

                Type y when asked if the game is using the Vulkan API.

                Supply the WINEPREFIX location and the exe architecture.

                Type u to uninstall ReShade.

        Removing ReShade / shader files:
            By default the files are stored in $HOME/.local/share/reshade
            Run: rm -rf "$HOME/.local/share/reshade"

    Environment Variables:
        UPDATE_RESHADE
            To skip checking for ReShade and shader updates, set UPDATE_RESHADE=0
            ex.: UPDATE_RESHADE=0 ./reshade-linux.sh

        MAIN_PATH
            By default, this script stores all its files, including ReShade and the shaders in XDG_DATA_HOME/reshade ($HOME/.local/share/reshade)
            You can override this by setting the MAIN_PATH variable.
            ex.: MAIN_PATH=~/Documents/reshade ./reshade-linux.sh

        SHADER_REPOS
            List of git repo URI's to clone or update which contain reshade shaders.
            By default this is set to :
                https://github.com/CeeJayDK/SweetFX|sweetfx-shaders;https://github.com/martymcmodding/qUINT|martymc-shaders;https://github.com/BlueSkyDefender/AstrayFX|astrayfx-shaders;https://github.com/prod80/prod80-ReShade-Repository|prod80-shaders;https://github.com/crosire/reshade-shaders|reshade-shaders|slim
            The format is (the branch is optional) : URI|local_repo_name|branch
            Use ; to separate multiple repos. For example: URI1|local_repo_name_1|master;URI2|local_repo_name_2

        MERGE_SHADERS
            If you're using multiple shader repositories, all the unique shaders will be put into one folder called Merged.
            For example, if you use reshade-shaders and sweetfx-shaders, both have ASCII.fx,
              by enabling MERGE_SHADERS, only 1 ASCII.fx is put into the Merged folder.
            The order of priority for shaders is taken from SHADER_REPOS.
            The default is MERGE_SHADERS=1
            To disable, set MERGE_SHADERS=0

        REBUILD_MERGE
            Set to REBUILD_MERGE to 1 to rebuild the MERGE_SHADERS folder.
            This is useful if you have changed SHADER_REPOS
            ex.: REBUILD_MERGE=1 SHADER_REPOS="https://github.com/martymcmodding/qUINT|martymc-shaders" ./reshade-linux.sh

        GLOBAL_INI
            With the default, GLOBAL_INI=1, the script will create a ReShade.ini file and store it
              in MAIN_PATH folder if it does not exist.
            The script will link this ReShade.ini file to the game's path.
            If you have disabled MERGE_SHADERS, you will need to manually edit the paths by editing
              this ReShade.ini file. Alternatively, when ReShade launches, you can change the paths in the GUI.
            You can disable GLOBAL_INI with : GLOBAL_INI=0
            Disabling GLOBAL_INI will cause ReShade to create a ReShade.ini file when the game starts,
              you will then need to manually configure ReShade when the game starts.
            You can also use a different ReShade.ini than the one that is created by this script,
              put it in the MAIN_PATH folder, then set GLOBAL_INI to the name of the
              file, for example : GLOBAL_INI="ReShade2.ini" ./reshade-linux.sh

        LINK_PRESET
            Link a ReShade preset file to the game's directory.
            Put the preset file in the MAIN_PATH, then run the script with LINK_PRESET set to the name of the file.
            ex.: LINK_PRESET=ReShadePreset.ini ./reshade-linux.sh

        RESHADE_VERSION
            To use a version of ReShade other than the newest version.
            If the version does not exist, the script will exit.
            The default is RESHADE_VERSION="latest"
            ex.: RESHADE_VERSION="4.9.1" ./reshade-linux.sh

        FORCE_RESHADE_UPDATE_CHECK
            By default the script will only check for updates if the script hasn't been run in more than 4 hours.
            This will bypass the 4 hours.
            ex.: FORCE_RESHADE_UPDATE_CHECK=1 ./reshade-linux.sh

        RESHADE_ADDON_SUPPORT
            This will download ReShade with addon support, it's only intended for single player games,
             since anti-cheat software might detect it as malicious.
            ex.: RESHADE_ADDON_SUPPORT=1 ./reshade-linux.sh

        DELETE_RESHADE_FILES
            When uninstalling ReShade for game, if DELETE_RESHADE_FILES is set to 1, ReShade.log and ReShadePreset.ini will be deleted.
            Disabled by default.
            ex.: DELETE_RESHADE_FILES=1 ./reshade-linux.sh

        VULKAN_SUPPORT
            As noted below, Vulkan / ReShade is not currently functional under wine.
            The script contains a function to enable ReShade under Vulkan, although it's disabled
            by default since it's currently not functional, you can enable this function by
            passing VULKAN_SUPPORT=1
            ex.: VULKAN_SUPPORT=1 ./reshade-linux.sh

        WINEPREFIX
            Since ReShade 6.5+, d3dcompiler_47.dll must also be present in the game's Wine/Proton
            prefix (drive_c/windows/system32 for 64-bit games, or syswow64 for 32-bit games),
            not only in the game folder. Without this, ReShade shaders will fail to compile.
            Set WINEPREFIX to the path of the Wine/Proton prefix for the game to have this script
            install d3dcompiler_47.dll there automatically.
            For Steam games with Proton, the prefix is typically found at:
            ~/.local/share/Steam/steamapps/compatdata/<AppID>/pfx
            You can find your game's AppID on https://steamdb.info
            ex.: WINEPREFIX="$HOME/.local/share/Steam/steamapps/compatdata/12345/pfx" ./reshade-linux.sh
DESCRIPTION

# Print error and exit
# $1 is message
# $2 is exit code
function printErr() {
    removeTempDir
    echo -e "\e[40m\e[31mError: $1\nExiting.\e[0m"
    [[ -z $2 ]] && exit 1 || exit "$2"
}

# Check user input
# $1 is valid values to display to user
# $2 is regex
function checkStdin() {
    while true; do
        read -rp "$1" userInput
        if [[ $userInput =~ $2 ]]; then
            break
        fi
    done
    echo "$userInput"
}

# Try to get game directory from user.
function getGamePath() {
    echo 'Supply the folder path where the main executable (exe file) for the game is.'
    echo '(Control+c to exit)'
    while true; do
        read -rp 'Game path: ' gamePath
        # Expand leading ~ without using eval (safe tilde expansion).
        gamePath="${gamePath/#\~/$HOME}"
        gamePath=$(realpath "$gamePath" 2>/dev/null)
        [[ -f $gamePath ]] && gamePath=$(dirname "$gamePath")
        if [[ -z $gamePath || ! -d $gamePath ]]; then
            echo "Incorrect or empty path supplied. You supplied \"$gamePath\"."
            continue
        fi
        if ! compgen -G "$gamePath/*.exe" &>/dev/null; then
            echo "No .exe file found in \"$gamePath\"."
            echo "Do you still want to use this directory?"
            [[ $(checkStdin "(y/n) " "^(y|n)$") != "y" ]] && continue
        fi
        echo "Is this path correct? \"$gamePath\""
        [[ $(checkStdin "(y/n) " "^(y|n)$") == "y" ]] && break
    done
}

# Remove / create temporary directory.
function createTempDir() {
    tmpDir=$(mktemp -d)
    cd "$tmpDir" || printErr "Failed to create temp directory."
}
function removeTempDir() {
    cd "$MAIN_PATH" || exit
    [[ -d $tmpDir ]] && rm -rf "$tmpDir"
}

# Downloads d3dcompiler_47.dll files.
# Sources from mozilla/fxc2 GitHub, same source used by Winetricks.
function downloadD3dcompiler_47() {
    ! [[ $1 =~ ^(32|64)$ ]] && printErr "(downloadD3dcompiler_47): Wrong system architecture."
    [[ -f $MAIN_PATH/d3dcompiler_47.dll.$1 ]] && return
    echo "Downloading d3dcompiler_47.dll for $1 bits."
    createTempDir
    if [[ $1 -eq 32 ]]; then
        local url="https://raw.githubusercontent.com/mozilla/fxc2/master/dll/d3dcompiler_47_32.dll"
        local hash="2ad0d4987fc4624566b190e747c9d95038443956ed816abfd1e2d389b5ec0851"
    else
        local url="https://raw.githubusercontent.com/mozilla/fxc2/master/dll/d3dcompiler_47.dll"
        local hash="4432bbd1a390874f3f0a503d45cc48d346abc3a8c0213c289f4b615bf0ee84f3"
    fi
    curl --fail -sLo d3dcompiler_47.dll "$url" \
        || printErr "(downloadD3dcompiler_47) Could not download d3dcompiler_47.dll."
    local dlhash
    dlhash=$(sha256sum d3dcompiler_47.dll | cut -d' ' -f1)
    [[ "$dlhash" != "$hash" ]] && printErr "(downloadD3dcompiler_47) Integrity check failed. (Expected: $hash ; Calculated: $dlhash)"
    cp d3dcompiler_47.dll "$MAIN_PATH/d3dcompiler_47.dll.$1" || printErr "(downloadD3dcompiler_47) Unable to copy d3dcompiler_47.dll to $MAIN_PATH"
    removeTempDir
}

# Download / extract ReShade from specified link.
# $1 => Version of ReShade
# $2 -> Full URL of ReShade exe, ex.: https://reshade.me/downloads/ReShade_Setup_5.0.2.exe
function downloadReshade() {
    createTempDir
    curl --fail -sLO "$2" || printErr "Could not download version $1 of ReShade."
    exeFile="$(find . -name "*.exe")"
    ! [[ -f $exeFile ]] && printErr "Download of ReShade exe file failed."
    [[ $(file "$exeFile" | grep -o executable) == "" ]] && printErr "The ReShade exe file is not an executable file, does the ReShade version exist?"
    7z -y e "$exeFile" 1> /dev/null || printErr "Failed to extract ReShade using 7z."
    rm -f "$exeFile"
    resCurPath="$RESHADE_PATH/$1"
    [[ -e $resCurPath ]] && rm -rf "$resCurPath"
    mkdir -p "$resCurPath"
    mv ./* "$resCurPath"
    removeTempDir
}

# Link d3dcompiler_47.dll into the Wine/Proton prefix system32 or syswow64 directory.
# Since ReShade 6.5+, the DLL must exist there for shaders to compile correctly.
# $1 is the exe architecture (32 or 64).
function linkD3dcompilerToWineprefix() {
    [[ -z $WINEPREFIX ]] && return
    local arch="$1"
    local sysDir
    # 32-bit libraries go into syswow64 in a 64-bit prefix; 64-bit go into system32.
    if [[ $arch -eq 32 ]] && [[ -d "$WINEPREFIX/drive_c/windows/syswow64" ]]; then
        sysDir="$WINEPREFIX/drive_c/windows/syswow64"
    else
        sysDir="$WINEPREFIX/drive_c/windows/system32"
    fi
    if [[ ! -d $sysDir ]]; then
        echo "Warning: Wine prefix directory '$sysDir' not found -- skipping system32 d3dcompiler_47.dll install."
        return
    fi
    echo "Linking d3dcompiler_47.dll into '$sysDir' (required for ReShade 6.5+)."
    [[ -L "$sysDir/d3dcompiler_47.dll" ]] && unlink "$sysDir/d3dcompiler_47.dll"
    ln -is "$(realpath "$MAIN_PATH/d3dcompiler_47.dll.$arch")" "$sysDir/d3dcompiler_47.dll"
}

SEPARATOR="------------------------------------------------------------------------------------------------"
COMMON_OVERRIDES="d3d8 d3d9 d3d11 d3d12 ddraw dinput8 dxgi opengl32"
REQUIRED_EXECUTABLES=(7z curl git grep)
XDG_DATA_HOME=${XDG_DATA_HOME:-"$HOME/.local/share"}
MAIN_PATH=${MAIN_PATH:-"$XDG_DATA_HOME/reshade"}
RESHADE_PATH="$MAIN_PATH/reshade"
# Strip the leading /home/$USER/ then convert forward slashes to double-backslashes
# for use in Wine registry paths — done with pure bash, no external commands.
_tmp_path="${MAIN_PATH#/home/"$USER"/}"
WINE_MAIN_PATH="${_tmp_path//\//\\\\}"
unset _tmp_path
UPDATE_RESHADE=${UPDATE_RESHADE:-1}
MERGE_SHADERS=${MERGE_SHADERS:-1}
VULKAN_SUPPORT=${VULKAN_SUPPORT:-0}
GLOBAL_INI=${GLOBAL_INI:-"ReShade.ini"}
SHADER_REPOS=${SHADER_REPOS:-"https://github.com/CeeJayDK/SweetFX|sweetfx-shaders;https://github.com/martymcmodding/qUINT|martymc-shaders;https://github.com/BlueSkyDefender/AstrayFX|astrayfx-shaders;https://github.com/prod80/prod80-ReShade-Repository|prod80-shaders;https://github.com/crosire/reshade-shaders|reshade-shaders|slim"}
RESHADE_VERSION=${RESHADE_VERSION:-"latest"}
RESHADE_ADDON_SUPPORT=${RESHADE_ADDON_SUPPORT:-0}
FORCE_RESHADE_UPDATE_CHECK=${FORCE_RESHADE_UPDATE_CHECK:-0}
RESHADE_URL="https://reshade.me"
RESHADE_URL_ALT="https://static.reshade.me"
WINEPREFIX=${WINEPREFIX:-""}

for REQUIRED_EXECUTABLE in "${REQUIRED_EXECUTABLES[@]}"; do
    if ! command -v "$REQUIRED_EXECUTABLE" &>/dev/null; then
        printf "Program '%s' is missing, but it is required.\nExiting.\n" "$REQUIRED_EXECUTABLE"
        exit 1
    fi
done

# Z0000 Create MAIN_PATH
# Z0005 Check if update enabled.
# Z0010 Download / update shaders.
# Z0015 Download / update latest ReShade version.
# Z0016 Download version of ReShade specified by user.
# Z0020 Process GLOBAL_INI.
# Z0025 Vulkan install / uninstall.
# Z0030 DirectX / OpenGL uninstall.
# Z0035 DirectX / OpenGL find correct ReShade DLL.
# Z0040 Download d3dcompiler_47.dll.
# Z0045 DirectX / OpenGL link files to game directory.

# Z0000
mkdir -p "$MAIN_PATH" || printErr "Unable to create directory '$MAIN_PATH'."
cd "$MAIN_PATH" || exit
# Z0000

mkdir -p "$RESHADE_PATH"
mkdir -p "$MAIN_PATH/ReShade_shaders"
mkdir -p "$MAIN_PATH/External_shaders"

# Z0005
# Skip updating shaders / reshade if recently done (4 hours).
LASTUPDATED=0; [[ -f LASTUPDATED ]] && LASTUPDATED=$(< LASTUPDATED)
[[ ! $LASTUPDATED =~ ^[0-9]+$ ]] && LASTUPDATED=0
[[ $LASTUPDATED -gt 0 && $(($(date +%s)-LASTUPDATED)) -lt 14400 ]] && UPDATE_RESHADE=0
[[ $UPDATE_RESHADE == 1 ]] && date +%s > LASTUPDATED
# Z0005

echo -e "$SEPARATOR\nReShade installer/updater for Linux games using wine or proton.\n$SEPARATOR\n"

# Z0010
# Link Shader / Texture files from an input directory to an output directory if the link doesn't already exist.
# $1 is the input directory (full path).
# $2 is the output directory name (Textures / Shaders), with optional subdirectory.
function linkShaderFiles() {
    [[ ! -d $1 ]] && return
    cd "$1" || return
    for file in *; do
        [[ ! -f $file ]] && continue
        [[ -L "$MAIN_PATH/ReShade_shaders/Merged/$2/$file" ]] && continue
        INFILE="$(realpath "$1/$file")"
        OUTDIR="$(realpath "$MAIN_PATH/ReShade_shaders/Merged/$2/")"
        [[ ! -d $OUTDIR ]] && mkdir -p "$OUTDIR"
        echo "Linking $INFILE to $OUTDIR"
        ln -s "$INFILE" "$OUTDIR"
    done
}
# Check ReShade_shaders or External_shaders directories for directories to link to the Merged folder.
# $1 ReShade_shaders | External_shaders
# $2 Optional: Repo name
function mergeShaderDirs() {
    [[ $1 != ReShade_shaders && $1 != External_shaders ]] && return
    for dirName in Shaders Textures; do
        [[ $1 == "ReShade_shaders" ]] && dirPath=$(find "$MAIN_PATH/$1/$2" ! -path . -type d -name "$dirName") || dirPath="$MAIN_PATH/$1/$dirName"
        linkShaderFiles "$dirPath" "$dirName"
        # Check if there are any extra directories inside the Shaders or Texture folder, and link them.
        while IFS= read -rd '' anyDir; do
            linkShaderFiles "$dirPath/$anyDir" "$dirName/$anyDir"
        done < <(find . ! -path . -type d -print0)
    done
}
if [[ -n $SHADER_REPOS ]]; then
    echo "Checking for ReShade Shader updates."
    [[ $REBUILD_MERGE == 1 ]] && rm -rf "$MAIN_PATH/ReShade_shaders/Merged/"
    [[ $MERGE_SHADERS == 1 ]] && mkdir -p "$MAIN_PATH/ReShade_shaders/Merged/Shaders" &&  mkdir -p "$MAIN_PATH/ReShade_shaders/Merged/Textures"
    IFS=';' read -ra _shaderRepos <<< "$SHADER_REPOS"
    for _repoEntry in "${_shaderRepos[@]}"; do
        IFS='|' read -r URI localRepoName branchName <<< "$_repoEntry"
        if [[ -d "$MAIN_PATH/ReShade_shaders/$localRepoName" ]]; then
            if [[ $UPDATE_RESHADE -eq 1 ]]; then
                cd "$MAIN_PATH/ReShade_shaders/$localRepoName" || continue
                echo "Updating ReShade shader repository $URI."
                git pull --ff-only || echo "Could not update shader repo: $URI."
            fi
        else
            cd "$MAIN_PATH/ReShade_shaders" || exit
            branchArgs=()
            [[ -n $branchName ]] && branchArgs=(--branch "$branchName" --single-branch)
            echo "Cloning ReShade shader repository $URI."
            git clone --depth 1 "${branchArgs[@]}" "$URI" "$localRepoName" || echo "Could not clone Shader repo: $URI."
        fi
        [[ $MERGE_SHADERS == 1 ]] && mergeShaderDirs "ReShade_shaders" "$localRepoName"
    done
    if [[ $MERGE_SHADERS == 1 ]] && [[ -d "$MAIN_PATH/External_shaders" ]]; then
        echo "Checking for External Shader updates."
        mergeShaderDirs "External_shaders"
        # Link loose files.
        cd "$MAIN_PATH/External_shaders" || exit 1
        for file in *; do
            [[ ! -f $file || -L "$MAIN_PATH/ReShade_shaders/Merged/Shaders/$file" ]] && continue
            INFILE="$(realpath "$MAIN_PATH/External_shaders/$file")"
            OUTDIR="$MAIN_PATH/ReShade_shaders/Merged/Shaders/"
            echo "Linking $INFILE to $OUTDIR"
            ln -s "$INFILE" "$OUTDIR"
        done
    fi
fi
echo "$SEPARATOR"
# Z0010

# Z0015
cd "$MAIN_PATH" || exit
LVERS=0; [[ -f LVERS ]] && LVERS=$(< LVERS)
if [[ $RESHADE_VERSION == latest ]]; then
    # Check if user wants reshade without addon support and we're currently using reshade with addon support.
    [[ $LVERS =~ Addon && $RESHADE_ADDON_SUPPORT -eq 0 ]] && UPDATE_RESHADE=1
    # Check if user wants reshade with addon support and we're not currently using reshade with addon support.
    [[ ! $LVERS =~ Addon ]] && [[ $RESHADE_ADDON_SUPPORT -eq 1 ]] && UPDATE_RESHADE=1
fi
if [[ $FORCE_RESHADE_UPDATE_CHECK -eq 1 ]] || [[ $UPDATE_RESHADE -eq 1 ]] || [[ ! -e reshade/latest/ReShade64.dll ]] || [[ ! -e reshade/latest/ReShade32.dll ]]; then
    echo -e "Checking for ReShade updates.\n$SEPARATOR"
    ALT_URL=0
    if ! RHTML=$(curl --fail --max-time 10 -sL "$RESHADE_URL") || [[ $RHTML == *'<h2>Something went wrong.</h2>'* ]]; then
        ALT_URL=1
        echo "Error: Failed to connect to '$RESHADE_URL' after 10 seconds. Trying to connect to '$RESHADE_URL_ALT'."
        RHTML=$(curl -sL "$RESHADE_URL_ALT") || echo "Error: Failed to connect to '$RESHADE_URL_ALT'."
    fi
    [[ $RESHADE_ADDON_SUPPORT -eq 1 ]] && VREGEX="[0-9][0-9.]*[0-9]_Addon" || VREGEX="[0-9][0-9.]*[0-9]"
    RLINK="$(echo "$RHTML" | grep -o "/downloads/ReShade_Setup_${VREGEX}\.exe" | head -n1)"
    [[ $RLINK == "" ]] && printErr "Could not fetch ReShade version."
    [[ $ALT_URL -eq 1 ]] && RLINK="${RESHADE_URL_ALT}${RLINK}" || RLINK="${RESHADE_URL}${RLINK}"
    RVERS=$(echo "$RLINK" | grep -o "$VREGEX")
    if [[ $RVERS != "$LVERS" ]]; then
        [[ -L $RESHADE_PATH/latest ]] && unlink "$RESHADE_PATH/latest"
        echo -e "Updating ReShade to latest version."
        downloadReshade "$RVERS" "$RLINK"
        ln -is "$(realpath "$RESHADE_PATH/$RVERS")" "$(realpath "$RESHADE_PATH/latest")"
        echo "$RVERS" > LVERS
        LVERS="$RVERS"
        echo "Updated ReShade to version $RVERS."
    fi
fi
# Z0015

# Z0016
cd "$MAIN_PATH" || exit
if [[ $RESHADE_VERSION != latest ]]; then
    [[ $RESHADE_ADDON_SUPPORT -eq 1 ]] && RESHADE_VERSION="${RESHADE_VERSION}_Addon"
    if [[ ! -f reshade/$RESHADE_VERSION/ReShade64.dll ]] || [[ ! -f reshade/$RESHADE_VERSION/ReShade32.dll ]]; then
        echo -e "Downloading version $RESHADE_VERSION of ReShade.\n$SEPARATOR\n"
        [[ -e reshade/$RESHADE_VERSION ]] && rm -rf "reshade/$RESHADE_VERSION"
        downloadReshade "$RESHADE_VERSION" "$RESHADE_URL/downloads/ReShade_Setup_$RESHADE_VERSION.exe"
    fi
    echo -e "Using version $RESHADE_VERSION of ReShade.\n"
else
    echo -e "Using the latest version of ReShade ($LVERS).\n"
fi
# Z0016

# Z0020
if [[ $GLOBAL_INI != 0 ]] && [[ $GLOBAL_INI == ReShade.ini ]] && [[ ! -f $MAIN_PATH/$GLOBAL_INI ]]; then
    cd "$MAIN_PATH" || exit
    curl --fail -sLO https://github.com/asafelobotomy/reshade-steam-proton/raw/ini/ReShade.ini
    if [[ -f ReShade.ini ]]; then
        sed -i "s/_USERSED_/$USER/g" "$MAIN_PATH/$GLOBAL_INI"
        if [[ $MERGE_SHADERS == 1 ]]; then
            sed -i "s#_SHADSED_#$WINE_MAIN_PATH\\\ReShade_shaders\\\Merged\\\Shaders#g" "$MAIN_PATH/$GLOBAL_INI"
            sed -i "s#_TEXSED_#$WINE_MAIN_PATH\\\ReShade_shaders\\\Merged\\\Textures#g" "$MAIN_PATH/$GLOBAL_INI"
        fi
    fi
fi
# Z0020

# Z0025
# TODO Requires changes for ReShade 5.0 ; paths and json files are different.
# See https://github.com/kevinlekiller/reshade-steam-proton/issues/6#issuecomment-1027230967
if [[ $VULKAN_SUPPORT == 1 ]]; then
    echo "Does the game use the Vulkan API?"
    if [[ $(checkStdin "(y/n): " "^(y|n)$") == "y" ]]; then
        echo 'Supply the WINEPREFIX path for the game.'
        echo '(Control+c to exit)'
        while true; do
            read -rp 'WINEPREFIX path: ' WINEPREFIX
            # Expand leading ~ without using eval (safe tilde expansion).
            WINEPREFIX="${WINEPREFIX/#\~/$HOME}"
            WINEPREFIX=$(realpath "$WINEPREFIX" 2>/dev/null)
            if [[ -z $WINEPREFIX || ! -d $WINEPREFIX ]]; then
                echo "Incorrect or empty path supplied. You supplied \"$WINEPREFIX\"."
                continue
            fi
            echo "Is this path correct? \"$WINEPREFIX\""
            [[ $(checkStdin "(y/n) " "^(y|n)$") == "y" ]] && break
        done
        echo "Specify if the game's EXE file architecture is 32 or 64 bits:"
        [[ $(checkStdin "(32/64) " "^(32|64)$") == 64 ]] && exeArch=64 || exeArch=32
        export WINEPREFIX="$WINEPREFIX"
        echo "Do you want to (i)nstall or (u)ninstall ReShade?"
        if [[ $(checkStdin "(i/u): " "^(i|u)$") == "i" ]]; then
            wine reg ADD HKLM\\SOFTWARE\\Khronos\\Vulkan\\ImplicitLayers /d 0 /t REG_DWORD /v "Z:\\home\\$USER\\$WINE_MAIN_PATH\\reshade\\$RESHADE_VERSION\\ReShade$exeArch.json" -f /reg:"$exeArch" \
                && echo "Done." || echo "An error has occurred."
        else
            wine reg DELETE HKLM\\SOFTWARE\\Khronos\\Vulkan\\ImplicitLayers -f /reg:"$exeArch" \
                && echo "Done." || echo "An error has occurred."
        fi
        exit 0
    fi
fi
# Z0025

# Z0030
echo "Do you want to (i)nstall or (u)ninstall ReShade for a DirectX or OpenGL game?"
if [[ $(checkStdin "(i/u): " "^(i|u)$") == "u" ]]; then
    getGamePath
    echo "Unlinking ReShade files."
    # Build the DLL list from COMMON_OVERRIDES using bash string substitution
    # (replaces each space with ".dll ", then appends ".dll" to the last entry).
    LINKS="${COMMON_OVERRIDES// /.dll }.dll ReShade.ini ReShade32.json ReShade64.json d3dcompiler_47.dll Shaders Textures ReShade_shaders"
    [[ -n $LINK_PRESET ]] && LINKS="$LINKS $LINK_PRESET"
    for link in $LINKS; do
        if [[ -L $gamePath/$link ]]; then
            echo "Unlinking \"$gamePath/$link\"."
            unlink "$gamePath/$link"
        fi
    done
    if [[ $DELETE_RESHADE_FILES == 1 ]]; then
        echo "Deleting ReShade.log and ReShadePreset.ini"
        rm -f "$gamePath/ReShade.log" "$gamePath/ReShadePreset.ini"
    fi
    if [[ -n $WINEPREFIX ]]; then
        for sysDir in "$WINEPREFIX/drive_c/windows/system32" "$WINEPREFIX/drive_c/windows/syswow64"; do
            if [[ -L "$sysDir/d3dcompiler_47.dll" ]]; then
                echo "Unlinking d3dcompiler_47.dll from '$sysDir'."
                unlink "$sysDir/d3dcompiler_47.dll"
            fi
        done
    fi
    echo "Finished uninstalling ReShade for '$gamePath'."
    echo -e "\e[40m\e[32mMake sure to remove or change the \e[34mWINEDLLOVERRIDES\e[32m environment variable.\e[0m"
    exit 0
fi
# Z0030

# Z0035
getGamePath
echo "Do you want $0 to attempt to automatically detect the right dll files to use for ReShade?"
[[ $(checkStdin "(y/n) " "^(y|n)$") == "y" ]] && wantedDll="auto" || wantedDll="manual"
exeArch=32
if [[ $wantedDll == "auto" ]]; then
    for file in "$gamePath/"*.exe; do
        if [[ $(file "$file") =~ x86-64 ]]; then
            exeArch=64
            break
        fi
    done
    [[ $exeArch -eq 32 ]] && wantedDll="d3d9" || wantedDll="dxgi"
    echo "We have detected the game is $exeArch bits, we will use $wantedDll.dll as the override, is this correct?"
    [[ $(checkStdin "(y/n) " "^(y|n)$") == "n" ]] && wantedDll="manual"
else
    echo "Specify if the game's EXE file architecture is 32 or 64 bits:"
    [[ $(checkStdin "(32/64) " "^(32|64)$") == 64 ]] && exeArch=64
fi
if [[ $wantedDll == "manual" ]]; then
    echo "Manually enter the dll override for ReShade, common values are one of: $COMMON_OVERRIDES"
    while true; do
        read -rp 'Override: ' wantedDll
        wantedDll=${wantedDll//.dll/}
        echo "You have entered '$wantedDll', is this correct?"
        read -rp '(y/n): ' ynCheck
        [[ $ynCheck =~ ^(y|Y|yes|YES)$ ]] && break
    done
fi
# Z0035

# Z0040
downloadD3dcompiler_47 "$exeArch"
linkD3dcompilerToWineprefix "$exeArch"
# Z0040

# Z0045
echo "Linking ReShade files to game directory."
[[ -L $gamePath/$wantedDll.dll ]] && unlink "$gamePath/$wantedDll.dll"
if [[ $exeArch == 32 ]]; then
    echo "Linking ReShade32.dll to $wantedDll.dll."
    ln -is "$(realpath "$RESHADE_PATH/$RESHADE_VERSION"/ReShade32.dll)" "$gamePath/$wantedDll.dll"
else
    echo "Linking ReShade64.dll to $wantedDll.dll."
    ln -is "$(realpath "$RESHADE_PATH/$RESHADE_VERSION"/ReShade64.dll)" "$gamePath/$wantedDll.dll"
fi
[[ -L $gamePath/d3dcompiler_47.dll ]] && unlink "$gamePath/d3dcompiler_47.dll"
ln -is "$(realpath "$MAIN_PATH/d3dcompiler_47.dll.$exeArch")" "$gamePath/d3dcompiler_47.dll"
[[ -L $gamePath/ReShade_shaders ]] && unlink "$gamePath/ReShade_shaders"
ln -is "$(realpath "$MAIN_PATH"/ReShade_shaders)" "$gamePath/"
if [[ $GLOBAL_INI != 0 ]] && [[ -f $MAIN_PATH/$GLOBAL_INI ]]; then
    [[ -L $gamePath/$GLOBAL_INI ]] && unlink "$gamePath/$GLOBAL_INI"
    ln -is "$(realpath "$MAIN_PATH/$GLOBAL_INI")" "$gamePath/$GLOBAL_INI"
fi
if [[ -f $MAIN_PATH/$LINK_PRESET ]]; then
    echo "Linking $LINK_PRESET to game directory."
    [[ -L $gamePath/$LINK_PRESET ]] && unlink "$gamePath/$LINK_PRESET"
    ln -is "$(realpath "$MAIN_PATH/$LINK_PRESET")" "$gamePath/$LINK_PRESET"
fi
# Z0045

echo -e "$SEPARATOR\nDone."
gameEnvVar="WINEDLLOVERRIDES=\"d3dcompiler_47=n;$wantedDll=n,b\""
echo -e "\e[40m\e[32mIf you're using Steam, right click the game, click properties, set the 'LAUNCH OPTIONS' to: \e[34m$gameEnvVar %command%"
echo -e "\e[32mIf not, run the game with this environment variable set: \e[34m$gameEnvVar"
echo -e "\e[32mThe next time you start the game, \e[34mopen the ReShade settings, go to the 'Settings' tab, if they are missing, add the Shaders folder" \
        "location to the 'Effect Search Paths', add the Textures folder to the 'Texture Search Paths'," \
        "these folders are located inside the ReShade_shaders folder, finally go to the 'Home' tab, click 'Reload'.\e[0m"
if [[ -z $WINEPREFIX ]]; then
    echo -e "\e[40m\e[33mNote: ReShade 6.5+ requires d3dcompiler_47.dll in the game's Wine/Proton prefix system32 folder,"
    echo -e "not only in the game folder. If shaders fail to compile, re-run with WINEPREFIX set:"
    echo -e "\e[34mWINEPREFIX=\"\$HOME/.local/share/Steam/steamapps/compatdata/<AppID>/pfx\" $0\e[0m"
fi
