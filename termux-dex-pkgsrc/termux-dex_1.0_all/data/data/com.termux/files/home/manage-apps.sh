#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
#   Termux Desktop — App Manager  v2.1
#   Install or remove apps at any time after setup
#   Uses the same interactive checklist as setup.sh
#   Repo : github.com/Tanmay-1122/Termux-desktop
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── IP address helper (ifconfig not always installed) ─────────
get_ip() {
    local iface="$1"
    local ip=""
    ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}' | head -1)
    if [ -z "$ip" ] && command -v ifconfig &>/dev/null; then
        ip=$(ifconfig "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
    fi
    echo "$ip"
}

# ── Helpers ──────────────────────────────────────────────────
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
info() { echo -e "  ${DIM}→${NC} $1"; }

show_progress() {
    local current=$1 total=$2 label=$3
    local percent=$(( current * 100 / total ))
    local filled=$(( percent * 30 / 100 ))
    local bar=""
    for ((i=0; i<30; i++)); do
        if [ $i -lt $filled ]; then bar="${bar}█"
        elif [ $i -eq $filled ]; then bar="${bar}▓"
        else bar="${bar}░"
        fi
    done
    printf "  \033[0;36m[%s]\033[0m \033[1m%3d%%\033[0m  %s\n" "$bar" "$percent" "$label"
}

pkg_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

pkg_available() {
    apt-cache show "$1" >/dev/null 2>&1
}

# Cache-aware update: only call pkg update if the index is older than 1 hour.
# This prevents a full network round-trip on every single install.
_PKG_STAMP="/tmp/.termux-dex-manage-updated"
refresh_packages() {
    local force="${1:-}"
    local age=9999
    if [ -f "$_PKG_STAMP" ]; then
        # seconds since last update
        local now; now=$(date +%s)
        local then; then=$(date -r "$_PKG_STAMP" +%s 2>/dev/null || echo 0)
        age=$(( now - then ))
    fi
    if [ "$force" = "force" ] || [ "$age" -gt 3600 ]; then
        pkg update -y > /tmp/termux-dex-manage-update.log 2>&1 || true
        touch "$_PKG_STAMP"
    fi
}

