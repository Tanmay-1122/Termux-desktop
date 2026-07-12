#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
#   Termux Desktop — Self-Update Checker
#   Checks for newer versions and updates in-place.
#
#   Usage:
#     td-update              # check + offer update
#     td-update --check      # check only (no install)
#     td-update --force      # reinstall current version
#     td-update --changelog  # show recent changes
#
#   Repo : github.com/Tanmay-1122/Termux-desktop
# ============================================================

set -eo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!!]${NC} $1"; }
fail() { echo -e "  ${RED}[XX]${NC} $1"; exit 1; }
info() { echo -e "  ${CYAN}->${NC} $1"; }

REPO="Tanmay-1122/Termux-desktop"
RAW_BASE="https://raw.githubusercontent.com/$REPO/main"
API_BASE="https://api.github.com/repos/$REPO"
PKG_NAME="termux-dex"

# Force Termux paths — may be overridden by parent environment (e.g. Windows host via ADB)
if [ -d "/data/data/com.termux" ]; then
    PREFIX="/data/data/com.termux/files/usr"
    HOME="/data/data/com.termux/files/home"
    TMPDIR="$PREFIX/tmp"
else
    PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
    HOME="${HOME:-/data/data/com.termux/files/home}"
    TMPDIR="${TMPDIR:-$PREFIX/tmp}"
fi
export PREFIX HOME TMPDIR

MODE="check"
for arg in "$@"; do
    case "$arg" in
        --check)    MODE="check" ;;
        --force)    MODE="force" ;;
        --changelog) MODE="changelog" ;;
        --help|-h)
            echo "Usage: td-update [--check|--force|--changelog]"
            echo ""
            echo "  (no args)   Check for updates and install if available"
            echo "  --check     Check only, don't install"
            echo "  --force     Reinstall current version"
            echo "  --changelog Show recent commit history"
            exit 0
            ;;
    esac
done

# ── Get installed version ─────────────────────────────────────
get_installed_version() {
    local ver=""
    # Method 1: dpkg (if installed as .deb)
    if command -v dpkg &>/dev/null; then
        ver=$(dpkg -s "$PKG_NAME" 2>/dev/null | grep '^Version:' | awk '{print $2}')
    fi
    # Method 2: version file fallback
    if [ -z "$ver" ] && [ -f "$HOME/.termux-desktop-version" ]; then
        ver=$(cat "$HOME/.termux-desktop-version" 2>/dev/null)
    fi
    echo "${ver:-0}"
}

# ── Get latest version from GitHub ────────────────────────────
get_latest_version() {
    local ver=""

    # Method 1: GitHub API releases (if any exist)
    if command -v curl &>/dev/null; then
        ver=$(curl -fsSL "$API_BASE/releases/latest" 2>/dev/null \
            | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"v\?\([^"]*\)".*/\1/')
    fi

    # Method 2: Fetch the control file from repo (always works)
    if [ -z "$ver" ]; then
        local control
        control=$(curl -fsSL "$RAW_BASE/termux-dex-pkgsrc/termux-dex_1.0_all/DEBIAN/control" 2>/dev/null)
        ver=$(echo "$control" | grep '^Version:' | awk '{print $2}')
    fi

    echo "${ver:-0}"
}

