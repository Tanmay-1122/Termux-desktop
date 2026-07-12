#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
#   Termux Desktop — Setup Script
#   Fully automatic — no prompts, no fancy bars
#   Usage:
#     bash setup.sh            -> auto install (minimal)
#     bash setup.sh standard   -> install with useful tools
#     bash setup.sh full       -> install everything
#   Repo : github.com/Tanmay-1122/Termux-desktop
# ============================================================

# Source shared library (installed by install.sh)
LIBSH="$HOME/lib.sh"
[ -f "$LIBSH" ] && source "$LIBSH" 2>/dev/null

# Fallback inline definitions (if lib.sh not found)
if ! declare -F ok &>/dev/null; then
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
    BOLD='\033[1m'; NC='\033[0m'
    ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
    warn() { echo -e "  ${YELLOW}[!!]${NC} $1"; }
    fail() { echo -e "  ${RED}[XX]${NC} $1"; }
    info() { echo -e "       $1"; }
    step() { STEP=$((STEP + 1)); echo -e "\n${BOLD}=== Step $STEP/$TOTAL_STEPS: $1 ===${NC}\n"; }
fi
log_pkg() { echo -e "  [${1}/${2}] Installing $3..."; }

# ── Package install with live progress ─────────────────────────
# Runs pkg install with spinner showing live dpkg progress.
# Usage: timed_pkg_install <packages...>
timed_pkg_install() {
    spinner_run "Installing packages" "$HOME/pkg_install.log" pkg install -y "$@"
    local rc=$?
    if [ $rc -eq 0 ]; then
        local elapsed
        elapsed=$(grep -oP 'Done in \K[0-9]+' "$HOME/pkg_install.log" 2>/dev/null || echo "?")
        echo -e "       ${GREEN}Done${NC}"
    fi
    return $rc
}

PRESET="${1:-minimal}"   # minimal | standard | full
STEP=0
TOTAL_STEPS=7
PROJECT_VER=$(cat "$HOME/.termux-desktop-version" 2>/dev/null || echo "1.4")

FAILED_REQUIRED=()
FAILED_OPTIONAL=()

# ── Architecture ──────────────────────────────────────────────
ARCH=$(uname -m)
IS_AARCH64=false
case "$ARCH" in aarch64|arm64|x86_64) IS_AARCH64=true ;; esac

arch_ok() {
    $IS_AARCH64 && return 0
    case "$1" in firefox|chromium|openjdk-17|golang) return 1 ;; esac
    return 0
}

# ── Package helpers ───────────────────────────────────────────
pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }
pkg_available()  { apt-cache show "$1" >/dev/null 2>&1; }

PKG_UPDATED=false
do_pkg_update() {
    $PKG_UPDATED && return 0
    spinner_run "Updating package lists" "$HOME/pkg_update.log" pkg update -y || true
    PKG_UPDATED=true
    ok "Package lists updated"
}

