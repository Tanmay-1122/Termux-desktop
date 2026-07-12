#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
#   Termux Desktop Launcher
#   Usage:
#     startdesktop          -> Termux:X11 (auto, recommended)
#     startdesktop rdp      -> xRDP mode
#     startdesktop novnc    -> noVNC browser mode
#     startdesktop menu     -> show selection menu
#     startdesktop stop     -> kill desktop session
#   Repo : github.com/Tanmay-1122/Termux-desktop
# ============================================================

export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$PREFIX/bin:/system/bin:/system/xbin:$PATH"

# ── IP address helper ─────────────────────────────────────────
get_ip() {
    local iface="$1"
    local addr=""
    addr=$(ip -4 addr show "$iface" 2>/dev/null \
           | grep -oE 'inet [0-9.]+' | awk '{print $2}' | head -1)
    if [ -z "$addr" ] && command -v ifconfig &>/dev/null; then
        addr=$(ifconfig "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
    fi
    echo "$addr"
}

# ── Detect IPs ───────────────────────────────────────────────
WIFI_IP=$(get_ip wlan0)
USB_IP=""
USB_IFACE=""
for iface in rndis0 usb0 eth0; do
    IP=$(get_ip "$iface")
    if [ -n "$IP" ]; then USB_IP="$IP"; USB_IFACE="$iface"; break; fi
done
BEST_IP="${WIFI_IP:-$USB_IP}"

# ── Parse argument ─────────────────────────────────────────────
MODE="${1:-x11}"
case "$MODE" in
    x11|X11|"")   MODE="x11" ;;
    rdp|RDP)       MODE="rdp" ;;
    novnc|noVNC)   MODE="novnc" ;;
    menu)          MODE="menu" ;;
    stop|kill)     MODE="stop" ;;
    *)             echo "[!] Unknown mode '$MODE'. Using x11."; MODE="x11" ;;
esac

# ── Stop mode ─────────────────────────────────────────────────
if [ "$MODE" = "stop" ]; then
    echo "[*] Stopping desktop session..."
    pkill xrdp 2>/dev/null || true
    pkill xrdp-sesman 2>/dev/null || true
    pkill Xtigervnc 2>/dev/null || true
    pkill Xvnc 2>/dev/null || true
    pkill xfce4-session 2>/dev/null || true
    pkill websockify 2>/dev/null || true
    pkill -f "termux.x11" 2>/dev/null || true
    vncserver -kill :1 2>/dev/null || true
    pkill -f virgl_test_server 2>/dev/null || true
    rm -rf "$PREFIX/tmp/.X"* 2>/dev/null || true
    rm -rf "$PREFIX/tmp/.X11-unix/"* 2>/dev/null || true
    echo "[OK] Desktop stopped."
    exit 0
fi

# ── Menu mode ─────────────────────────────────────────────────
if [ "$MODE" = "menu" ]; then
    clear
    echo ""
    echo "=================================================="
    echo "  Termux Desktop Launcher"
    echo "=================================================="
    echo ""
    echo "  Network:"
    if [ -n "$USB_IP" ]; then
        printf "   USB  (%-6s) : %s\n" "$USB_IFACE" "$USB_IP"
    else
        echo "   USB            : Not detected"
    fi
    printf "   WiFi (wlan0)   : %s\n" "${WIFI_IP:-Not detected}"
    echo "--------------------------------------------------"
    echo "  Select display mode:"
    echo ""
    echo "   A) Termux:X11  — Recommended (fastest)"
    echo "   B) xRDP        — Windows Remote Desktop"
    echo "   C) noVNC       — Any browser"
    echo ""
    echo "  Quick tools:"
    echo "   D) Dashboard   — System health"
    echo "   T) Theme       — Change desktop theme"
    echo "   M) Manage Apps — Install/remove apps"
    echo "   S) Stop        — Kill current desktop"
    echo "=================================================="
    echo ""
    if [ -n "$BEST_IP" ]; then
        echo "   RDP address: $BEST_IP:3389"
        echo "   noVNC URL  : http://$BEST_IP:6080/vnc.html"
    fi
    echo ""
    read -rp "   Choice [A/B/C/D/T/M/S]: " CHOICE
    CHOICE=$(echo "$CHOICE" | tr '[:lower:]' '[:upper:]')
    case "$CHOICE" in
        D) exec bash "$HOME/dashboard.sh" ;;
        T) exec bash "$HOME/theme.sh" ;;
        M) exec bash "$HOME/manage-apps.sh" ;;
        A|"") MODE="x11" ;;
        B)    MODE="rdp" ;;
        C)    MODE="novnc" ;;
        S)    exec bash "$0" stop ;;
        *)    MODE="x11" ;;
    esac
fi

