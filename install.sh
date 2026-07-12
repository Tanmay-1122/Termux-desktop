#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
#   Termux Desktop — One-Command Installer
#   Installs XFCE4 desktop with GPU acceleration, themes,
#   app manager, dashboard, and self-updater.
#
#   Usage:
#     curl -fsSL https://raw.githubusercontent.com/Tanmay-1122/Termux-desktop/main/install.sh | bash
#
#   Options (pass via env):
#     PRESET=minimal|standard|full   (default: minimal)
#
#   Repo : github.com/Tanmay-1122/Termux-desktop
# ============================================================

set -eo pipefail

# ── Colors ───────────────────────────────────────────────────
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
step() { STEP=$((STEP + 1)); echo -e "\n${BOLD}[$STEP/$TOTAL_STEPS] $1${NC}\n"; }

# ── Variables ────────────────────────────────────────────────
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
PRESET="${PRESET:-${1:-minimal}}"
REPO_RAW="https://raw.githubusercontent.com/Tanmay-1122/Termux-desktop/main"
REPO_CDN="https://cdn.jsdelivr.net/gh/Tanmay-1122/Termux-desktop@main"
REPO_API="https://api.github.com/repos/Tanmay-1122/Termux-desktop"
SCRIPTS=(start-desktop.sh setup.sh theme.sh manage-apps.sh dashboard.sh td-update.sh lib.sh uninstall.sh)
STEP=0
TOTAL_STEPS=6
MAX_RETRIES=3
LOG_FILE="$HOME/termux-desktop-install.log"
PROJECT_VER=$(cat "$HOME/.termux-desktop-version" 2>/dev/null || echo "1.4")

# ── Cleanup trap (rollback on interrupt) ─────────────────────
_cleanup() {
    printf '\e[?25h' 2>/dev/null || true  # restore cursor
    echo ""
    warn "Installation interrupted! Cleaning up..."
    for _s in "${SCRIPTS[@]}"; do
        rm -f "$HOME/$_s" 2>/dev/null || true
    done
    rm -f "$HOME/.termux-desktop-sha256sums" 2>/dev/null || true
    rm -f "$HOME/termux-desktop-install.log" 2>/dev/null || true
    pkill -f virgl_test_server 2>/dev/null || true
    termux-wake-unlock 2>/dev/null || true
    warn "Partial install cleaned up — run the installer again when ready"
    exit 1
}

# ── Logging ──────────────────────────────────────────────────
log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true; }

# ── CDN URL helper ────────────────────────────────────────────
# Converts raw.githubusercontent.com URL to jsDelivr CDN URL
cdn_url() {
    echo "$1" | sed "s|https://raw\.githubusercontent\.com/\([^/]*/[^/]*\)/main/|https://cdn.jsdelivr.net/gh/\1@main/|"
}

# ── Download with retry ─────────────────────────────────────
download() {
    local url="$1" dest="$2"
    local attempt=1
    local cdn
    cdn=$(cdn_url "$url")
    while [ $attempt -le $MAX_RETRIES ]; do
        if curl -fsSL --connect-timeout 10 --max-time 60 "$cdn" -o "$dest" 2>/dev/null; then
            if [ -s "$dest" ]; then return 0; fi
        fi
        if curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$dest" 2>/dev/null; then
            if [ -s "$dest" ]; then return 0; fi
        fi
        rm -f "$dest" 2>/dev/null || true
        attempt=$((attempt + 1))
        [ $attempt -le $MAX_RETRIES ] && countdown_sleep 2
    done
    return 1
}