install_pkg_group() {
    local label="$1"
    shift

    local pending=()
    local skipped=()
    local failed=()
    local pkg

    refresh_packages || warn "Package index refresh had warnings; continuing"

    for pkg in "$@"; do
        if pkg_installed "$pkg"; then
            ok "$pkg already installed"
        elif pkg_available "$pkg"; then
            pending+=("$pkg")
        else
            warn "$pkg is not available in enabled repos - skipped"
            skipped+=("$pkg")
        fi
    done

    [ ${#pending[@]} -eq 0 ] && return 0

    show_progress 1 3 "Installing $label (${#pending[@]} package(s))..."
    if pkg install -y "${pending[@]}" > /tmp/pkg_install.log 2>&1; then
        ok "$label installed"
        return 0
    fi

    warn "Batch install failed - refreshing indexes and retrying..."
    refresh_packages force
    show_progress 2 3 "Retrying $label..."
    if pkg install -y "${pending[@]}" > /tmp/pkg_install.log 2>&1; then
        ok "$label installed after retry"
        return 0
    fi

    warn "Still failing - trying packages individually"
    local count=0
    local total=${#pending[@]}
    for pkg in "${pending[@]}"; do
        count=$((count + 1))
        show_progress "$count" "$total" "Installing $pkg..."
        if pkg install -y "$pkg" > /tmp/pkg_install.log 2>&1; then
            ok "$pkg installed"
        else
            fail "$pkg FAILED"
            failed+=("$pkg")
        fi
    done

    [ ${#failed[@]} -gt 0 ] && warn "Some failed: ${failed[*]} - check /tmp/pkg_install.log"
    [ ${#skipped[@]} -gt 0 ] && warn "Skipped unavailable packages: ${skipped[*]}"
}

# ════════════════════════════════════════════════════════════
# APP CATALOGUE (same as setup.sh — keep in sync)
# Format: "pkg_name|display_name|category|description"
# Only Termux-native packages — no proot/chroot required
# ════════════════════════════════════════════════════════════

BROWSERS=(
    "firefox|Firefox|browser|Full desktop browser with GPU rendering"
    "chromium|Chromium|browser|Open-source Chrome — good HTML5 support"
    "lynx|Lynx|browser|Lightweight terminal browser"
    "w3m|w3m|browser|Terminal browser with inline image support"
)
EDITORS=(
    "neovim|Neovim|editor|Modern Vim with LSP support"
    "gedit|Gedit|editor|GNOME text editor — good for beginners"
    "mousepad|Mousepad|editor|XFCE default lightweight editor"
    "nano|Nano|editor|Simple terminal editor"
    "micro|Micro|editor|Modern terminal editor with mouse support"
)
LANGUAGES=(
    "python|Python 3|lang|Python interpreter + pip"
    "nodejs|Node.js|lang|JavaScript runtime + npm"
    "ruby|Ruby|lang|Ruby interpreter + gem"
    "php|PHP|lang|PHP CLI for web dev"
    "golang|Go|lang|Google's Go language"
    "rust|Rust|lang|Systems programming language"
    "openjdk-17|Java 17 (OpenJDK)|lang|Java runtime + compiler"
    "lua54|Lua 5.4|lang|Lightweight scripting language"
)
DEVTOOLS=(
    "git|Git|dev|Version control"
    "curl|cURL|dev|HTTP client for APIs"
    "openssh|OpenSSH|dev|SSH server + client"
    "gh|GitHub CLI|dev|Manage GitHub from terminal"
    "jq|jq|dev|JSON processor"
    "make|Make|dev|Build automation"
    "clang|Clang/LLVM|dev|C/C++ compiler suite"
    "cmake|CMake|dev|Cross-platform build system"
    "tmux|tmux|dev|Terminal multiplexer"
)
UTILITIES=(
    "htop|htop|util|Interactive process viewer"
    "neofetch|Neofetch|util|System info banner"
    "thunar|Thunar|util|XFCE file manager"
    "galculator|Calculator|util|GTK calculator app"
    "xfce4-terminal|XFCE Terminal|util|Better terminal for XFCE"
    "ranger|Ranger|util|Terminal file manager"
    "tree|tree|util|Directory tree viewer"
)
OFFICE=(
    "libreoffice|LibreOffice|office|Full office suite"
    "zathura|Zathura|office|Minimal PDF viewer"
    "evince|Evince|office|GNOME document viewer"
)
MEDIA=(
    "mpv|mpv|media|Lightweight media player"
    "feh|feh|media|Fast image viewer"
    "eog|Eye of GNOME|media|Full-featured image viewer"
    "ffmpeg|FFmpeg|media|Video/audio converter"
)

ALL_CATEGORIES=(
    "Browsers:BROWSERS"
    "Code Editors:EDITORS"
    "Programming Languages:LANGUAGES"
    "Dev Tools:DEVTOOLS"
    "Utilities:UTILITIES"
    "Office / Productivity:OFFICE"
    "Media:MEDIA"
)

# ════════════════════════════════════════════════════════════
# Interactive checklist (install mode)
# ════════════════════════════════════════════════════════════
SELECTED_PKGS=()

show_install_checklist() {
    local category_name="$1"
    local -n items=$2

    local pkg_list=() display_list=() desc_list=() installed_list=()
    local selections=()

    for entry in "${items[@]}"; do
        IFS='|' read -r pkg display cat desc <<< "$entry"
        pkg_list+=("$pkg")
        display_list+=("$display")
        desc_list+=("$desc")
        # Check if already installed
        if dpkg -s "$pkg" &>/dev/null 2>&1; then
            installed_list+=("installed")
            selections+=(0)
        else
            installed_list+=("")
            selections+=(0)
        fi
    done

    local total=${#pkg_list[@]}
    local cursor=0

    while true; do
        clear
        echo ""
        echo -e "${CYAN}${BOLD}  ── $category_name ──${NC}"
        echo -e "  ${DIM}[installed] = already on system │ Space = toggle │ Enter = confirm${NC}"
        echo ""

        for ((i=0; i<total; i++)); do
            local check="○"
            local label_color="$NC"
            local installed_tag=""

            [ "${selections[$i]}" -eq 1 ] && check="${GREEN}✓${NC}"
            [ -n "${installed_list[$i]}" ] && installed_tag=" ${DIM}[installed]${NC}"

            if [ "$i" -eq "$cursor" ]; then
                echo -e "  ${CYAN}▶ [${check}]  ${BOLD}${display_list[$i]}${NC}${installed_tag}"
                echo -e "       ${DIM}${desc_list[$i]}${NC}"
                echo ""
            else
                echo -e "    [${check}]  ${display_list[$i]}${installed_tag}"
            fi
        done

        echo ""
        echo -e "  ${DIM}↑/k up │ ↓/j down │ Space toggle │ A all │ N none │ Enter done${NC}"

        IFS= read -rsn1 key 2>/dev/null
        case "$key" in
            $'\x1b')
                IFS= read -rsn1 -t 0.1 k2; IFS= read -rsn1 -t 0.1 k3
                case "$k2$k3" in
                    '[A') [ $cursor -gt 0 ] && cursor=$((cursor-1)) ;;
                    '[B') [ $cursor -lt $((total-1)) ] && cursor=$((cursor+1)) ;;
                esac ;;
            'k') [ $cursor -gt 0 ] && cursor=$((cursor-1)) ;;
            'j') [ $cursor -lt $((total-1)) ] && cursor=$((cursor+1)) ;;
            ' ')
                [ "${selections[$cursor]}" -eq 0 ] \
                    && selections[$cursor]=1 || selections[$cursor]=0 ;;
            'a'|'A') for ((i=0;i<total;i++)); do selections[$i]=1; done ;;
            'n'|'N') for ((i=0;i<total;i++)); do selections[$i]=0; done ;;
            '') break ;;
        esac
    done

    for ((i=0;i<total;i++)); do
        [ "${selections[$i]}" -eq 1 ] && SELECTED_PKGS+=("${pkg_list[$i]}")
    done
}

