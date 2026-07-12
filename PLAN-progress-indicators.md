# Progress Indicators Plan — Termux Desktop

## Problem Analysis

On **low-end Android devices** (2-3GB RAM, slow CPUs), the installer has long **silent periods** where the terminal appears frozen. The user cannot distinguish between "script is working" and "app crashed".

### Current Silent Periods

| Phase | Duration | Current Output | Problem |
|---|---|---|---|
| `pkg update` | 10-120s | All output → `$LOG_FILE` | **Terminal frozen** |
| `install_pkgs "core desktop"` | 30-300s | All output → `$LOG_FILE` | **Terminal frozen** |
| `install_pkgs "GPU packages"` | 20-120s | All output → `$LOG_FILE` | **Terminal frozen** |
| `install_pkgs "extra apps"` | 30-300s | All output → `$LOG_FILE` | **Terminal frozen** |
| `parallel_download_batch` | 10-60s | Nothing until all done | **Silent + parallel = confusing** |
| `sleep 2` / `sleep 3` | 2-3s | Nothing | Brief but adds up |
| Mirror testing (`test_mirrors_parallel`) | 3-10s | `Finding fastest mirror...` then silence | Partial — better than nothing |

### Why it's worse on low-end devices

- Slower CPU → `dpkg --configure -a` takes 2-3x longer
- Slower I/O → package unpacking is 3-5x slower
- Less RAM → Android may swap, stalling everything
- Older WiFi/modem → downloads are slower
- Result: a 2-minute install on a flagship takes **8-12 minutes** on a budget device

---

## Solution Architecture

**Single approach**: A `spinner_run()` function that runs any command in the background, shows a live progress display, and optionally watches a log file for the last line of output.

### The Core: `spinner_run()`

```bash
# ── Spinner with live log tail ──────────────────────────────
# Runs a command in the background while displaying:
#   [spin] Label... (package-name) [NNs]
# The log file is tailed to show the last line of real output.
spinner_run() {
    local label="$1"        # Display label (e.g., "Installing core desktop")
    local log_file="$2"     # Log file to watch for progress
    shift 2
    local cmd=("$@")        # Command to run (e.g., pkg install -y ...)

    # Run command in background, redirect to log
    "${cmd[@]}" > "$log_file" 2>&1 &
    local pid=$!

    # Spinner characters
    local spin='-\|/'
    local i=0
    local start_time=$SECONDS

    # Clear any previous line
    printf "\033[2K\r"

    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$((SECONDS - start_time))
        # Get last meaningful line from log (skip progress lines)
        local last_line
        last_line=$(tail -5 "$log_file" 2>/dev/null | grep -v '^$' | \
            grep -v '^Progress:' | grep -v '^Get:' | grep -v '^Fetched' | \
            grep -v '^Reading' | grep -v '^Building' | tail -1)
        last_line="${last_line:0:50}"  # truncate to 50 chars

        if [ -n "$last_line" ]; then
            printf "\r  ${CYAN}%c${NC} ${BOLD}%s${NC} ... %s ${DIM}[%ds]${NC}" \
                "${spin:$i:1}" "$label" "$last_line" "$elapsed"
        else
            printf "\r  ${CYAN}%c${NC} ${BOLD}%s${NC} ... ${DIM}[%ds]${NC}" \
                "${spin:$i:1}" "$label" "$elapsed"
        fi

        i=$(( (i+1) % 4 ))
        sleep 0.5
    done

    wait "$pid"
    local rc=$?

    # Clear spinner line
    printf "\r\033[K"

    return $rc
}
```

### Usage transformation

**Before** (dead silent):
```bash
pkg install -y xfce4 pulseaudio >> "$LOG_FILE" 2>&1
```

**After** (live spinner + last installed package):
```bash
spinner_run "Installing core desktop" "$LOG_FILE" \
    pkg install -y xfce4 pulseaudio
```

---

## Implementation Plan — 5 Changes

### Change 1: Add `spinner_run()` to `lib.sh`

The shared library gets a new function used by all scripts.

```bash
# ── Spinner with live progress ──────────────────────────────
# Runs command in background, shows animated spinner + elapsed
# time + last significant line from log file.
# Usage: spinner_run "Label" /path/to/log cmd arg1 arg2 ...
spinner_run() {
    local label="$1"
    local log_file="$2"
    shift 2

    # Ensure we have a writable log
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
    : > "$log_file"

    # Run in background
    "$@" > "$log_file" 2>&1 &
    local pid=$!

    local spin='-\|/'
    local i=0
    local start_time=$SECONDS

    # Hide cursor
    printf '\e[?25l'

    while kill -0 "$pid" 2>/dev/null; do
        local elapsed=$((SECONDS - start_time))
        local last_line
        last_line=$(tail -3 "$log_file" 2>/dev/null | \
            grep -vE '^(Progress:|Get:|Fetched |Reading |Building |$)' | \
            tail -1)
        last_line="${last_line:0:55}"

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

    # Restore cursor
    printf '\e[?25h'
    printf '\r\033[K'

    return $rc
}
```