# ── aria2 download (faster for large files) ───────────────────
# Uses aria2c with multi-connection splitting when available.
# Falls back to curl if aria2 is not installed.
download_fast() {
    local url="$1" dest="$2"
    local cdn
    cdn=$(cdn_url "$url")
    if command -v aria2c &>/dev/null; then
        aria2c -x 4 -s 4 --connect-timeout=10 --timeout=30 \
            --max-tries=3 --retry-wait=2 \
            --allow-overwrite=true --auto-file-renaming=false \
            "$cdn" -d "$(dirname "$dest")" -o "$(basename "$dest")" \
            -q 2>/dev/null && [ -s "$dest" ] && return 0
        aria2c -x 4 -s 4 --connect-timeout=10 --timeout=30 \
            --max-tries=3 --retry-wait=2 \
            --allow-overwrite=true --auto-file-renaming=false \
            "$url" -d "$(dirname "$dest")" -o "$(basename "$dest")" \
            -q 2>/dev/null && [ -s "$dest" ] && return 0
    fi
    download "$url" "$dest"
}

# ── Parallel download batch ───────────────────────────────────
# Downloads multiple files concurrently using background jobs.
# Tries jsDelivr CDN first, falls back to GitHub raw.
# Usage: parallel_download_batch URL_ARRAY DEST_ARRAY
# Both arguments are variable names of arrays (not the arrays themselves).
parallel_download_batch() {
    local -n _urls="$1" _dests="$2"
    local pids=() successes=0 n=${#_urls[@]}

    for i in "${!_urls[@]}"; do
        (
            local url="${_urls[$i]}"
            local cdn
            cdn=$(cdn_url "$url")
            curl -fsSL --connect-timeout 10 --max-time 60 "$cdn" -o "${_dests[$i]}" 2>/dev/null || \
            curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "${_dests[$i]}" 2>/dev/null
        ) &
        pids+=($!)
    done

    # Show live download status while waiting
    local dl_start=$SECONDS
    while true; do
        local alive=0
        for pid in "${pids[@]}"; do
            kill -0 "$pid" 2>/dev/null && alive=$((alive + 1))
        done
        [ $alive -eq 0 ] && break

        local done_count=0
        for f in "${_dests[@]}"; do
            [ -s "$f" ] && done_count=$((done_count + 1))
        done
        local elapsed=$((SECONDS - dl_start))
        printf "\r  \033[0;36m\u2193\033[0m %d/%d files \033[2m[%ds]\033[0m" \
            "$done_count" "$n" "$elapsed"
        sleep 1
    done
    printf "\r\033[K"

    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null && successes=$((successes + 1)) || true
    done

    if [ $successes -lt $n ]; then
        warn "Downloaded $successes/$n files"
        return 1
    fi
    return 0
}

# ── Spinner with live progress ──────────────────────────────
# Runs command in background, shows animated spinner + elapsed
# time + last significant line from log file.
# Hides cursor while running, restores on completion.
# Usage: spinner_run "Label" /path/to/log cmd arg1 arg2 ...
spinner_run() {
    local label="$1"
    local log_file="$2"
    shift 2
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
    : > "$log_file"

    "$@" > "$log_file" 2>&1 &
    local pid=$!

    local spin='-\|/'
    local i=0
    local start_time=$SECONDS
    printf '\e[?25l'

    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$((SECONDS - start_time))
        local last_line
        last_line=$(tail -3 "$log_file" 2>/dev/null | \
            grep -vE '^(\[\*\]|Progress:|Get:|Fetched |Hit:|Reading |Building |WARNING:|$)' | \
            grep -vE 'https?://' | \
            tail -1)
        last_line="${last_line:0:60}"

        if [ -n "$last_line" ]; then
            printf "\r  \033[0;36m%c\033[0m \033[1m%s\033[0m \033[2m[%ds]\033[0m  %s" \
                "${spin:$i:1}" "$label" "$elapsed" "$last_line"
        else
            printf "\r  \033[0;36m%c\033[0m \033[1m%s\033[0m \033[2m[%ds]\033[0m" \
                "${spin:$i:1}" "$label" "$elapsed"
        fi

        i=$(( (i+1) % 4 ))
        sleep 0.5
    done

    wait "$pid"
    local rc=$?

    printf '\e[?25h\r\033[K'
    return $rc
}

# ── Animated countdown sleep ──────────────────────────────────
# Replaces silent sleep with a visible countdown.
# Usage: countdown_sleep <seconds> [message]
countdown_sleep() {
    local secs="$1" msg="${2:-  waiting}"
    while [ $secs -gt 0 ]; do
        printf "\r%s \033[2m%ds\033[0m" "$msg" "$secs"
        sleep 1
        secs=$((secs - 1))
    done
    printf "\r\033[K"
}

# ── Install packages with retry ──────────────────────────────
install_pkgs() {
    local label="$1"; shift
    local pkgs="$*"
    local attempt=1
    local wrapper=()
    command -v eatmydata &>/dev/null && wrapper=(eatmydata)
    while [ $attempt -le $MAX_RETRIES ]; do
        log "Installing $label (attempt $attempt): $pkgs"
        if spinner_run "$label" "$LOG_FILE" "${wrapper[@]}" pkg install -y $pkgs; then
            ok "$label installed"
            return 0
        fi
        warn "$label attempt $attempt failed, retrying..."
        spinner_run "$label (dpkg fix)" "$LOG_FILE" dpkg --configure -a
        spinner_run "$label (apt fix)" "$LOG_FILE" apt --fix-broken install -y
        spinner_run "$label (pkg update)" "$LOG_FILE" pkg update -y
        attempt=$((attempt + 1))
        countdown_sleep 3
    done
    warn "$label had issues — check $LOG_FILE"
    return 1
}

# ── GPU Detection ────────────────────────────────────────────
detect_gpu() {
    local gpu="unknown"
    local hw=$(getprop ro.hardware 2>/dev/null || true)
    local board=$(getprop ro.board.platform 2>/dev/null || true)

    if echo "$hw $board" | grep -qi "qcom\|msm\|snapdragon"; then
        gpu="adreno"
    elif echo "$hw $board" | grep -qi "mali\|arm\|exynos"; then
        gpu="mali"
    elif echo "$hw $board" | grep -qi "xclipse"; then
        gpu="xclipse"
    fi
    echo "$gpu"
}

# ════════════════════════════════════════════════════════════
# Banner
# ════════════════════════════════════════════════════════════
echo ""
echo "=================================================="
echo "  Termux Desktop — Installer v${PROJECT_VER}"
echo "  Preset: $PRESET"
echo "=================================================="
echo ""
echo -e "  ${YELLOW}Do NOT close Termux during installation!${NC}"
echo -e "  ${YELLOW}Package downloads may take 2-10 minutes.${NC}"
echo ""

trap _cleanup INT TERM

# ── Step 1: Verify environment ──────────────────────────────
step "Verifying environment"

if [ ! -d "/data/data/com.termux" ]; then
    fail "This must be run inside Termux."
fi
ok "Running inside Termux"

# Check Android version
ANDROID_VER=$(getprop ro.build.version.release 2>/dev/null || echo "unknown")
ok "Android $ANDROID_VER"

# Detect GPU
GPU=$(detect_gpu)
info "GPU detected: $GPU"

# Check free space
FREE_KB=$(df /data 2>/dev/null | awk 'NR==2{print $4}')
FREE_MB=$(( ${FREE_KB:-999999} / 1024 ))
if [ "$FREE_MB" -lt 500 ] 2>/dev/null; then
    warn "Low storage: ~${FREE_MB} MB free"
else
    ok "Storage: ~${FREE_MB} MB free"
fi

# ── Step 2: Update & install dependencies ────────────────────
step "Installing dependencies"

termux-wake-lock 2>/dev/null || true
info "Wake lock acquired"

# ── Mirror Registry (top 3 per region, by bandwidth) ────────
MIRROR_ASIA=(
    "https://mirrors.ravidwivedi.in/termux/termux-main"
    "https://termux.niranjan.co/termux-main"
    "https://mirror.twds.com.tw/termux/termux-main"
)
MIRROR_EUROPE=(
    "https://ftp.fau.de/termux/termux-main"
    "https://mirror.bouwhuis.network/termux/termux-main"
    "https://grimler.se/termux/termux-main"
)
MIRROR_NA=(
    "https://packages-cf.termux.dev/apt/termux-main"
    "https://plug-mirror.rcac.purdue.edu/termux/termux-main"
    "https://mirrors.utermux.dev/termux/termux-main"
)
GLOBAL_FALLBACK="https://packages-cf.termux.dev/apt/termux-main"

# ── Geo-detect region (fast, <2s) ──────────────────────────
detect_region() {
    local cc
    cc=$(wget -q -O- --timeout=3 "https://ipapi.co/json/" 2>/dev/null \
        | grep -o '"country_code":"[^"]*"' | cut -d'"' -f4 2>/dev/null)
    case "${cc^^}" in
        IN|PK|BD|LK|NP|MM|TH|VN|MY|ID|PH|SG|TW|JP|KR|CN|HK|BN|KH|LA) echo "asia" ;;
        AU|NZ) echo "asia" ;;
        DE|GB|FR|NL|SE|FI|PL|ES|IT|PT|CH|AT|BE|DK|NO|IE|CZ|RO|HU|BG|HR|SK|SI|LT|LV|EE|LU|MT|CY|GR|IS|LI|MC|AD|SM|VA) echo "europe" ;;
        US|CA|MX|BR|AR|CL|CO|PE|VE|EC|BO|PY|UY|PA|CR|NI|HN|GT|SV|DO|CU|JM|TT|GY|SR|GF|HT) echo "north_america" ;;
        *) echo "unknown" ;;
    esac
}

