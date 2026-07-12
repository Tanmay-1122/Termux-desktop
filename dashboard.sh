#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
#   Termux Desktop — System Health Dashboard
#   Shows: CPU, RAM, Storage, Battery, Network, Uptime
#   Run anytime: bash ~/dashboard.sh
#   Auto-refresh every 3 seconds until Ctrl+C
#   Repo : github.com/Tanmay-1122/Termux-desktop
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

REFRESH=3  # seconds between refreshes

# ── Bar renderer ─────────────────────────────────────────────
# Usage: render_bar VALUE MAX WIDTH COLOR_IF_OK
render_bar() {
    local value=$1 max=$2 width=$3
    local percent=$(( value * 100 / max ))
    local filled=$(( value * width / max ))
    [ $filled -gt $width ] && filled=$width

    local color="$GREEN"
    [ $percent -ge 60 ] && color="$YELLOW"
    [ $percent -ge 85 ] && color="$RED"

    local bar=""
    for ((i=0; i<width; i++)); do
        [ $i -lt $filled ] && bar="${bar}█" || bar="${bar}░"
    done

    printf "${color}%s${NC} ${BOLD}%3d%%${NC}" "$bar" "$percent"
}

# ── CPU usage (1-second sample) ───────────────────────────────
get_cpu_usage() {
    # Read /proc/stat twice with a 0.5s gap
    local line1 line2
    line1=$(grep '^cpu ' /proc/stat)
    sleep 0.5
    line2=$(grep '^cpu ' /proc/stat)

    local idle1 total1 idle2 total2
    read -r _ u1 n1 s1 i1 w1 _ <<< "$line1"
    read -r _ u2 n2 s2 i2 w2 _ <<< "$line2"

    total1=$(( u1 + n1 + s1 + i1 + w1 ))
    total2=$(( u2 + n2 + s2 + i2 + w2 ))

    local dtotal=$(( total2 - total1 ))
    local didle=$(( i2 - i1 ))

    [ $dtotal -eq 0 ] && echo 0 && return
    echo $(( (dtotal - didle) * 100 / dtotal ))
}

# ── CPU temp ─────────────────────────────────────────────────
get_cpu_temp() {
    local temp=""
    # Try thermal zone 0 first
    for zone in /sys/class/thermal/thermal_zone*/temp; do
        if [ -f "$zone" ]; then
            local raw
            raw=$(cat "$zone" 2>/dev/null)
            if [ -n "$raw" ] && [ "$raw" -gt 1000 ] 2>/dev/null; then
                temp=$(( raw / 1000 ))
                echo "${temp}°C"
                return
            fi
        fi
    done
    echo "N/A"
}

# ── RAM usage ─────────────────────────────────────────────────
get_ram() {
    local total_kb avail_kb used_kb
    total_kb=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    avail_kb=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}')
    used_kb=$(( total_kb - avail_kb ))

    local total_mb=$(( total_kb / 1024 ))
    local used_mb=$(( used_kb / 1024 ))
    local avail_mb=$(( avail_kb / 1024 ))

    echo "$used_mb $total_mb $avail_mb"
}

# ── Storage ───────────────────────────────────────────────────
get_storage() {
    local info
    info=$(df "$HOME" 2>/dev/null | tail -1)
    local size_kb=$(echo "$info" | awk '{print $2}')
    local used_kb=$(echo "$info" | awk '{print $3}')
    local avail_kb=$(echo "$info" | awk '{print $4}')

    local size_gb=$(( size_kb / 1024 / 1024 ))
    local used_gb=$(( used_kb / 1024 / 1024 ))
    local avail_gb=$(( avail_kb / 1024 / 1024 ))

    [ $size_gb -eq 0 ] && {
        echo "N/A 1 1"
        return
    }

    echo "$used_gb $size_gb $avail_gb"
}

# ── Battery ───────────────────────────────────────────────────
get_battery() {
    local battery_json
    battery_json=$(termux-battery-status 2>/dev/null)

    if [ -n "$battery_json" ]; then
        local level status temp
        level=$(echo "$battery_json" | grep '"percentage"' | grep -o '[0-9]*')
        status=$(echo "$battery_json" | grep '"status"' | grep -o '"[A-Z_]*"' | tr -d '"')
        temp=$(echo "$battery_json" | grep '"temperature"' | grep -o '[0-9.]*' | head -1)

        [ -z "$level" ] && level="?"
        [ -z "$status" ] && status="UNKNOWN"
        [ -z "$temp" ] && temp="?"

        echo "$level $status $temp"
    else
        # Fallback: try /sys directly
        local bat_path=""
        for p in /sys/class/power_supply/battery /sys/class/power_supply/Battery; do
            [ -d "$p" ] && bat_path="$p" && break
        done

        if [ -n "$bat_path" ]; then
            local level status
            level=$(cat "$bat_path/capacity" 2>/dev/null || echo "?")
            status=$(cat "$bat_path/status" 2>/dev/null || echo "UNKNOWN")
            echo "$level $status N/A"
        else
            echo "? UNKNOWN N/A"
        fi
    fi
}

