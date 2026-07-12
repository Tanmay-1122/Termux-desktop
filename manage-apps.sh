#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
#   Termux Desktop — App Manager
#   Browse, install & remove GUI apps with a visual checklist.
#   Usage:  bash ~/manage-apps.sh
#   Repo : github.com/Tanmay-1122/Termux-desktop
# ============================================================

# ── Temp directory: always use $TMPDIR, never /tmp ────────────
# Termux sandboxes /tmp/ — writing there causes "Permission denied"
export TMPDIR="${TMPDIR:-$PREFIX/tmp}"
mkdir -p "$TMPDIR" 2>/dev/null || true

LOG_DIR="$TMPDIR/termux-dex-logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true

_PKG_STAMP="$LOG_DIR/.manage-updated"
UPDATE_LOG="$LOG_DIR/update.log"
INSTALL_LOG="$LOG_DIR/install.log"

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

npm_installed() {
    npm list -g "$1" --depth=0 2>/dev/null | grep -q "$1"
}

pip_installed() {
    pip show "$1" >/dev/null 2>&1 || pip3 show "$1" >/dev/null 2>&1
}

# ── Detect available package managers ─────────────────────────
HAS_NPM=false
HAS_PIP=false
HAS_PIPX=false
HAS_CARGO=false

detect_managers() {
    command -v npm &>/dev/null && HAS_NPM=true
    if command -v pip &>/dev/null; then
        HAS_PIP=true
    elif command -v pip3 &>/dev/null; then
        HAS_PIP=true
    fi
    command -v pipx &>/dev/null && HAS_PIPX=true
    command -v cargo &>/dev/null && HAS_CARGO=true
}

# Cache-aware update: only call pkg update if the index is older than 1 hour.
refresh_packages() {
    local force="${1:-}"
    local age=9999
    if [ -f "$_PKG_STAMP" ]; then
        local now; now=$(date +%s)
        local then; then=$(date -r "$_PKG_STAMP" +%s 2>/dev/null || echo 0)
        age=$(( now - then ))
    fi
    if [ "$force" = "force" ] || [ "$age" -gt 3600 ]; then
        pkg update -y > "$UPDATE_LOG" 2>&1 || true
        touch "$_PKG_STAMP" 2>/dev/null || true
    fi
}

# Safe install wrapper: tries pkg, falls back gracefully
safe_pkg_install() {
    local pkg="$1"
    if pkg_available "$pkg"; then
        pkg install -y "$pkg" > "$INSTALL_LOG" 2>&1
        return $?
    fi
    return 1
}

safe_npm_install() {
    local pkg="$1"
    if $HAS_NPM; then
        npm install -g "$pkg" > "$INSTALL_LOG" 2>&1
        return $?
    fi
    return 1
}

safe_pip_install() {
    local pkg="$1"
    if $HAS_PIPX; then
        pipx install "$pkg" > "$INSTALL_LOG" 2>&1
        return $?
    elif $HAS_PIP; then
        pip install --user "$pkg" > "$INSTALL_LOG" 2>&1
        return $?
    fi
    return 1
}

safe_cargo_install() {
    local pkg="$1"
    local bin="$2"
    if $HAS_CARGO; then
        cargo install "$pkg" > "$INSTALL_LOG" 2>&1
        return $?
    fi
    return 1
}