# Install a group of packages in one shot with a simple fallback
install_group() {
    local label="$1"; shift
    local tier="${1}"; shift      # required | optional
    local pending=()
    local n=0 total=$#

    for pkg in "$@"; do
        [ -z "$pkg" ] && continue
        if ! arch_ok "$pkg"; then
            warn "$pkg skipped (not available on $ARCH)"
            continue
        fi
        if pkg_installed "$pkg"; then
            ok "$pkg already installed"
        elif pkg_available "$pkg"; then
            pending+=("$pkg")
        elif [ "$tier" = "required" ]; then
            fail "$pkg not available in repos"
            FAILED_REQUIRED+=("$pkg")
        else
            warn "$pkg not in repos — skipped"
            FAILED_OPTIONAL+=("$pkg")
        fi
    done

    [ ${#pending[@]} -eq 0 ] && return 0

    local count=${#pending[@]}
    echo "       Installing ${count} package(s): ${pending[*]}"
    echo -e "       ${YELLOW}Please wait — this may take a few minutes...${NC}"

    if timed_pkg_install "${pending[@]}"; then
        ok "$label installed"
        return 0
    fi

    warn "$label batch failed — retrying in 3s..."
    countdown_sleep 3 "  retrying in"
    pkg update -y >/dev/null 2>&1 || true
    if timed_pkg_install "${pending[@]}"; then
        ok "$label installed (retry)"
        return 0
    fi

    # Last resort: one by one
    warn "Trying one by one..."
    local i=0
    for pkg in "${pending[@]}"; do
        i=$((i+1))
        log_pkg "$i" "${#pending[@]}" "$pkg"
        if timed_pkg_install "$pkg"; then
            ok "$pkg installed"
        else
            [ "$tier" = "required" ] && FAILED_REQUIRED+=("$pkg") \
                                     || FAILED_OPTIONAL+=("$pkg")
            warn "$pkg failed"
        fi
    done
}

# ════════════════════════════════════════════════════════════
# BANNER
# ════════════════════════════════════════════════════════════
clear
echo ""
echo "=================================================="
echo "  Termux Desktop Setup v${PROJECT_VER}  |  preset: $PRESET"
echo "  Arch: $ARCH"
echo "=================================================="
echo ""
echo -e "  ${YELLOW}NOTE: Package downloads may take 2-10 minutes.${NC}"
echo -e "  ${YELLOW}Do NOT close Termux during installation!${NC}"
echo ""

# ════════════════════════════════════════════════════════════
# Step 1 — Pre-flight
# ════════════════════════════════════════════════════════════
step "Pre-flight checks"

# Free space — use /data partition available KB
FREE_KB=$(df /data 2>/dev/null | awk 'NR==2{print $4}')
FREE_MB=$(( ${FREE_KB:-999999} / 1024 ))
if [ "$FREE_MB" -lt 500 ] 2>/dev/null; then
    warn "Storage low: ~${FREE_MB} MB free. Install may fail if you run out."
    warn "Tip: clear Downloads folder or uninstall unused apps."
else
    ok "Storage OK (~${FREE_MB} MB free on /data)"
fi

$IS_AARCH64 && ok "Architecture: $ARCH (full catalogue)" \
             || warn "Architecture: $ARCH (firefox/chromium/java/go skipped)"

# ════════════════════════════════════════════════════════════
# Step 2 — Update package lists
# ════════════════════════════════════════════════════════════
step "Updating package lists"
do_pkg_update

# ════════════════════════════════════════════════════════════
# Step 3 — Add x11 repo (must be BEFORE core install)
# ════════════════════════════════════════════════════════════
step "Adding Termux x11 repository"
install_group "x11-repo" "required" x11-repo
echo "       Refreshing index with x11 packages..."
pkg update -y >/dev/null 2>&1 || true
ok "x11 repository ready"

# ════════════════════════════════════════════════════════════
# Step 4 — Core desktop packages
# ════════════════════════════════════════════════════════════
step "Installing core desktop + all display modes"
CORE=(xfce4 termux-x11-nightly pulseaudio dbus wget unzip xrdp tigervnc websockify)
install_group "core desktop" "required" "${CORE[@]}"

# ── GPU / Hardware Acceleration Drivers ─────────────────────
info "Configuring hardware acceleration drivers..."
gpu_pkgs=(mesa-zink virglrenderer-mesa-zink vulkan-loader-android)

# Detect Qualcomm Adreno GPU
is_adreno=false
if getprop ro.hardware 2>/dev/null | grep -qi "qcom" || \
   getprop ro.board.platform 2>/dev/null | grep -qi "msm" || \
   grep -qi "qualcomm" /proc/cpuinfo 2>/dev/null; then
    is_adreno=true
fi

if $is_adreno; then
    info "Qualcomm Adreno GPU detected — adding Turnip Vulkan driver"
    gpu_pkgs+=(mesa-vulkan-icd-freedreno)
fi

install_group "GPU acceleration drivers" "optional" "${gpu_pkgs[@]}"


# ════════════════════════════════════════════════════════════
# Step 5 — Extra apps (based on preset)
# ════════════════════════════════════════════════════════════
step "Installing extra apps (preset: $PRESET)"

case "$PRESET" in
    minimal)
        info "Minimal — skipping extra apps"
        ;;
    full)
        EXTRAS=(git curl openssh htop nano micro neovim python nodejs
                ruby php rust tmux jq tree unzip zip neofetch
                ranger thunar xfce4-terminal galculator mpv feh ffmpeg
                zathura gedit picom)
        install_group "full app bundle" "optional" "${EXTRAS[@]}"
        ;;
    *)  # standard (default)
        EXTRAS=(git curl openssh htop nano micro tree unzip zip python nodejs mpv feh picom)
        install_group "standard apps" "optional" "${EXTRAS[@]}"
        ;;
esac

# ════════════════════════════════════════════════════════════
# Step 6 — Widget shortcuts + theme
# ════════════════════════════════════════════════════════════
step "Creating shortcuts and applying theme"

create_widget_shortcuts
apply_default_theme

# Save version marker
if [ ! -f "$HOME/.termux-desktop-version" ]; then
    REPO_RAW="https://raw.githubusercontent.com/Tanmay-1122/Termux-desktop/main"
    curl -fsSL "$REPO_RAW/VERSION" -o "$HOME/.termux-desktop-version" 2>/dev/null || true
fi
ok "Version: v$(cat "$HOME/.termux-desktop-version" 2>/dev/null || echo '?')"

setup_picom_config

# ── Verify all display modes are ready ────────────────────────
X11_OK=$(command -v termux-x11 >/dev/null 2>&1 && echo true || echo false)
RDP_OK=false
command -v xrdp >/dev/null 2>&1 && command -v vncserver >/dev/null 2>&1 && RDP_OK=true
NOVNC_OK=$(command -v websockify >/dev/null 2>&1 && echo true || echo false)

# ════════════════════════════════════════════════════════════
# Step 7 — Install CLI commands
# ════════════════════════════════════════════════════════════
step "Installing CLI commands"

install_startdesktop_cmd
install_td_update_cmd

# ════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════
echo ""
echo "=================================================="
echo "  Setup Complete!"
echo "=================================================="
echo ""

echo ""
echo "=================================================="
echo "  Display Modes:"
echo "=================================================="
echo ""
$X11_OK  && ok "Termux:X11  — startdesktop" \
        || warn "Termux:X11 — missing termux-x11-nightly"
$RDP_OK  && ok "xRDP        — startdesktop rdp" \
        || warn "xRDP component missing"
$NOVNC_OK && ok "noVNC       — startdesktop novnc" \
        || warn "noVNC component missing"

[ ${#FAILED_REQUIRED[@]} -gt 0 ] && {
    echo ""
    fail "Some required packages failed:"
    for p in "${FAILED_REQUIRED[@]}"; do info "  * $p"; done
    echo ""
    info "Retry: pkg install ${FAILED_REQUIRED[*]}"
}

echo ""
echo -e "${BOLD}  Commands:${NC}"
echo "    startdesktop         <- Termux:X11 (default)"
echo "    startdesktop rdp     <- xRDP mode"
echo "    startdesktop novnc   <- noVNC browser mode"
echo "    startdesktop menu    <- interactive menu"
echo "    startdesktop stop    <- kill desktop session"
echo ""
echo "  Other:"
echo "    td-update             <- check for updates"
echo "    bash ~/manage-apps.sh <- install/remove apps"
echo "    bash ~/theme.sh       <- change theme"
echo "    bash ~/dashboard.sh   <- system health"
echo ""