# ── Network ───────────────────────────────────────────────────
get_ip_addr() {
    local iface="$1"
    local addr=""
    # Prefer 'ip' (always present), fall back to ifconfig
    addr=$(ip -4 addr show "$iface" 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}' | head -1)
    if [ -z "$addr" ] && command -v ifconfig &>/dev/null; then
        addr=$(ifconfig "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
    fi
    echo "$addr"
}

get_network() {
    local wifi_ip usb_ip
    wifi_ip=$(get_ip_addr wlan0)
    usb_ip=""
    for iface in rndis0 usb0 eth0; do
        local ip
        ip=$(get_ip_addr "$iface")
        [ -n "$ip" ] && usb_ip="$ip ($iface)" && break
    done

    [ -z "$wifi_ip" ] && wifi_ip="Not connected"
    [ -z "$usb_ip"  ] && usb_ip="Not connected"

    echo "$wifi_ip|$usb_ip"
}

# ── Uptime ────────────────────────────────────────────────────
get_uptime() {
    local seconds
    seconds=$(cut -d'.' -f1 /proc/uptime 2>/dev/null || echo 0)
    local hours=$(( seconds / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$(( seconds % 60 ))
    printf "%dh %02dm %02ds" "$hours" "$minutes" "$secs"
}

# ── Process count ─────────────────────────────────────────────
get_processes() {
    ps aux 2>/dev/null | wc -l
}

# ── Top CPU processes ─────────────────────────────────────────
get_top_processes() {
    ps aux --sort=-%cpu 2>/dev/null | awk 'NR>1 && NR<=6 {printf "   %-22s %5s%%  %5s MB\n", substr($11,1,22), $3, int($6/1024)}' 2>/dev/null \
    || ps -eo pid,pcpu,pmem,comm --sort=-pcpu 2>/dev/null | awk 'NR>1 && NR<=6 {printf "   %-22s %5s%%\n", $4, $2}'
}

# ════════════════════════════════════════════════════════════
# Main render loop
# ════════════════════════════════════════════════════════════
trap 'clear; echo "  Dashboard closed."; exit 0' INT TERM

while true; do
    # Collect all data
    CPU_USAGE=$(get_cpu_usage)
    CPU_TEMP=$(get_cpu_temp)
    read -r RAM_USED RAM_TOTAL RAM_AVAIL <<< "$(get_ram)"
    read -r STOR_USED STOR_TOTAL STOR_AVAIL <<< "$(get_storage)"
    read -r BAT_LEVEL BAT_STATUS BAT_TEMP <<< "$(get_battery)"
    NET_INFO=$(get_network)
    WIFI_IP=$(echo "$NET_INFO" | cut -d'|' -f1)
    USB_IP=$(echo "$NET_INFO" | cut -d'|' -f2)
    UPTIME=$(get_uptime)
    PROC_COUNT=$(get_processes)
    TOP_PROCS=$(get_top_processes)

    # Timestamp
    NOW=$(date '+%H:%M:%S  %a %d %b %Y')

    # Render to temp file first for flicker-free display
    RENDER=$(cat << RENDER_EOF

╔══════════════════════════════════════════════════════════════╗
║   📊  Termux Desktop — System Dashboard          $NOW   ║
╠══════════════════════════════════════════════════════════════╣
RENDER_EOF
    )

    clear
    echo ""
    printf "${CYAN}${BOLD}"
    printf "╔══════════════════════════════════════════════════════════════════╗\n"
    PROJECT_VER=$(cat "$HOME/.termux-desktop-version" 2>/dev/null || echo "1.4")
    printf "║  📊  Termux Desktop Dashboard                  %-18s║\n" "$NOW"
    printf "╠══════════════════════════════════════════════════════════════════╣\n"
    printf "${NC}"

    # ── CPU ────────────────────────────────────────────────
    printf "${BOLD}║  CPU${NC}\n"
    [ "$CPU_USAGE" -gt 100 ] && CPU_USAGE=100
    printf "║   Usage  : "
    render_bar "$CPU_USAGE" 100 28
    printf "\n"
    printf "║   Temp   : ${BOLD}%s${NC}\n" "$CPU_TEMP"
    printf "${DIM}║─────────────────────────────────────────────────────────────────${NC}\n"

    # ── RAM ────────────────────────────────────────────────
    printf "${BOLD}║  RAM${NC}\n"
    [ "$RAM_TOTAL" -eq 0 ] && RAM_TOTAL=1
    printf "║   Usage  : "
    render_bar "$RAM_USED" "$RAM_TOTAL" 28
    printf "\n"
    printf "║   Used   : ${BOLD}%s MB${NC} / %s MB  (free: %s MB)\n" "$RAM_USED" "$RAM_TOTAL" "$RAM_AVAIL"
    printf "${DIM}║─────────────────────────────────────────────────────────────────${NC}\n"

    # ── Storage ────────────────────────────────────────────
    printf "${BOLD}║  Storage (/data/data/com.termux)${NC}\n"
    [ "$STOR_TOTAL" -eq 0 ] && STOR_TOTAL=1
    printf "║   Usage  : "
    render_bar "$STOR_USED" "$STOR_TOTAL" 28
    printf "\n"
    printf "║   Used   : ${BOLD}%s GB${NC} / %s GB  (free: %s GB)\n" "$STOR_USED" "$STOR_TOTAL" "$STOR_AVAIL"
    printf "${DIM}║─────────────────────────────────────────────────────────────────${NC}\n"

    # ── Battery ────────────────────────────────────────────
    printf "${BOLD}║  Battery${NC}\n"
    BAT_ICON="[BAT]"
    BAT_COLOR="$GREEN"
    case "$BAT_STATUS" in
        CHARGING|Full) BAT_ICON="[CHG]"; BAT_COLOR="$CYAN" ;;
        DISCHARGING)
            [ "${BAT_LEVEL:-0}" -lt 20 ] && BAT_COLOR="$RED" && BAT_ICON="[LOW]"
            ;;
    esac

    BAT_DISP=${BAT_LEVEL:-0}
    [ "$BAT_DISP" -gt 100 ] 2>/dev/null && BAT_DISP=100
    [ -z "$BAT_DISP" ] || [ "$BAT_DISP" = "?" ] && BAT_DISP=50

    printf "║   Level  : ${BAT_COLOR}${BOLD}%s%%%s${NC}  Status: %s  Temp: %s°C\n" \
        "${BAT_LEVEL}" "$BAT_ICON" "$BAT_STATUS" "$BAT_TEMP"
    printf "${DIM}║─────────────────────────────────────────────────────────────────${NC}\n"

    # ── Network ────────────────────────────────────────────
    printf "${BOLD}║  Network${NC}\n"
    printf "║   WiFi   : ${CYAN}%s${NC}\n" "$WIFI_IP"
    printf "║   USB    : ${CYAN}%s${NC}\n" "$USB_IP"

    if [ "$WIFI_IP" != "Not connected" ] || [ "$USB_IP" != "Not connected" ]; then
        BEST_IP="${WIFI_IP}"
        [ "$WIFI_IP" = "Not connected" ] && BEST_IP=$(echo "$USB_IP" | awk '{print $1}')
        printf "║   RDP    : ${GREEN}${BOLD}%s:3389${NC}  (if Mode B is running)\n" "$BEST_IP"
        printf "║   noVNC  : ${GREEN}${BOLD}http://%s:6080/vnc.html${NC}\n" "$BEST_IP"
    fi
    printf "${DIM}║─────────────────────────────────────────────────────────────────${NC}\n"

    # ── System Info ────────────────────────────────────────
    printf "${BOLD}║  System${NC}\n"
    printf "║   Uptime : ${BOLD}%s${NC}   Processes: ${BOLD}%s${NC}\n" "$UPTIME" "$PROC_COUNT"
    printf "${DIM}║─────────────────────────────────────────────────────────────────${NC}\n"

    # ── Top Processes ──────────────────────────────────────
    printf "${BOLD}║  Top processes (by CPU)${NC}\n"
    printf "${DIM}%s${NC}\n" "$TOP_PROCS"
    printf "${DIM}║─────────────────────────────────────────────────────────────────${NC}\n"

    # ── Quick Actions ──────────────────────────────────────
    printf "${BOLD}║  Quick launch${NC}\n"
    printf "║   [S] start-desktop   [M] manage-apps   [T] theme   [Q] quit\n"
    printf "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${NC}\n"
    printf "\n  ${DIM}Auto-refresh in ${REFRESH}s — press Q to quit, S/M/T for actions${NC}\n"

    # Non-blocking read for user input
    read -rsn1 -t "$REFRESH" INPUT 2>/dev/null
    INPUT=$(echo "$INPUT" | tr '[:lower:]' '[:upper:]')

    case "$INPUT" in
        Q) clear; echo "  Dashboard closed."; exit 0 ;;
        S) clear; exec bash "$HOME/start-desktop.sh" ;;
        M) clear; exec bash "$HOME/manage-apps.sh" ;;
        T) clear; exec bash "$HOME/theme.sh" ;;
    esac
done