# ── Cleanup previous session ──────────────────────────────────
echo "[*] Cleaning previous session..."
pkill xrdp            2>/dev/null || true
pkill xrdp-sesman     2>/dev/null || true
pkill Xtigervnc       2>/dev/null || true
pkill Xvnc            2>/dev/null || true
pkill xfce4-session   2>/dev/null || true
pkill websockify      2>/dev/null || true
pkill -f "termux.x11" 2>/dev/null || true
vncserver -kill :1    2>/dev/null || true
pkill -f virgl_test_server 2>/dev/null || true
rm -rf "$PREFIX/tmp/.X*"          2>/dev/null || true
rm -rf "$PREFIX/tmp/.X11-unix/"*  2>/dev/null || true
sleep 1

# ── Start VirGL Server for Hardware Acceleration ───────────
if command -v virgl_test_server_android &>/dev/null; then
    echo "[*] Initializing GPU hardware acceleration..."
    virgl_test_server_android &
    sleep 1
    if pgrep -f virgl_test_server &>/dev/null; then
        export GALLIUM_DRIVER=virpipe
        export MESA_GL_VERSION_OVERRIDE=4.0
        echo "[OK] Hardware acceleration active (VirGL)"
    else
        echo "[!] Hardware acceleration failed to start. Using software rendering."
    fi
fi

# ════════════════════════════════════════════════════════════
# Shared helpers
# ════════════════════════════════════════════════════════════
setup_xsession() {
    export XDG_RUNTIME_DIR="$PREFIX/tmp/runtime-$UID"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    cat > ~/.xsession << 'EOL'
export XDG_RUNTIME_DIR=/data/data/com.termux/files/usr/tmp/runtime-0
mkdir -p $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR
dbus-launch --exit-with-session xfce4-session
EOL
    chmod +x ~/.xsession
    echo "startxfce4" > ~/.Xclients
    chmod +x ~/.Xclients
}

configure_xrdp() {
    local XRDP_INI="$PREFIX/etc/xrdp/xrdp.ini"
    [ ! -f "$XRDP_INI" ] && return 1
    sed -i 's/^autorun=.*/autorun=Direct-VNC/' "$XRDP_INI"
    grep -q '^autorun=' "$XRDP_INI" || \
        sed -i '/^\[Globals\]/a autorun=Direct-VNC' "$XRDP_INI"
    sed -i 's/^crypt_level=high/crypt_level=none/' "$XRDP_INI"
    grep -q '\[Direct-VNC\]' "$XRDP_INI" || cat >> "$XRDP_INI" << 'XEOF'

[Direct-VNC]
name=NoLogin
lib=libvnc.so
username=na
password=na
ip=127.0.0.1
port=5901
XEOF
}

start_vnc() {
    echo "[*] Starting VNC on :1 (port 5901)..."
    vncserver :1 -geometry 1366x768 -depth 24 \
        -SecurityTypes None -localhost no 2>/dev/null
    sleep 2
    if ! pgrep -f "Xvnc.*:1" >/dev/null && ! pgrep -f "Xtigervnc.*:1" >/dev/null; then
        echo "[!!] VNC failed to start. Check: ~/.vnc/"
        exit 1
    fi
    echo "[OK] VNC running on :1"
}

# ════════════════════════════════════════════════════════════
# MODE X11 — Termux:X11 (default)
# ════════════════════════════════════════════════════════════
start_x11() {
    echo ""
    echo "[*] Starting Termux:X11 mode..."

    termux-wake-lock 2>/dev/null || true

    pulseaudio --start \
        --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
        --exit-idle-time=-1 2>/dev/null || true

    export XDG_RUNTIME_DIR="${TMPDIR:-$PREFIX/tmp}"
    termux-x11 :0 >/dev/null 2>&1 &
    sleep 4

    echo "[*] Launching Termux:X11 app..."
    if command -v am &>/dev/null; then
        if am start --user 0 \
            -n com.termux.x11/com.termux.x11.MainActivity \
            >/dev/null 2>&1; then
            echo "[OK] Termux:X11 app launched"
        else
            echo "[!!] Could not launch app automatically"
            echo "     Open Termux:X11 app manually from your app drawer"
        fi
    else
        echo "[!] Please open the Termux:X11 app on your phone now."
    fi
    sleep 2

    export PULSE_SERVER=127.0.0.1
    export DISPLAY=:0

    echo ""
    echo "=================================================="
    echo "  Termux:X11 mode active"
    echo "  XFCE4 is launching — please wait"
    echo "  Press Ctrl+C to stop"
    echo "=================================================="
    echo ""

    env DISPLAY=:0 dbus-launch --exit-with-session xfce4-session \
        >/dev/null 2>&1 &
    XFCE_PID=$!
    wait $XFCE_PID
}