# ════════════════════════════════════════════════════════════
# Interactive checklist (uninstall mode)
# ════════════════════════════════════════════════════════════
REMOVE_PKGS=()

show_uninstall_checklist() {
    local category_name="$1"
    local -n items=$2

    local pkg_list=() display_list=() installed_list=()
    local selections=()

    for entry in "${items[@]}"; do
        IFS='|' read -r pkg display cat desc <<< "$entry"
        # Only show installed packages
        if dpkg -s "$pkg" &>/dev/null 2>&1; then
            pkg_list+=("$pkg")
            display_list+=("$display")
            selections+=(0)
        fi
    done

    [ ${#pkg_list[@]} -eq 0 ] && {
        info "No installed packages in $category_name"
        return
    }

    local total=${#pkg_list[@]}
    local cursor=0

    while true; do
        clear
        echo ""
        echo -e "${RED}${BOLD}  ── Remove from: $category_name ──${NC}"
        echo -e "  ${DIM}These are currently installed. Select to remove.${NC}"
        echo ""

        for ((i=0; i<total; i++)); do
            local check="○"
            [ "${selections[$i]}" -eq 1 ] && check="${RED}✓${NC}"

            if [ "$i" -eq "$cursor" ]; then
                echo -e "  ${CYAN}▶ [${check}]  ${BOLD}${display_list[$i]}${NC}"
                echo ""
            else
                echo -e "    [${check}]  ${display_list[$i]}"
            fi
        done

        echo ""
        echo -e "  ${DIM}↑/k up │ ↓/j down │ Space toggle │ A all │ N none │ Enter done${NC}"

        IFS= read -rsn1 key 2>/dev/null
        case "$key" in
            $'\x1b')
                IFS= read -rsn1 -t 0.1 k2; IFS= read -rsn1 -t 0.1 k3
                case "$k2$k3" in
                    '[A') [ $cursor -gt 0 ] && cursor=$((cursor-1)) ;;
                    '[B') [ $cursor -lt $((total-1)) ] && cursor=$((cursor+1)) ;;
                esac ;;
            'k') [ $cursor -gt 0 ] && cursor=$((cursor-1)) ;;
            'j') [ $cursor -lt $((total-1)) ] && cursor=$((cursor+1)) ;;
            ' ')
                [ "${selections[$cursor]}" -eq 0 ] \
                    && selections[$cursor]=1 || selections[$cursor]=0 ;;
            'a'|'A') for ((i=0;i<total;i++)); do selections[$i]=1; done ;;
            'n'|'N') for ((i=0;i<total;i++)); do selections[$i]=0; done ;;
            '') break ;;
        esac
    done

    for ((i=0;i<total;i++)); do
        [ "${selections[$i]}" -eq 1 ] && REMOVE_PKGS+=("${pkg_list[$i]}")
    done
}

# ════════════════════════════════════════════════════════════
# Main Menu
# ════════════════════════════════════════════════════════════
clear
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║       📦  Termux Desktop — App Manager          ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║                                                  ║"
echo "║   I) Install new apps                           ║"
echo "║   R) Remove installed apps                      ║"
echo "║   L) List all installed apps from catalogue     ║"
echo "║   Q) Quit                                       ║"
echo "║                                                  ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
read -rp "  Choose [I/R/L/Q]: " MAIN_CHOICE
MAIN_CHOICE=$(echo "$MAIN_CHOICE" | tr '[:lower:]' '[:upper:]')