install_pkg_group() {
    local label="$1"
    local install_fn="$2"
    shift 2

    local pending=()
    local skipped=()
    local failed=()
    local pkg

    refresh_packages || warn "Package index refresh had warnings; continuing"

    for pkg in "$@"; do
        IFS='|' read -r pkg_name install_method <<< "$pkg"
        pkg_name="${pkg_name:-$pkg}"
        install_method="${install_method:-pkg}"

        if pkg_installed "$pkg_name" || npm_installed "$pkg_name" || pip_installed "$pkg_name"; then
            ok "$pkg_name already installed"
        else
            pending+=("$pkg_name|$install_method")
        fi
    done

    [ ${#pending[@]} -eq 0 ] && return 0

    show_progress 1 3 "Installing $label (${#pending[@]} package(s))..."
    local batch_success=true
    for entry in "${pending[@]}"; do
        IFS='|' read -r pkg_name install_method <<< "$entry"
        local result=false
        case "$install_method" in
            npm)    $HAS_NPM && safe_npm_install "$pkg_name" && result=true ;;
            pip)    $HAS_PIP && safe_pip_install "$pkg_name" && result=true ;;
            cargo)  safe_cargo_install "$pkg_name" "$pkg_name" && result=true ;;
            *)      safe_pkg_install "$pkg_name" && result=true ;;
        esac
        $result || { batch_success=false; break; }
    done

    $batch_success && { ok "$label installed"; return 0; }

    warn "Batch install failed - refreshing indexes and retrying..."
    refresh_packages force
    show_progress 2 3 "Retrying $label..."
    local retry_success=true
    for entry in "${pending[@]}"; do
        IFS='|' read -r pkg_name install_method <<< "$entry"
        local result=false
        case "$install_method" in
            npm)    $HAS_NPM && safe_npm_install "$pkg_name" && result=true ;;
            pip)    $HAS_PIP && safe_pip_install "$pkg_name" && result=true ;;
            cargo)  safe_cargo_install "$pkg_name" "$pkg_name" && result=true ;;
            *)      safe_pkg_install "$pkg_name" && result=true ;;
        esac
        $result || { retry_success=false; break; }
    done

    $retry_success && { ok "$label installed after retry"; return 0; }

    warn "Still failing - trying packages individually"
    local count=0
    local total=${#pending[@]}
    for entry in "${pending[@]}"; do
        count=$((count + 1))
        IFS='|' read -r pkg_name install_method <<< "$entry"
        show_progress "$count" "$total" "Installing $pkg_name..."
        local result=false
        case "$install_method" in
            npm)    $HAS_NPM && safe_npm_install "$pkg_name" && result=true ;;
            pip)    $HAS_PIP && safe_pip_install "$pkg_name" && result=true ;;
            cargo)  safe_cargo_install "$pkg_name" "$pkg_name" && result=true ;;
            *)      safe_pkg_install "$pkg_name" && result=true ;;
        esac
        if $result; then
            ok "$pkg_name installed"
        else
            fail "$pkg_name FAILED"
            failed+=("$pkg_name")
        fi
    done

    [ ${#failed[@]} -gt 0 ] && warn "Some failed: ${failed[*]}"
    [ ${#skipped[@]} -gt 0 ] && warn "Skipped unavailable packages: ${skipped[*]}"
}

# ════════════════════════════════════════════════════════════
# APP CATALOGUE
# Format: "pkg_name|install_method|display_name|category|description"
# install_method: pkg (termux), npm, pip, cargo
# ════════════════════════════════════════════════════════════

BROWSERS=(
    "firefox|pkg|Firefox|browser|Full desktop browser with GPU rendering"
    "chromium|pkg|Chromium|browser|Open-source Chrome — good HTML5 support"
    "lynx|pkg|Lynx|browser|Lightweight terminal browser"
    "w3m|pkg|w3m|browser|Terminal browser with inline image support"
)
EDITORS=(
    "neovim|pkg|Neovim|editor|Modern Vim with LSP support"
    "gedit|pkg|Gedit|editor|GNOME text editor — good for beginners"
    "mousepad|pkg|Mousepad|editor|XFCE default lightweight editor"
    "nano|pkg|Nano|editor|Simple terminal editor"
    "micro|pkg|Micro|editor|Modern terminal editor with mouse support"
    "helix|pkg|Helix|editor|Post-modern modal editor — Rust-based"
    "emacs|pkg|Emacs|editor|The extensible, self-documenting editor"
)
LANGUAGES=(
    "python|pkg|Python 3|lang|Python interpreter + pip"
    "nodejs|pkg|Node.js|lang|JavaScript runtime + npm"
    "ruby|pkg|Ruby|lang|Ruby interpreter + gem"
    "php|pkg|PHP|lang|PHP CLI for web dev"
    "golang|pkg|Go|lang|Google's Go language"
    "rust|pkg|Rust|lang|Systems programming language"
    "openjdk-17|pkg|Java 17 (OpenJDK)|lang|Java runtime + compiler"
    "lua54|pkg|Lua 5.4|lang|Lightweight scripting language"
)
DEVTOOLS=(
    "git|pkg|Git|dev|Version control"
    "curl|pkg|cURL|dev|HTTP client for APIs"
    "openssh|pkg|OpenSSH|dev|SSH server + client"
    "gh|pkg|GitHub CLI|dev|Manage GitHub from terminal"
    "jq|pkg|jq|dev|JSON processor"
    "make|pkg|Make|dev|Build automation"
    "clang|pkg|Clang/LLVM|dev|C/C++ compiler suite"
    "cmake|pkg|CMake|dev|Cross-platform build system"
    "tmux|pkg|tmux|dev|Terminal multiplexer"
    "fzf|pkg|fzf|dev|Fuzzy finder for files and history"
    "ripgrep|pkg|ripgrep|dev|Fast recursive grep"
    "bat|pkg|bat|dev|Syntax-highlighting cat replacement"
)
CODING_TOOLS=(
    "code-server|npm|Code OSS (code-server)|code|VS Code in the browser — web-based IDE"
    "tldr|npm|tldr|code|Simplified man pages"
    "prettier|npm|Prettier|code|Code formatter"
    "eslint|npm|ESLint|code|JavaScript linter"
    "shellcheck|pkg|ShellCheck|code|Shell script linter"
    "delta|pkg|Git Delta|code|Better git diffs with syntax highlighting"
)
AI_TOOLS=(
    "claude-code|npm|Claude Code|ai|Anthropic's AI coding assistant (needs ANTHROPIC_API_KEY)"
    "crush|npm|Crush (OpenCode)|ai|AI-powered TUI — explicitly supports Android/Termux"
    "aider-chat|pip|Aider|ai|AI pair programmer in your terminal"
    "shell-gpt|pip|Shell GPT|ai|Lightweight AI CLI (needs OPENAI_API_KEY)"
    "llm|pip|LLM (Simon Willison)|ai|Multi-model AI CLI tool"
    "gemini-cli|npm|Gemini CLI|ai|Google's AI coding assistant (needs GEMINI_API_KEY)"
    "codex|npm|OpenAI Codex CLI|ai|OpenAI's coding agent (needs OPENAI_API_KEY)"
    "antigravity|npm|Antigravity|ai|AI-powered coding assistant"
)
UTILITIES=(
    "htop|pkg|htop|util|Interactive process viewer"
    "neofetch|pkg|Neofetch|util|System info banner"
    "thunar|pkg|Thunar|util|XFCE file manager"
    "galculator|pkg|Calculator|util|GTK calculator app"
    "xfce4-terminal|pkg|XFCE Terminal|util|Better terminal for XFCE"
    "ranger|pkg|Ranger|util|Terminal file manager"
    "tree|pkg|tree|util|Directory tree viewer"
    "termux-api|pkg|Termux API|util|Access Android APIs from terminal"
)
OFFICE=(
    "libreoffice|pkg|LibreOffice|office|Full office suite"
    "zathura|pkg|Zathura|office|Minimal PDF viewer"
    "evince|pkg|Evince|office|GNOME document viewer"
)
MEDIA=(
    "mpv|pkg|mpv|media|Lightweight media player"
    "feh|pkg|feh|media|Fast image viewer"
    "eog|pkg|Eye of GNOME|media|Full-featured image viewer"
    "ffmpeg|pkg|FFmpeg|media|Video/audio converter"
)

ALL_CATEGORIES=(
    "Browsers:BROWSERS"
    "Code Editors:EDITORS"
    "Programming Languages:LANGUAGES"
    "Dev Tools:DEVTOOLS"
    "Coding Tools:CODING_TOOLS"
    "AI Tools:AI_TOOLS"
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

    local pkg_list=() display_list=() desc_list=() installed_list=() method_list=()
    local selections=()

    for entry in "${items[@]}"; do
        IFS='|' read -r pkg method display cat desc <<< "$entry"
        pkg_list+=("$pkg")
        display_list+=("$display")
        desc_list+=("$desc")
        method_list+=("$method")
        if pkg_installed "$pkg" || npm_installed "$pkg" || pip_installed "$pkg"; then
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
            local method_tag=" ${DIM}[${method_list[$i]}]${NC}"

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
        [ "${selections[$i]}" -eq 1 ] && SELECTED_PKGS+=("${pkg_list[$i]}|${method_list[$i]}")
    done
}

# ════════════════════════════════════════════════════════════
# Interactive checklist (uninstall mode)
# ════════════════════════════════════════════════════════════
REMOVE_PKGS=()

show_uninstall_checklist() {
    local category_name="$1"
    local -n items=$2

    local pkg_list=() display_list=() installed_list=() method_list=()
    local selections=()

    for entry in "${items[@]}"; do
        IFS='|' read -r pkg method display cat desc <<< "$entry"
        if pkg_installed "$pkg" || npm_installed "$pkg" || pip_installed "$pkg"; then
            pkg_list+=("$pkg")
            display_list+=("$display")
            method_list+=("$method")
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
        [ "${selections[$i]}" -eq 1 ] && REMOVE_PKGS+=("${pkg_list[$i]}|${method_list[$i]}")
    done
}

# ════════════════════════════════════════════════════════════
# Main Menu
# ════════════════════════════════════════════════════════════
clear
echo ""
echo "╔══════════════════════════════════════════════════╗"
PROJECT_VER=$(cat "$HOME/.termux-desktop-version" 2>/dev/null || echo "1.4")
echo "║       📦  Termux Desktop — App Manager  v${PROJECT_VER}     ║"
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

        SELECTED_PKGS=($(printf '%s\n' "${SELECTED_PKGS[@]}" | sort -u))

        echo ""
        echo "  Installing ${#SELECTED_PKGS[@]} package(s):"
        for entry in "${SELECTED_PKGS[@]}"; do
            IFS='|' read -r pkg method <<< "$entry"
            echo "   • $pkg ($method)"
        done
        echo ""
        read -rp "  Proceed? [Y/n]: " CONFIRM
        [[ "$CONFIRM" =~ ^[Nn]$ ]] && { echo "Aborted."; exit 0; }

        install_pkg_group "selected apps" "" "${SELECTED_PKGS[@]}"

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
        for entry in "${REMOVE_PKGS[@]}"; do
            IFS='|' read -r pkg method <<< "$entry"
            echo "   • $pkg"
        done
        echo ""
        read -rp "  Confirm removal? [y/N]: " CONFIRM
        [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && { echo "Aborted."; exit 0; }

        COUNT=0
        TOTAL=${#REMOVE_PKGS[@]}
        for entry in "${REMOVE_PKGS[@]}"; do
            COUNT=$((COUNT + 1))
            IFS='|' read -r pkg method <<< "$entry"
            show_progress "$COUNT" "$TOTAL" "Removing $pkg..."
            local removed=false
            case "$method" in
                npm)    npm uninstall -g "$pkg" > /dev/null 2>&1 && removed=true ;;
                pip)    pip uninstall -y "$pkg" > /dev/null 2>&1 && removed=true ;;
                cargo)  cargo uninstall "$pkg" > /dev/null 2>&1 && removed=true ;;
                *)      pkg uninstall -y "$pkg" > /dev/null 2>&1 && removed=true ;;
            esac
            if $removed; then
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
                IFS='|' read -r pkg method display cat desc <<< "$entry"
                if pkg_installed "$pkg" || npm_installed "$pkg" || pip_installed "$pkg"; then
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