# ════════════════════════════════════════════════════════════
# MODE RDP — xRDP
# ════════════════════════════════════════════════════════════
start_rdp() {
    echo ""
    echo "[*] Starting xRDP mode..."
    if ! command -v xrdp &>/dev/null; then
        echo "[!] xRDP not installed. Installing..."
        if ! pkg install -y xrdp 2>/dev/null; then
            echo "[!!] Failed to install xrdp. Try: pkg install xrdp"
            exit 1
        fi
        echo "[OK] xrdp installed"
    fi
    termux-wake-lock 2>/dev/null || true
    setup_xsession
    configure_xrdp
    start_vnc

    echo "[*] Launching XFCE4..."
    export DISPLAY=:1
    dbus-launch --exit-with-session xfce4-session \
        > "$PREFIX/tmp/xfce4.log" 2>&1 &
    XFCE_PID=$!
    sleep 3

    echo "[*] Starting xRDP on port 3389..."
    xrdp-sesman > "$PREFIX/tmp/xrdp-sesman.log" 2>&1 &
    sleep 1
    xrdp > "$PREFIX/tmp/xrdp.log" 2>&1 &
    sleep 2

    if ! pgrep -x "xrdp" >/dev/null; then
        echo "[!!] xRDP failed. Log:"; cat "$PREFIX/tmp/xrdp.log"
        exit 1
    fi
    echo "[OK] xRDP running on port 3389"

    echo ""
    echo "=================================================="
    echo "  xRDP mode active"
    echo "  Connect using Windows Remote Desktop (mstsc)"
    echo ""
    [ -n "$WIFI_IP" ] && printf "  WiFi  -> %s\n" "$WIFI_IP:3389"
    [ -n "$USB_IP"  ] && printf "  USB   -> %s\n" "$USB_IP:3389"
    [ -z "$WIFI_IP" ] && [ -z "$USB_IP" ] && \
        echo "  No IP detected — check connection"
    echo ""
    echo "  Leave username/password blank"
    echo "  Press Ctrl+C to stop"
    echo "=================================================="
    echo ""
    wait $XFCE_PID
}

# ════════════════════════════════════════════════════════════
# MODE NOVNC — browser access
# ════════════════════════════════════════════════════════════
start_novnc() {
    echo ""
    echo "[*] Starting noVNC mode..."
    termux-wake-lock 2>/dev/null || true

    command -v websockify &>/dev/null || {
        echo "[*] Installing websockify..."
        pkg install -y websockify || { echo "[!!] websockify install failed"; exit 1; }
    }

    NOVNC_DIR="$HOME/noVNC"
    if [ ! -d "$NOVNC_DIR" ]; then
        echo "[*] Downloading noVNC web client..."
        local novnc_url="https://github.com/novnc/noVNC/archive/refs/heads/master.zip"
        local novnc_zip="$TMPDIR/novnc.zip"
        if command -v aria2c &>/dev/null; then
            aria2c -x 4 -s 4 --connect-timeout=10 --timeout=30 \
                --max-tries=3 --retry-wait=2 \
                --allow-overwrite=true --auto-file-renaming=false \
                "$novnc_url" -d "$TMPDIR" -o "novnc.zip" \
                -q 2>/dev/null || true
        fi
        if [ ! -f "$novnc_zip" ] || [ ! -s "$novnc_zip" ]; then
            wget -c -q "$novnc_url" -O "$novnc_zip" || true
        fi
        [ -f "$novnc_zip" ] && unzip -q "$novnc_zip" -d "$HOME" && \
        mv "$HOME/noVNC-master" "$NOVNC_DIR" && \
        rm -f "$novnc_zip" || true
    fi

    setup_xsession
    start_vnc

    echo "[*] Launching XFCE4..."
    export DISPLAY=:1
    dbus-launch --exit-with-session xfce4-session \
        > "$PREFIX/tmp/xfce4.log" 2>&1 &
    XFCE_PID=$!
    sleep 3

    echo "[*] Starting websockify on port 6080..."
    if [ -d "$NOVNC_DIR" ]; then
        websockify --web="$NOVNC_DIR" 6080 localhost:5901 \
             > "$PREFIX/tmp/websockify.log" 2>&1 &
    else
        websockify 6080 localhost:5901 \
             > "$PREFIX/tmp/websockify.log" 2>&1 &
    fi
    sleep 2

    echo ""
    echo "=================================================="
    echo "  noVNC mode active"
    echo "  Open in any browser:"
    echo ""
    [ -n "$WIFI_IP" ] && echo "  http://$WIFI_IP:6080/vnc.html"
    [ -n "$USB_IP"  ] && echo "  http://$USB_IP:6080/vnc.html"
    [ -z "$BEST_IP" ] && echo "  (No IP detected — check WiFi)"
    echo ""
    echo "  Press Ctrl+C to stop"
    echo "=================================================="
    echo ""
    wait $XFCE_PID
}

# ════════════════════════════════════════════════════════════
# Launch
# ════════════════════════════════════════════════════════════
case "$MODE" in
    x11)   start_x11   ;;
    rdp)   start_rdp   ;;
    novnc) start_novnc ;;
esac