case "$MAIN_CHOICE" in

    # ── Install mode ─────────────────────────────────────────
    I)
        clear
        echo ""
        echo -e "${CYAN}${BOLD}  Select app categories to browse:${NC}"
        echo ""
        IDX=1
        for cat_entry in "${ALL_CATEGORIES[@]}"; do
            IFS=':' read -r cat_name cat_var <<< "$cat_entry"
            echo "   $IDX) $cat_name"
            IDX=$((IDX + 1))
        done
        echo "   A) All categories"
        echo "   Q) Quit"
        echo ""
        read -rp "  Enter choices [e.g. 1 3 5 or A]: " CAT_INPUT
        CAT_INPUT=$(echo "$CAT_INPUT" | tr '[:lower:]' '[:upper:]')

        SELECTED_PKGS=()
        IDX=1
        for cat_entry in "${ALL_CATEGORIES[@]}"; do
            IFS=':' read -r cat_name cat_var <<< "$cat_entry"
            if echo "$CAT_INPUT" | grep -q "$IDX" || echo "$CAT_INPUT" | grep -q 'A'; then
                show_install_checklist "$cat_name" "$cat_var"
            fi
            IDX=$((IDX + 1))
        done

        if [ ${#SELECTED_PKGS[@]} -eq 0 ]; then
            info "No packages selected."
            exit 0
        fi

        # Deduplicate
        SELECTED_PKGS=($(printf '%s\n' "${SELECTED_PKGS[@]}" | sort -u))

        echo ""
        echo "  Installing ${#SELECTED_PKGS[@]} package(s):"
        for pkg in "${SELECTED_PKGS[@]}"; do echo "   • $pkg"; done
        echo ""
        read -rp "  Proceed? [Y/n]: " CONFIRM
        [[ "$CONFIRM" =~ ^[Nn]$ ]] && { echo "Aborted."; exit 0; }

        install_pkg_group "selected apps" "${SELECTED_PKGS[@]}"

        echo ""
        ok "Install pass finished"
        ;;

    # ── Remove mode ──────────────────────────────────────────
    R)
        echo ""
        warn "Remove mode — only packages from the catalogue will be listed."
        echo ""

        REMOVE_PKGS=()
        for cat_entry in "${ALL_CATEGORIES[@]}"; do
            IFS=':' read -r cat_name cat_var <<< "$cat_entry"
            show_uninstall_checklist "$cat_name" "$cat_var"
        done

        if [ ${#REMOVE_PKGS[@]} -eq 0 ]; then
            info "No packages selected for removal."
            exit 0
        fi

        echo ""
        echo -e "  ${RED}About to REMOVE ${#REMOVE_PKGS[@]} package(s):${NC}"
        for pkg in "${REMOVE_PKGS[@]}"; do echo "   • $pkg"; done
        echo ""
        read -rp "  Confirm removal? [y/N]: " CONFIRM
        [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && { echo "Aborted."; exit 0; }

        COUNT=0
        TOTAL=${#REMOVE_PKGS[@]}
        for pkg in "${REMOVE_PKGS[@]}"; do
            COUNT=$((COUNT + 1))
            show_progress "$COUNT" "$TOTAL" "Removing $pkg..."
            if pkg uninstall -y "$pkg" > /dev/null 2>&1; then
                ok "$pkg removed"
            else
                fail "$pkg could not be removed"
            fi
        done
        ;;

    # ── List installed ────────────────────────────────────────
    L)
        echo ""
        echo -e "${CYAN}${BOLD}  Installed apps from catalogue:${NC}"
        echo ""
        FOUND=0
        for cat_entry in "${ALL_CATEGORIES[@]}"; do
            IFS=':' read -r cat_name cat_var <<< "$cat_entry"
            echo -e "  ${BOLD}$cat_name:${NC}"
            declare -n items="$cat_var"
            for entry in "${items[@]}"; do
                IFS='|' read -r pkg display cat desc <<< "$entry"
                if dpkg -s "$pkg" &>/dev/null 2>&1; then
                    echo -e "   ${GREEN}✓${NC} $display"
                    FOUND=$((FOUND + 1))
                fi
            done
            unset -n items
            echo ""
        done
        [ "$FOUND" -eq 0 ] && info "No catalogue apps currently installed."
        ;;

    Q|*)
        echo "Goodbye."
        exit 0
        ;;
esac

echo ""
echo "  Done. Run 'bash ~/manage-apps.sh' anytime to manage apps."