# ── Test mirrors in parallel (background jobs) ───────────────
test_mirrors_parallel() {
    local mirrors=("$@")
    local tmpdir
    tmpdir=$(mktemp -d 2>/dev/null || echo "/tmp/mirror_test_$$")
    mkdir -p "$tmpdir"
    local pids=()
    local start_times=()

    for i in "${!mirrors[@]}"; do
        local mirror="${mirrors[$i]}"
        local start_ms
        start_ms=$(date +%s%N 2>/dev/null || echo "0")
        wget -O "$tmpdir/r_$i" --timeout=5 --tries=1 \
            -q "$mirror/dists/stable/InRelease" 2>/dev/null &
        pids+=($!)
        start_times+=($start_ms)
    done

    # Wait for all, pick fastest
    local best_mirror="" best_time=999999
    for i in "${!pids[@]}"; do
        wait "${pids[$i]}" 2>/dev/null
        local end_ms
        end_ms=$(date +%s%N 2>/dev/null || echo "0")
        if [ -f "$tmpdir/r_$i" ] && [ -s "$tmpdir/r_$i" ]; then
            local elapsed_ms=$(( (end_ms - ${start_times[$i]}) / 1000000 ))
            [ "$elapsed_ms" -le 0 ] && elapsed_ms=1
            if [ "$elapsed_ms" -lt "$best_time" ]; then
                best_time=$elapsed_ms
                best_mirror="${mirrors[$i]}"
            fi
        fi
        rm -f "$tmpdir/r_$i" 2>/dev/null
    done

    rm -rf "$tmpdir" 2>/dev/null
    echo "$best_mirror"
}