# ── Compare versions (returns 0 if $1 >= $2) ──────────────────
version_gte() {
    [ "$(printf '%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

# ── Fetch changelog (recent commits) ──────────────────────────
show_changelog() {
    echo ""
    echo -e "${CYAN}${BOLD}  Recent changes in Termux Desktop:${NC}"
    echo ""

    if command -v curl &>/dev/null; then
        local commits
        commits=$(curl -fsSL "$API_BASE/commits?per_page=15" 2>/dev/null)
        if [ -n "$commits" ]; then
            echo "$commits" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for c in data:
        msg = c['commit']['message'].split(chr(10))[0][:72]
        date = c['commit']['author']['date'][:10]
        sha = c['sha'][:7]
        print(f'  {date}  {sha}  {msg}')
except:
    pass
" 2>/dev/null || {
            # Fallback: simple parse without python
            echo "$commits" | grep '"message"' | head -10 \
                | sed 's/.*"message": *"\([^"]*\)".*/  \1/' \
                | sed 's/\\n.*//'
        }
        fi
    else
        warn "curl not found — cannot fetch changelog"
    fi

    echo ""
}

# ── Download and install update ────────────────────────────────
do_update() {
    local latest_ver="$1"
    local deb_url="$RAW_BASE/repo/termux-dex_${latest_ver}_all.deb"
    local deb_path="$HOME/termux-dex_${latest_ver}_all.deb"

    echo ""
    info "Downloading termux-dex v${latest_ver}..."
    echo "       URL: $deb_url"

    local dl_ok=false
    if command -v aria2c &>/dev/null; then
        aria2c -x 4 -s 4 --connect-timeout=10 --timeout=30 \
            --max-tries=3 --retry-wait=2 \
            --allow-overwrite=true --auto-file-renaming=false \
            "$deb_url" -d "$HOME" -o "termux-dex_${latest_ver}_all.deb" \
            -q 2>/dev/null && dl_ok=true
    fi
    if ! $dl_ok; then
        if ! curl -fsSL --retry 2 --retry-delay 3 "$deb_url" -o "$deb_path" 2>/dev/null; then
            fail "Download failed after 3 attempts. Check your connection or try again later."
        fi
    fi

    ok "Downloaded $(du -h "$deb_path" | cut -f1)"

    echo ""
    info "Installing update..."
    if pkg install -y "$deb_path" 2>/dev/null || dpkg -i "$deb_path" 2>/dev/null; then
        ok "Updated to v${latest_ver}!"
        # Save version marker
        echo "$latest_ver" > "$HOME/.termux-desktop-version" 2>/dev/null || true
    else
        warn "Package install had issues — trying dpkg directly..."
        if dpkg -i --force-depends "$deb_path" 2>/dev/null; then
            ok "Updated to v${latest_ver} (forced)"
            echo "$latest_ver" > "$HOME/.termux-desktop-version" 2>/dev/null || true
        else
            fail "Install failed. The .deb is at: $deb_path"
        fi
    fi

    # Cleanup
    rm -f "$deb_path" 2>/dev/null || true

    echo ""
    echo -e "${GREEN}${BOLD}  Update complete!${NC}"
    echo "  Restart your session to use the new version."
    echo ""
}

# ════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════

clear
echo ""
echo "=================================================="
PROJECT_VER=$(cat "$HOME/.termux-desktop-version" 2>/dev/null || echo "1.4")
echo "  Termux Desktop — Update Checker v${PROJECT_VER}"
echo "=================================================="
echo ""

# Changelog mode
if [ "$MODE" = "changelog" ]; then
    show_changelog
    exit 0
fi

# Check connectivity
info "Checking connectivity..."
if ! curl -fsSL --max-time 10 "$API_BASE" &>/dev/null; then
    warn "Cannot reach GitHub — check your internet connection."
    exit 1
fi
ok "Connected to GitHub"

# Get versions
INSTALLED=$(get_installed_version)
info "Installed version: ${INSTALLED}"
LATEST=$(get_latest_version)
info "Latest version   : ${LATEST}"

echo ""

# Compare
if [ "$LATEST" = "0" ] || [ -z "$LATEST" ]; then
    warn "Could not determine latest version."
    warn "Visit https://github.com/$REPO manually."
    exit 1
fi

if [ "$INSTALLED" = "0" ] || [ -z "$INSTALLED" ]; then
    warn "No installed version found."
    echo ""
    echo -e "  ${YELLOW}Would you like to install Termux Desktop v${LATEST} fresh?${NC}"
    read -rp "  Install now? [Y/n]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
        echo "  Skipped. Run 'td-update' later to install."
        exit 0
    fi
    do_update "$LATEST"
    exit 0
fi

if [ "$MODE" = "force" ]; then
    info "Force mode — reinstalling v${INSTALLED}..."
    do_update "$INSTALLED"
    exit 0
fi

if [ "$LATEST" = "$INSTALLED" ]; then
    ok "You're up to date! (v${INSTALLED})"
    echo ""
    exit 0
fi

if version_gte "$INSTALLED" "$LATEST"; then
    ok "You're ahead of latest (installed: v${INSTALLED}, latest: v${LATEST})"
    echo ""
    exit 0
fi

# Update available
echo -e "  ${YELLOW}${BOLD}Update available!${NC}"
echo -e "  Installed: ${RED}v${INSTALLED}${NC}  ->  Latest: ${GREEN}v${LATEST}${NC}"
echo ""

if [ "$MODE" = "check" ]; then
    read -rp "  Update now? [Y/n]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
        echo "  Skipped. Run 'td-update' later to update."
        exit 0
    fi
fi

do_update "$LATEST"
