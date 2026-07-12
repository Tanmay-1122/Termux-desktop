# ============================================================
#   Termux Desktop — Shared Library
#   Source this in other scripts:  source lib.sh
#   Repo : github.com/Tanmay-1122/Termux-desktop
# ============================================================

# ── Colors (safe to redefine) ────────────────────────────────
GREEN='\033[0;32m';  YELLOW='\033[1;33m'
RED='\033[0;31m';    CYAN='\033[0;36m'
BOLD='\033[1m';      DIM='\033[2m'
NC='\033[0m'

# ── Logging helpers ─────────────────────────────────────────
ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!!]${NC} $1"; }
fail() { echo -e "  ${RED}[XX]${NC} $1"; exit 1; }
info() { echo -e "  ${CYAN}->${NC} $1"; }
step() { STEP=$((STEP + 1)); echo -e "\n${BOLD}[$STEP/$TOTAL_STEPS] $1${NC}\n"; }

# ── Paths ──────────────────────────────────────────────────
[ -d "/data/data/com.termux" ] && {
    export PREFIX="/data/data/com.termux/files/usr"
    export HOME="/data/data/com.termux/files/home"
    export TMPDIR="$PREFIX/tmp"
}
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"

# ── Project version ─────────────────────────────────────────
get_project_ver() {
    local v
    v=$(cat "$HOME/.termux-desktop-version" 2>/dev/null)
    echo "${v:-1.4}"
}

# ── GPU detection ──────────────────────────────────────────
detect_gpu() {
    local hw=$(getprop ro.hardware 2>/dev/null || true)
    local board=$(getprop ro.board.platform 2>/dev/null || true)
    if echo "$hw $board" | grep -qi "qcom\|msm\|snapdragon"; then echo "adreno"
    elif echo "$hw $board" | grep -qi "mali\|arm\|exynos"; then echo "mali"
    elif echo "$hw $board" | grep -qi "xclipse"; then echo "xclipse"
    else echo "unknown"; fi
}

# ── Widget shortcuts ───────────────────────────────────────
create_widget_shortcuts() {
    local d="$HOME/.shortcuts"
    mkdir -p "$d" && chmod 700 "$d"
    cat > "$d/Start Desktop.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
bash "$HOME/start-desktop.sh"
EOF
    chmod +x "$d/Start Desktop.sh"
    cat > "$d/Manage Apps.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
bash "$HOME/manage-apps.sh"
EOF
    chmod +x "$d/Manage Apps.sh"
    cat > "$d/Change Theme.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
bash "$HOME/theme.sh"
EOF
    chmod +x "$d/Change Theme.sh"
    cat > "$d/Check Updates.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
bash "$HOME/td-update.sh"
EOF
    chmod +x "$d/Check Updates.sh"
    ok "4 widget shortcuts created"
}

# ── Install CLI commands ───────────────────────────────────
install_startdesktop_cmd() {
    local bin="${PREFIX}/bin/startdesktop"
    cat > "$bin" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
HOME=/data/data/com.termux/files/home
exec bash "$HOME/start-desktop.sh" "${@}"
EOF
    chmod +x "$bin"
    ok "'startdesktop' command installed"
}

install_td_update_cmd() {
    local bin="${PREFIX}/bin/td-update"
    cat > "$bin" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
HOME=/data/data/com.termux/files/home
exec bash "$HOME/td-update.sh" "${@}"
EOF
    chmod +x "$bin"
    ok "'td-update' command installed"
}

# ── Apply theme (if available) ──────────────────────────────
apply_default_theme() {
    if [ -f "$HOME/theme.sh" ]; then
        bash "$HOME/theme.sh" --auto nord 2>/dev/null && ok "Nord theme applied" || true
    fi
}

# ── Picom config ───────────────────────────────────────────
setup_picom_config() {
    local src="$PREFIX/share/termux-desktop/picom.conf"
    local dst="$HOME/.config/picom/picom.conf"
    if [ -f "$src" ]; then
        mkdir -p "$HOME/.config/picom" 2>/dev/null
        cp "$src" "$dst" 2>/dev/null && ok "Picom blur config installed" || true
    fi
}

# ── SHA-256 integrity verification ────────────────────────────
# Checks downloaded scripts/configs against repo checksums.
# Best-effort: detects corruption but (without GPG signing)
# does not guarantee authenticity.
verify_integrity() {
    local sums_file="$1"
    local target_dir="$2"
    local failed=0 missing=0 ok=0

    if [ ! -f "$sums_file" ]; then
        warn "Checksums file not found — skipping verification"
        return 0
    fi

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local expected_hash file name
        expected_hash=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{print $2}')
        file="$target_dir/$name"

        if [ ! -f "$file" ]; then
            warn "Missing: $name"
            missing=$((missing + 1))
            continue
        fi

        local actual_hash
        if command -v sha256sum &>/dev/null; then
            actual_hash=$(sha256sum "$file" | awk '{print $1}')
        elif command -v shasum &>/dev/null; then
            actual_hash=$(shasum -a 256 "$file" | awk '{print $1}')
        else
            warn "No sha256 tool — skipping verification"
            return 0
        fi

        actual_hash=$(echo "$actual_hash" | tr '[:lower:]' '[:upper:]')
        expected_hash=$(echo "$expected_hash" | tr '[:lower:]' '[:upper:]')

        if [ "$actual_hash" = "$expected_hash" ]; then
            ok=$((ok + 1))
        else
            warn "Corrupted: $name (hash mismatch)"
            failed=$((failed + 1))
        fi
    done < "$sums_file"

    local total=$((ok + failed + missing))
    if [ "$failed" -gt 0 ] || [ "$missing" -gt 0 ]; then
        warn "Integrity: $ok/$total passed, $failed corrupted, $missing missing"
        return 1
    fi
    info "Integrity: $ok files verified"
    return 0
}

# ── CDN URL helper ────────────────────────────────────────────
# Converts raw.githubusercontent.com URL to jsDelivr CDN URL
cdn_url() {
    echo "$1" | sed "s|https://raw\.githubusercontent\.com/\([^/]*/[^/]*\)/main/|https://cdn.jsdelivr.net/gh/\1@main/|"
}

# ── Download helpers ─────────────────────────────────────────
# Download with resume support (uses wget -c, falls back to curl)
download_with_resume() {
    local url="$1" dest="$2" max_retries="${3:-3}"
    local attempt=1
    while [ $attempt -le $max_retries ]; do
        if wget -c -q --timeout=30 --tries=2 "$url" -O "$dest" 2>/dev/null; then
            [ -s "$dest" ] && return 0
        elif curl -fsSL -C - --connect-timeout 10 --max-time 60 "$url" -o "$dest" 2>/dev/null; then
            [ -s "$dest" ] && return 0
        fi
        rm -f "$dest" 2>/dev/null || true
        attempt=$((attempt + 1))
        [ $attempt -le $max_retries ] && sleep 2
    done
    return 1
}

# Fast download with aria2 (multi-connection) — falls back to curl
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
    download_with_resume "$url" "$dest"
}

# Parallel download batch — fires all downloads concurrently
# Tries jsDelivr CDN first, falls back to GitHub raw.
# Usage: parallel_download_batch URL_ARRAY DEST_ARRAY
# Both arguments are variable names of arrays (nameref).
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