# ── Auto-select fastest mirror ───────────────────────────────
info "Finding fastest mirror for your region..."
FASTEST_MIRROR=""

if command -v wget &>/dev/null; then
    # Step 1: Detect region
    REGION=$(detect_region)
    info "Region: $REGION"

    # Step 2: Test top mirrors from detected region in parallel
    case "$REGION" in
        asia)          CANDIDATES=("${MIRROR_ASIA[@]}") ;;
        europe)        CANDIDATES=("${MIRROR_EUROPE[@]}") ;;
        north_america) CANDIDATES=("${MIRROR_NA[@]}") ;;
        unknown)       CANDIDATES=("${MIRROR_NA[@]}" "${MIRROR_EUROPE[@]}" "${MIRROR_ASIA[@]}") ;;
    esac

    FASTEST_MIRROR=$(test_mirrors_parallel "${CANDIDATES[@]}")

    # Step 3: If regional test failed, test one from each region
    if [ -z "$FASTEST_MIRROR" ]; then
        info "Regional test failed — testing global top mirrors..."
        GLOBAL_CANDIDATES=("${MIRROR_NA[0]}" "${MIRROR_EUROPE[0]}" "${MIRROR_ASIA[0]}")
        FASTEST_MIRROR=$(test_mirrors_parallel "${GLOBAL_CANDIDATES[@]}")
    fi

    # Step 4: Ultimate fallback — CloudFlare CDN
    if [ -z "$FASTEST_MIRROR" ]; then
        FASTEST_MIRROR="$GLOBAL_FALLBACK"
    fi