**Edge cases handled:**
- Log file doesn't exist yet → `: >` creates it
- Command finishes instantly → `kill -0` returns false immediately, no spinner shown
- Very long log lines → truncated to 55 chars
- ANSI escape codes or special chars in dpkg output → `grep -vE` filters noise
- User interruption → cursor restored via cleanup trap

### Change 2: Rewrite `install_pkgs()` in `install.sh`

Replace the silent `pkg install -y` with `spinner_run`.

**Before:**
```bash
install_pkgs() {
    local label="$1"; shift
    local pkgs="$*"
    local attempt=1
    while [ $attempt -le $MAX_RETRIES ]; do
        log "Installing $label (attempt $attempt): $pkgs"
        if pkg install -y $pkgs >> "$LOG_FILE" 2>&1; then
            ok "$label installed"
            return 0
        fi
        ...
    done
}
```

**After:**
```bash
install_pkgs() {
    local label="$1"; shift
    local pkgs="$*"
    local attempt=1
    while [ $attempt -le $MAX_RETRIES ]; do
        log "Installing $label (attempt $attempt): $pkgs"
        if spinner_run "$label" "$LOG_FILE" pkg install -y $pkgs; then
            ok "$label installed"
            return 0
        fi
        ...
    done
}
```

### Change 3: Add spinner to `parallel_download_batch()`

Show live completion count during parallel downloads.

**Add inside the wait loop:**
```bash
# Before wait loop, start a background status updater
local dl_start=$SECONDS
(
    while kill -0 "${pids[0]}" 2>/dev/null || [ ${#pids[@]} -gt 1 ]; do
        local complete=0
        for f in "${_dests[@]}"; do
            [ -s "$f" ] && complete=$((complete + 1))
        done
        local elapsed=$((SECONDS - dl_start))
        printf "\r  \033[0;36m↓\033[0m Downloaded %d/%d files \033[2m[%ds]\033[0m" \
            "$complete" "$n" "$elapsed"
        sleep 1
    done
) &
local status_pid=$!
```

### Change 4: Add spinner to `pkg update` calls

All `pkg update -y` calls currently hide output. Wrap with spinner.

### Change 5: Animated "still alive" dots during sleeps

Replace `sleep 2` and `sleep 3` with animated countdown:

```bash
# Instead of: sleep 2
# Use:
countdown_sleep() {
    local secs="$1" msg="${2:-waiting}"
    while [ $secs -gt 0 ]; do
        printf "\r  \033[0;2m%s... %ds\033[0m" "$msg" "$secs"
        sleep 1
        secs=$((secs - 1))
    done
    printf "\r\033[K"
}
```

---

## Where Each Change Goes

| File | Function/Area | Change |
|---|---|---|
| `lib.sh` | New function | Add `spinner_run()`, `countdown_sleep()` |
| `install.sh` | `install_pkgs()` (line 146) | Replace `pkg install` → `spinner_run` |
| `install.sh` | `pkg update -y` (line 357) | Wrap in `spinner_run` |
| `install.sh` | `parallel_download_batch()` | Add live status counter |
| `install.sh` | `sleep 2` / `sleep 3` | Replace with `countdown_sleep` |
| `install.sh` | GPU install (line 375) | Wrap in `spinner_run` |
| `setup.sh` | `install_group()` → `timed_pkg_install()` | Wrap in `spinner_run` |
| `setup.sh` | `do_pkg_update()` | Wrap in `spinner_run` |

---

## Visual Output Examples

### During package install:
```
  ════════════════════════════════════════════════════════════
  [3/6] Installing core desktop

  \ Installing core desktop... Unpacking xfce4-panel (4.18.6) [45s]
```

### During parallel download:
```
  → Downloading desktop files (10 in parallel)...
  ↓ Downloaded 7/10 files [12s]
```

### During sleep/retry wait:
```
  ⚠ Core desktop attempt 1 failed, retrying...
  waiting... 2s
```

### After completion:
```
  ✓ Core desktop installed
```

---

## Implementation Order

1. **Add `spinner_run()` + `countdown_sleep()` to `lib.sh`** — foundation
2. **Wrap `install_pkgs()` in `install.sh`** — biggest win (longest silent period)
3. **Wrap `pkg update` calls** — quick wins
4. **Add download counter to `parallel_download_batch()`** — medium effort
5. **Wrap GPU install in `setup.sh`** — consistency
6. **Replace `sleep N` with `countdown_sleep`** — polish

---

## Edge Cases & Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Log file grows large during long install | Medium | Only read last 3 lines |
| ANSI escape codes in dpkg output corrupt terminal | Low | Filter with `grep -vE`; cursor restore on exit |
| `kill -0` fails on Android with stale PID | Low | `wait $pid` after loop catches exit code |
| Spinner slows down very old devices | Low | Uses 0.5s interval — negligible CPU |
| User presses Ctrl+C during spinner | Medium | `_cleanup` trap already handles this; add `printf '\e[?25h'` to cleanup |