fi

# Apply mirror configuration
if [ -n "$FASTEST_MIRROR" ]; then
    info "Using mirror: $FASTEST_MIRROR"
    X11_MIRROR=$(echo "$FASTEST_MIRROR" | sed 's|termux-main|termux-x11|')
    mkdir -p "$PREFIX/etc/apt"
    cat > "$PREFIX/etc/apt/sources.list" << MIRROR_EOF
deb $FASTEST_MIRROR stable main
deb $X11_MIRROR x11 main
MIRROR_EOF
    ok "Mirror configured"
else
    warn "Could not test mirrors — using default"
fi

# ── Enable apt parallel downloads (10 simultaneous) ──────────
mkdir -p "$PREFIX/etc/apt/apt.conf.d"
cat > "$PREFIX/etc/apt/apt.conf.d/99parallel" << 'PARALLEL_EOF'
Acquire::PDGM::Limit "10";
Acquire::Languages "none";
DPkg::Options {
    "--force-unsafe-io";
};
PARALLEL_EOF
ok "Parallel downloads enabled (10 streams)"

# ── Force IPv4 for APT (fixes slow/stalled downloads on mobile carriers with broken IPv6)
cat > "$PREFIX/etc/apt/apt.conf.d/00forceipv4" << 'IPV4_EOF'
Acquire::ForceIPv4 "true";
IPV4_EOF
ok "IPv4 forced for APT"

log "Running pkg update"
spinner_run "Updating package lists" "$LOG_FILE" pkg update -y || true
ok "Package lists updated"

# x11 repo (required for xfce4 and termux-x11)
info "Adding x11 repository..."
spinner_run "x11-repo & eatmydata" "$LOG_FILE" pkg install -y x11-repo eatmydata || true
spinner_run "Updating with x11 repo" "$LOG_FILE" pkg update -y || true
ok "x11-repo ready"

# Core packages
install_pkgs "core desktop" xfce4 termux-x11-nightly pulseaudio dbus wget unzip aria2 xrdp tigervnc websockify

# GPU drivers
info "Installing GPU acceleration packages..."
GPU_PKGS="mesa-zink virglrenderer-mesa-zink vulkan-loader-android"
if [ "$GPU" = "adreno" ]; then
    GPU_PKGS="$GPU_PKGS mesa-vulkan-icd-freedreno"
fi
if spinner_run "GPU drivers" "$LOG_FILE" pkg install -y $GPU_PKGS; then
    ok "GPU acceleration packages installed"
else
    warn "Some GPU packages failed — see $LOG_FILE"
    warn "Desktop will fall back to software rendering"
fi

# Extra apps based on preset
case "$PRESET" in
    full)
        install_pkgs "full apps" git curl openssh htop nano micro neovim python nodejs ruby php rust tmux jq tree neofetch ranger thunar xfce4-terminal galculator mpv feh ffmpeg zathura gedit
        install_pkgs "picom compositor" picom
        ;;
    standard)
        install_pkgs "standard apps" git curl openssh htop nano micro tree python nodejs mpv feh
        install_pkgs "picom compositor" picom
        ;;
    *)
        info "Minimal preset — skipping extra apps"
        ;;
esac

# ── Step 3: Download scripts ─────────────────────────────────
step "Downloading desktop scripts"

mkdir -p "$HOME/.shortcuts"
mkdir -p "$PREFIX/share/wallpapers"
mkdir -p "$PREFIX/etc/termux-desktop"

# Download scripts + version + checksums in parallel
SCRIPT_URLS=() SCRIPT_DESTS=()
for script in "${SCRIPTS[@]}"; do
    SCRIPT_URLS+=("$REPO_RAW/$script")
    SCRIPT_DESTS+=("$HOME/$script")
done
SCRIPT_URLS+=("$REPO_RAW/VERSION" "$REPO_RAW/sha256sums.txt")
SCRIPT_DESTS+=("$HOME/.termux-desktop-version" "$HOME/.termux-desktop-sha256sums")

info "Downloading desktop files (${#SCRIPT_URLS[@]} files in parallel)..."
if parallel_download_batch SCRIPT_URLS SCRIPT_DESTS; then
    ok "All desktop files downloaded"
else
    warn "Some files failed — continuing"
fi

for script in "${SCRIPTS[@]}"; do
    if [ -s "$HOME/$script" ]; then
        chmod +x "$HOME/$script"
        ok "$script"
    else
        warn "Failed: $script"
    fi
done
[ -s "$HOME/.termux-desktop-version" ] && ok "VERSION file" || true
[ -s "$HOME/.termux-desktop-sha256sums" ] && ok "sha256sums.txt" || true

# Verify integrity of downloaded scripts
if [ -f "$HOME/.termux-desktop-sha256sums" ] && declare -F verify_integrity &>/dev/null; then
    verify_integrity "$HOME/.termux-desktop-sha256sums" "$HOME" || warn "Some files may be corrupted — install anyway"
fi

# Source lib.sh (downloaded above) for shared functions
[ -f "$HOME/lib.sh" ] && source "$HOME/lib.sh" 2>/dev/null || true

# Download configs + wallpapers in parallel
mkdir -p "$PREFIX/share/termux-desktop" "$PREFIX/share/wallpapers" 2>/dev/null
CONFIG_WALL_URLS=() CONFIG_WALL_DESTS=()
CONFIG_WALL_URLS+=("$REPO_RAW/picom.conf" "$REPO_RAW/gtk-base.css")
CONFIG_WALL_DESTS+=("$PREFIX/share/termux-desktop/picom.conf" "$PREFIX/share/termux-desktop/gtk-base.css")

WALLPAPERS="nord.jpg catppuccin-mocha.jpg catppuccin-latte.jpg solarized-dark.jpg tokyo-night.jpg tokyo-night-light.jpg gruvbox-dark.jpg rose-pine.jpg"
for wp in $WALLPAPERS; do
    CONFIG_WALL_URLS+=("$REPO_RAW/wallpapers/${wp}")
    CONFIG_WALL_DESTS+=("$PREFIX/share/wallpapers/${wp}")
done

info "Downloading configs and wallpapers (${#CONFIG_WALL_URLS[@]} files in parallel)..."
if parallel_download_batch CONFIG_WALL_URLS CONFIG_WALL_DESTS; then
    ok "All configs and wallpapers downloaded"
else
    warn "Some configs/wallpapers had issues"
fi
[ -s "$PREFIX/share/termux-desktop/picom.conf" ] && ok "picom.conf" || true
[ -s "$PREFIX/share/termux-desktop/gtk-base.css" ] && ok "gtk-base.css" || true
for wp in $WALLPAPERS; do
    [ -s "$PREFIX/share/wallpapers/${wp}" ] && ok "wallpaper: $wp" || true
done

# ── Step 4: GPU environment setup ────────────────────────────
step "Configuring GPU acceleration"

# Save GPU config
cat > "$PREFIX/etc/termux-desktop/gpu.conf" << GPUEOF
# GPU Configuration
GPU_NAME=$GPU
ENABLE_HW_ACC=true
GPUEOF

if [ "$GPU" = "adreno" ]; then
    info "Adreno GPU detected — Freedreno/Turnip driver will be used"
elif [ "$GPU" = "mali" ]; then
    info "Mali GPU detected — VirGL renderer will be used"
else
    info "Unknown GPU — software rendering fallback"
fi
ok "GPU config saved"

# ── Step 5: Create shortcuts & commands ──────────────────────
step "Setting up shortcuts and commands"

# Use lib.sh functions if available, otherwise inline
if declare -F create_widget_shortcuts &>/dev/null; then
    create_widget_shortcuts
else
    mkdir -p "$HOME/.shortcuts" 2>/dev/null
    cat > "$HOME/.shortcuts/Start Desktop.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
bash "$HOME/start-desktop.sh"
EOF
    chmod +x "$HOME/.shortcuts/Start Desktop.sh"
    cat > "$HOME/.shortcuts/Manage Apps.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
bash "$HOME/manage-apps.sh"
EOF
    chmod +x "$HOME/.shortcuts/Manage Apps.sh"
    cat > "$HOME/.shortcuts/Change Theme.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
bash "$HOME/theme.sh"
EOF
    chmod +x "$HOME/.shortcuts/Change Theme.sh"
    cat > "$HOME/.shortcuts/Check Updates.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
bash "$HOME/td-update.sh"
EOF
    chmod +x "$HOME/.shortcuts/Check Updates.sh"
    ok "4 widget shortcuts created"
fi

if declare -F install_startdesktop_cmd &>/dev/null; then
    install_startdesktop_cmd
else
    cat > "$PREFIX/bin/startdesktop" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
HOME=/data/data/com.termux/files/home
exec bash "$HOME/start-desktop.sh" "${@}"
EOF
    chmod +x "$PREFIX/bin/startdesktop"
    ok "'startdesktop' command installed"
fi

if declare -F install_td_update_cmd &>/dev/null; then
    install_td_update_cmd
else
    cat > "$PREFIX/bin/td-update" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
HOME=/data/data/com.termux/files/home
exec bash "$HOME/td-update.sh" "${@}"
EOF
    chmod +x "$PREFIX/bin/td-update"
    ok "'td-update' command installed"
fi

# Save version marker (already downloaded above, but ensure it exists)
if [ ! -f "$HOME/.termux-desktop-version" ]; then
    curl -fsSL "$REPO_RAW/VERSION" -o "$HOME/.termux-desktop-version" 2>/dev/null || true
fi
ok "Version: v$(cat "$HOME/.termux-desktop-version" 2>/dev/null || echo '?')"

if declare -F apply_default_theme &>/dev/null; then
    apply_default_theme
else
    [ -f "$HOME/theme.sh" ] && bash "$HOME/theme.sh" --auto nord 2>/dev/null && ok "Nord theme applied" || true
fi

if declare -F setup_picom_config &>/dev/null; then
    setup_picom_config
else
    if [ -f "$PREFIX/share/termux-desktop/picom.conf" ]; then
        mkdir -p "$HOME/.config/picom" 2>/dev/null
        cp "$PREFIX/share/termux-desktop/picom.conf" "$HOME/.config/picom/picom.conf" 2>/dev/null
        ok "Picom blur config installed" || true
    fi
fi

# ── Step 6: Summary ──────────────────────────────────────────
step "Installation complete!"

echo ""
echo "=================================================="
echo "  Termux Desktop v${PROJECT_VER} — Ready!"
echo "=================================================="
echo ""
echo -e "  ${BOLD}Available display modes:${NC}"
echo "    startdesktop          <- Termux:X11 (default)"
echo "    startdesktop rdp      <- xRDP (Windows Remote Desktop)"
echo "    startdesktop novnc    <- noVNC (any browser)"
echo "    startdesktop menu     <- interactive picker"
echo ""
echo -e "  ${BOLD}Options:${NC}"
echo "    startdesktop --nogpu  <- no GPU acceleration"
echo "    startdesktop --legacy <- legacy X11 drawing"
echo ""
echo -e "  ${BOLD}Other commands:${NC}"
echo "    td-update             <- check for updates"
echo "    bash ~/manage-apps.sh <- install/remove apps"
echo "    bash ~/theme.sh       <- change theme (8 themes)"
echo "    bash ~/dashboard.sh   <- system health"
echo ""
echo -e "  ${BOLD}GPU:${NC} $GPU"
echo -e "  ${BOLD}Log:${NC} $LOG_FILE"
echo ""
echo -e "  ${CYAN}Open Termux:X11 app on your phone, then run 'startdesktop'${NC}"
echo ""
