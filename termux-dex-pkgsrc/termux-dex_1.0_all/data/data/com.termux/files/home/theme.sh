#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
#   Termux Desktop — Theme Switcher v2.0
#   8 themes: Nord, Catppuccin Mocha/Latte, Solarized Dark,
#   Tokyo Night Storm/Light, Gruvbox Dark, Rose Pine
#   Usage: bash ~/theme.sh           <- interactive menu
#          bash ~/theme.sh --auto nord <- apply silently
#   Repo : github.com/Tanmay-1122/Termux-desktop
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!!]${NC} $1"; }
fail() { echo -e "  ${RED}[XX]${NC} $1"; }
info() { echo -e "  ${DIM}->${NC} $1"; }

AUTO_THEME=""
if [ "$1" = "--auto" ] && [ -n "$2" ]; then
    AUTO_THEME="$2"
fi

# Force Termux paths — may be overridden by parent environment (e.g. Windows host via ADB)
if [ -d "/data/data/com.termux" ]; then
    export PREFIX="/data/data/com.termux/files/usr"
    export HOME="/data/data/com.termux/files/home"
    export TMPDIR="$PREFIX/tmp"
fi

# ════════════════════════════════════════════════════════════
# Shared helpers
# ════════════════════════════════════════════════════════════

# Set up DISPLAY and DBUS for xfconf-query if xfce4-session is running
_setup_xfconf_env() {
    export DISPLAY="${DISPLAY:-:0}"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$PREFIX/tmp}"

    if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
        local pid env_value
        for pid in $(pgrep -f 'xfce4-session|xfsettingsd|xfce4-panel|xfdesktop' 2>/dev/null); do
            [ -r "/proc/$pid/environ" ] || continue
            env_value=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -n 1)
            if [ -n "$env_value" ]; then
                export DBUS_SESSION_BUS_ADDRESS="$env_value"
                break
            fi
            env_value=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^DISPLAY=//p' | head -n 1)
            [ -n "$env_value" ] && export DISPLAY="$env_value"
        done
    fi

    [ -n "$DBUS_SESSION_BUS_ADDRESS" ] && return

    local candidate
    for candidate in \
        "$XDG_RUNTIME_DIR/bus" \
        "$PREFIX/tmp/runtime-0/bus" \
        "$PREFIX/tmp/runtime-$UID/bus" \
        "$PREFIX/tmp"/dbus-*; do
        if [ -S "$candidate" ]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=$candidate"
            return
        fi
    done
}

_xfconf() {
    _setup_xfconf_env
    xfconf-query "$@" 2>/dev/null
}

_xfconf_set() {
    local channel="$1" property="$2" type="$3" value="$4"
    _xfconf -c "$channel" -p "$property" -s "$value" && return 0
    _xfconf -c "$channel" -p "$property" -n -t "$type" -s "$value"
}

_hex_to_rgba_parts() {
    local hex="${1//#/}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN { printf "%.6f %.6f %.6f 1.000000", r/255, g/255, b/255 }'
}

_restart_if_running() {
    local process="$1" command="$2" label="$3"
    if pgrep -f "$process" >/dev/null 2>&1; then
        eval "$command" >/dev/null 2>&1 || true
        ok "$label restarted"
    fi
}

_icon_theme_available() {
    local name="$1"
    [ -d "$HOME/.icons/$name" ] || [ -d "$HOME/.local/share/icons/$name" ] || [ -d "$PREFIX/share/icons/$name" ]
}

_choose_icon_theme() {
    local gtk_theme="$1"
    if echo "$gtk_theme" | grep -qi 'dark'; then
        for icon in Papirus-Dark Papirus Adwaita; do
            _icon_theme_available "$icon" && { echo "$icon"; return; }
        done
    else
        for icon in Papirus-Light Papirus Adwaita; do
            _icon_theme_available "$icon" && { echo "$icon"; return; }
        done
    fi
    echo "Adwaita"
}

_write_xsettings_xml() {
    local theme="$1" icon_theme="${2:-Adwaita}"
    local xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
    mkdir -p "$(dirname "$xml")" 2>/dev/null
    cat > "$xml" << XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="${theme}"/>
    <property name="IconThemeName" type="string" value="${icon_theme}"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Monospace 11"/>
  </property>
  <property name="Xfce" type="empty">
    <property name="SyncThemes" type="bool" value="true"/>
  </property>
</channel>
XMLEOF
}

_write_xfwm_xml() {
    local theme="${1:-Default}"
    local xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
    mkdir -p "$(dirname "$xml")" 2>/dev/null
    cat > "$xml" << XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="${theme}"/>
  </property>
</channel>
XMLEOF
}

_set_gtk_theme() {
    local theme="$1"
    local wm_theme="Default"
    local icon_theme
    icon_theme="$(_choose_icon_theme "$theme")"

    if _xfconf_set xsettings /Net/ThemeName string "$theme"; then
        _xfconf_set xsettings /Net/IconThemeName string "$icon_theme" >/dev/null 2>&1 || true
        _xfconf_set xsettings /Xfce/SyncThemes bool true >/dev/null 2>&1 || true
        _xfconf_set xfwm4 /general/theme string "$wm_theme" >/dev/null 2>&1 || true
        ok "GTK theme set via xfconf: $theme"
        return
    fi

    _write_xsettings_xml "$theme" "$icon_theme"
    _write_xfwm_xml "$wm_theme"
    ok "GTK theme set: $theme"
}

_set_panel_color() {
    local hex="$1"
    local rgba
    rgba=($(_hex_to_rgba_parts "$hex"))

    _xfconf_set xfce4-panel /panels/dark-mode bool true >/dev/null 2>&1 || true

    local panel
    for panel in panel-1 panel-2; do
        _xfconf_set xfce4-panel "/panels/${panel}/background-style" uint 1 >/dev/null 2>&1 || true
        _xfconf -c xfce4-panel -p "/panels/${panel}/background-rgba" -r >/dev/null 2>&1 || true
        _xfconf -c xfce4-panel -p "/panels/${panel}/background-rgba" -n \
            -t double -t double -t double -t double \
            -s "${rgba[0]}" -s "${rgba[1]}" -s "${rgba[2]}" -s "${rgba[3]}" >/dev/null 2>&1 || true
    done
}

_set_desktop_color() {
    local hex="$1"
    local hex_clean="${hex//#/}"
    local xml_dir="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    local xml="$xml_dir/xfce4-desktop.xml"
    local wallpaper_path="$HOME/.config/xfce4/wallpaper-${hex_clean}.png"

    mkdir -p "$xml_dir" 2>/dev/null
    mkdir -p "$HOME/.config/xfce4" 2>/dev/null

    cat > "$xml" << XMLEOF
<?xml version="1.1" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="last-settings-migration-version" type="uint" value="1"/>
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value="${wallpaper_path}"/>
          <property name="rgba1" type="string" value="${hex}ff"/>
        </property>
      </property>
      <property name="monitorVNC-0" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value="${wallpaper_path}"/>
          <property name="rgba1" type="string" value="${hex}ff"/>
        </property>
      </property>
      <property name="monitorbuiltin" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value="${wallpaper_path}"/>
          <property name="rgba1" type="string" value="${hex}ff"/>
        </property>
      </property>
      <property name="monitorDexDisplay" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value="${wallpaper_path}"/>
          <property name="rgba1" type="string" value="${hex}ff"/>
        </property>
      </property>
    </property>
  </property>
</channel>
XMLEOF

    local monitor base
    for monitor in monitor0 monitorVNC-0 monitorbuiltin monitorDexDisplay; do
        base="/backdrop/screen0/${monitor}/workspace0"
        _xfconf_set xfce4-desktop "${base}/color-style" int 0 >/dev/null 2>&1 || true
        _xfconf_set xfce4-desktop "${base}/image-style" int 0 >/dev/null 2>&1 || true
        _xfconf_set xfce4-desktop "${base}/last-image" string "$wallpaper_path" >/dev/null 2>&1 || true
        _xfconf_set xfce4-desktop "${base}/rgba1" string "${hex}ff" >/dev/null 2>&1 || true
    done
}

_set_terminal() {
    local fg="$1" bg="$2" cursor="$3" palette="$4" font="${5:-Monospace 11}"
    TERM_CONF="$HOME/.config/xfce4/terminal/terminalrc"
    mkdir -p "$(dirname "$TERM_CONF")" 2>/dev/null
    cat > "$TERM_CONF" << TERM_EOF
[Configuration]
ColorForeground=${fg}
ColorBackground=${bg}
ColorCursor=${cursor}
ColorPalette=${palette}
FontName=${font}
MiscAlwaysShowTabs=FALSE
MiscBell=FALSE
MiscBellUrgent=FALSE
MiscBordersDefault=TRUE
MiscCursorBlinks=FALSE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_BLOCK
MiscDefaultGeometry=100x30
MiscInheritGeometry=FALSE
MiscMenubarDefault=TRUE
MiscMouseAutohide=FALSE
MiscMouseWheelZoom=TRUE
MiscToolbarDefault=FALSE
MiscConfirmClose=TRUE
MiscCycleTabs=TRUE
MiscTabCloseButtons=TRUE
MiscTabCloseMiddleClick=TRUE
MiscTabPosition=GTK_POS_TOP
MiscHighlightUrls=TRUE
MiscMiddleClickOpensUri=FALSE
MiscCopyOnSelect=FALSE
MiscShowRelaunchDialog=TRUE
MiscRewrapOnResize=TRUE
MiscUseShiftArrowsToScroll=FALSE
MiscSlimTabs=FALSE
MiscNewTabAgreement=FALSE
MiscSearchDialogOpacity=100
MiscShowUnsafePasteDialog=TRUE
TERM_EOF
    ok "Terminal palette applied"
}

_set_gtk_css() {
    local bg="$1" panel="$2" fg="$3" accent="$4" name="$5" mode="$6"
    local css3="$HOME/.config/gtk-3.0/gtk.css"
    local css4="$HOME/.config/gtk-4.0/gtk.css"
    local muted border shadow

    mkdir -p "$(dirname "$css3")" "$(dirname "$css4")" 2>/dev/null
    if [ "$mode" = "light" ]; then
        muted="$panel"
        border="rgba(20, 24, 35, 0.18)"
        shadow="rgba(20, 24, 35, 0.16)"
    else
        muted="$panel"
        border="rgba(255, 255, 255, 0.12)"
        shadow="rgba(0, 0, 0, 0.30)"
    fi

    cat > "$css3" << CSS_EOF
/* Generated by Termux Desktop theme.sh: ${name} */
@define-color theme_bg_color ${bg};
@define-color theme_fg_color ${fg};
@define-color theme_base_color ${bg};
@define-color theme_text_color ${fg};
@define-color theme_selected_bg_color ${accent};
@define-color theme_selected_fg_color ${bg};
@define-color panel_bg ${panel};
@define-color soft_border ${border};

window, dialog, headerbar, toolbar, menubar {
  background-color: ${bg};
  color: ${fg};
}

headerbar, .titlebar {
  border-bottom: 1px solid ${border};
  box-shadow: 0 1px 8px ${shadow};
}

button, entry, combobox, spinbutton, treeview, list, notebook, tab {
  background-color: ${panel};
  color: ${fg};
  border-color: ${border};
  border-radius: 6px;
}

button:hover, entry:focus, combobox:hover, spinbutton:focus, notebook tab:hover {
  border-color: ${accent};
  box-shadow: inset 0 -2px ${accent};
}

button:checked, notebook tab:checked {
  background-color: ${accent};
  color: ${bg};
}

*:selected, selection, progressbar progress, scale highlight {
  background-color: ${accent};
  color: ${bg};
}

menu, popover, tooltip {
  background-color: ${panel};
  color: ${fg};
  border: 1px solid ${border};
}

scrollbar slider {
  background-color: ${accent};
  border-radius: 8px;
  min-width: 7px;
  min-height: 7px;
}

#XfcePanelWindow,
.xfce4-panel {
  background-color: ${panel};
  color: ${fg};
  border-color: ${border};
}

.xfce4-panel button,
.xfce4-panel .button,
#whiskermenu-button {
  background: transparent;
  color: ${fg};
  border: 1px solid transparent;
  border-radius: 7px;
  margin: 2px;
  padding: 3px 7px;
}

.xfce4-panel button:hover,
.xfce4-panel .button:hover,
#whiskermenu-button:hover {
  background-color: alpha(@theme_selected_bg_color, 0.18);
  border-color: alpha(@theme_selected_bg_color, 0.45);
}

.xfce4-panel button:checked,
.tasklist button:checked,
.tasklist button:active {
  background-color: alpha(@theme_selected_bg_color, 0.24);
  border-bottom: 2px solid ${accent};
}

VteTerminal, TerminalScreen, vte-terminal {
  background-color: ${bg};
  color: ${fg};
}
CSS_EOF
    cp "$css3" "$css4" 2>/dev/null || true
    ok "GTK accents applied"
}

_save_theme_marker() {
    local name="$1" mode="$2" bg="$3" panel="$4" fg="$5" accent="$6" wallpaper="$7"
    mkdir -p "$HOME/.config/termux-desktop" 2>/dev/null
    cat > "$HOME/.config/termux-desktop/current-theme.conf" << THEME_EOF
name=${name}
mode=${mode}
background=${bg}
panel=${panel}
foreground=${fg}
accent=${accent}
wallpaper=${wallpaper}
THEME_EOF
}

_set_wallpaper() {
    local hex="$1"
    local wallpaper_file="${2:-}"
    local hex_clean="${hex//#/}"
    local wallpaper_path="$HOME/.config/xfce4/wallpaper-${hex_clean}.png"
    local src_path="$PREFIX/share/wallpapers/${hex_clean}.png"

    mkdir -p "$HOME/.config/xfce4" 2>/dev/null

    if [ -n "$wallpaper_file" ] && [ -f "$PREFIX/share/wallpapers/$wallpaper_file" ]; then
        wallpaper_path="$HOME/.config/xfce4/$wallpaper_file"
        cp "$PREFIX/share/wallpapers/$wallpaper_file" "$wallpaper_path" 2>/dev/null
    elif [ -f "$src_path" ]; then
        cp "$src_path" "$wallpaper_path" 2>/dev/null
    elif [ -f "$PREFIX/bin/convert" ]; then
        "$PREFIX/bin/convert" -size 1920x1080 "xc:${hex}" "$wallpaper_path" 2>/dev/null
    elif [ -f "$PREFIX/bin/python3" ]; then
        # Generate solid-color PNG using Python
        "$PREFIX/bin/python3" -c "
import struct, zlib
def create_png(w, h, r, g, b):
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    raw = b''
    for _ in range(h):
        raw += b'\\x00' + bytes([r, g, b]) * w
    return (b'\\x89PNG\\r\\n\\x1a\\n' +
            chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(raw)) +
            chunk(b'IEND', b''))
r, g, b = int('${hex_clean}'[0:2], 16), int('${hex_clean}'[2:4], 16), int('${hex_clean}'[4:6], 16)
with open('${wallpaper_path}', 'wb') as f:
    f.write(create_png(1920, 1080, r, g, b))
" 2>/dev/null
    elif [ -f "$PREFIX/bin/python" ]; then
        "$PREFIX/bin/python" -c "
import struct, zlib
def create_png(w, h, r, g, b):
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    raw = b''
    for _ in range(h):
        raw += b'\\x00' + bytes([r, g, b]) * w
    return (b'\\x89PNG\\r\\n\\x1a\\n' +
            chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(raw)) +
            chunk(b'IEND', b''))
r, g, b = int('${hex_clean}'[0:2], 16), int('${hex_clean}'[2:4], 16), int('${hex_clean}'[4:6], 16)
with open('${wallpaper_path}', 'wb') as f:
    f.write(create_png(1920, 1080, r, g, b))
" 2>/dev/null
    else
        info "No tool to generate wallpaper for ${hex}"
        return
    fi

    [ -f "$wallpaper_path" ] || return

    local desktop_xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
    if [ -f "$desktop_xml" ]; then
        sed -i "s|<property name=\"image-style\" type=\"int\" value=\"[^\"]*\"/>|<property name=\"image-style\" type=\"int\" value=\"1\"/>|g" "$desktop_xml" 2>/dev/null || true
        sed -i "s|<property name=\"last-image\" type=\"string\" value=\"[^\"]*\"/>|<property name=\"last-image\" type=\"string\" value=\"${wallpaper_path}\"/>|g" "$desktop_xml" 2>/dev/null || true
    fi

    local monitor base
    for monitor in monitor0 monitorVNC-0 monitorbuiltin monitorDexDisplay; do
        base="/backdrop/screen0/${monitor}/workspace0"
        _xfconf_set xfce4-desktop "${base}/last-image" string "$wallpaper_path" >/dev/null 2>&1 || true
        _xfconf_set xfce4-desktop "${base}/image-style" int 1 >/dev/null 2>&1 || true
    done
    ok "Wallpaper set"
}

_apply_full() {
    local name="$1" desc="$2" gtk="$3" panel_hex="$4" desktop_hex="$5"
    local term_fg="$6" term_bg="$7" term_cursor="$8" term_palette="$9"
    local font="${10}"
    local wallpaper_file="${11:-}"
    local mode="${12:-dark}"

    echo ""
    echo -e "${CYAN}${BOLD}  Applying ${name} Theme...${NC}"
    echo "  ${desc}"
    echo ""

    _set_gtk_theme "$gtk"
    _set_panel_color "$panel_hex"
    _set_desktop_color "$desktop_hex"
    _set_terminal "$term_fg" "$term_bg" "$term_cursor" "$term_palette" "$font"
    _set_gtk_css "$term_bg" "$panel_hex" "$term_fg" "$term_cursor" "$name" "$mode"
    _set_wallpaper "$desktop_hex" "$wallpaper_file"
    _save_theme_marker "$name" "$mode" "$term_bg" "$panel_hex" "$term_fg" "$term_cursor" "$wallpaper_file"

    # Restart desktop components to apply live color/wallpaper changes.
    _setup_xfconf_env
    _restart_if_running xfsettingsd "$PREFIX/bin/xfsettingsd --replace" "Settings daemon"
    _restart_if_running xfdesktop "$PREFIX/bin/xfdesktop --reload" "Desktop"
    _restart_if_running xfce4-panel "$PREFIX/bin/xfce4-panel -r" "Panel"

    ok "${name} theme applied"
}

# ════════════════════════════════════════════════════════════
# Theme 1: Nord
# ════════════════════════════════════════════════════════════
apply_nord() {
    _apply_full \
        "Nord" \
        "Arctic cool-toned dark — muted blues and greens" \
        "Adwaita-dark" \
        "#3b4252" \
        "#2e3440" \
        "#e5e9f0" \
        "#3b4252" \
        "#e5e9f0" \
        "#3b4252;#bf616a;#a3be8c;#ebcb8b;#81a1c1;#b48ead;#8fbcbb;#e5e9f0;#4c566a;#bf616a;#a3be8c;#ebcb8b;#81a1c1;#b48ead;#8fbcbb;#eceff4" \
        "Monospace 11" \
        "nord.jpg"
}

# ════════════════════════════════════════════════════════════
# Theme 2: Catppuccin Mocha
# ════════════════════════════════════════════════════════════
apply_catppuccin_mocha() {
    _apply_full \
        "Catppuccin Mocha" \
        "Warm plum dark — soft pastel accents on deep background" \
        "Adwaita-dark" \
        "#313244" \
        "#1e1e2e" \
        "#cdd6f4" \
        "#1e1e2e" \
        "#cdd6f4" \
        "#1e1e2e;#f38ba8;#a6e3a1;#f9e2af;#89b4fa;#cba6f7;#94e2d5;#cdd6f4;#585b70;#f38ba8;#a6e3a1;#f9e2af;#89b4fa;#cba6f7;#94e2d5;#a6adc8" \
        "Monospace 11" \
        "catppuccin-mocha.jpg"
}

# ════════════════════════════════════════════════════════════
# Theme 3: Catppuccin Latte
# ════════════════════════════════════════════════════════════
apply_catppuccin_latte() {
    _apply_full \
        "Catppuccin Latte" \
        "Warm cream light — soft pastels on bright background" \
        "Adwaita" \
        "#dce0e8" \
        "#eff1f5" \
        "#4c4f69" \
        "#eff1f5" \
        "#4c4f69" \
        "#4c4f69;#d20f39;#40a02b;#df8e1d;#1e66f5;#8839ef;#179299;#ccd0da;#9ca0b0;#d20f39;#40a02b;#df8e1d;#1e66f5;#8839ef;#179299;#bcc0cc" \
        "Monospace 11" \
        "catppuccin-latte.jpg" \
        "light"
}

# ════════════════════════════════════════════════════════════
# Theme 4: Solarized Dark
# ════════════════════════════════════════════════════════════
apply_solarized_dark() {
    _apply_full \
        "Solarized Dark" \
        "Blue-green dark — intellectual, refined, timeless" \
        "Adwaita-dark" \
        "#073642" \
        "#002b36" \
        "#839496" \
        "#002b36" \
        "#839496" \
        "#073642;#dc322f;#859900;#b58900;#268bd2;#d33682;#2aa198;#eee8d5;#586e75;#cb4b16;#586e75;#657b83;#839496;#6c71c4;#93a1a1;#fdf6e3" \
        "Monospace 11" \
        "solarized-dark.jpg"
}

# ════════════════════════════════════════════════════════════
# Theme 5: Tokyo Night (Storm)
# ════════════════════════════════════════════════════════════
apply_tokyo_night() {
    _apply_full \
        "Tokyo Night" \
        "Deep navy dark — neon accents, Tokyo cityscape vibe" \
        "Adwaita-dark" \
        "#24283b" \
        "#1f2335" \
        "#c0caf5" \
        "#1f2335" \
        "#c0caf5" \
        "#1d202f;#f7768e;#9ece6a;#e0af68;#7aa2f7;#bb9af7;#7dcfff;#a9b1d6;#414868;#f7768e;#9ece6a;#e0af68;#7aa2f7;#bb9af7;#7dcfff;#c0caf5" \
        "Monospace 11" \
        "tokyo-night.jpg"
}

# ════════════════════════════════════════════════════════════
# Theme 6: Tokyo Night Light
# ════════════════════════════════════════════════════════════
apply_tokyo_night_light() {
    _apply_full \
        "Tokyo Night Light" \
        "Clean modern light — soft gray-blue, muted accents" \
        "Adwaita" \
        "#d6d8e0" \
        "#e6e7ed" \
        "#343b58" \
        "#e6e7ed" \
        "#343b58" \
        "#2e3440;#8c4351;#385f0d;#8f5e15;#2959aa;#5a3e8e;#0f4b6e;#d2d4de;#9699a3;#8c4351;#385f0d;#8f5e15;#2959aa;#5a3e8e;#0f4b6e;#343b58" \
        "Monospace 11" \
        "tokyo-night-light.jpg" \
        "light"
}

# ════════════════════════════════════════════════════════════
# Theme 7: Gruvbox Dark
# ════════════════════════════════════════════════════════════
apply_gruvbox_dark() {
    _apply_full \
        "Gruvbox Dark" \
        "Warm earthy retro — brown/orange tones, vintage computing" \
        "Adwaita-dark" \
        "#3c3836" \
        "#282828" \
        "#ebdbb2" \
        "#282828" \
        "#ebdbb2" \
        "#282828;#fb4934;#b8bb26;#fabd2f;#83a598;#d3869b;#8ec07c;#ebdbb2;#928374;#fb4934;#b8bb26;#fabd2f;#83a598;#d3869b;#8ec07c;#fbf1c7" \
        "Monospace 11" \
        "gruvbox-dark.jpg"
}

# ════════════════════════════════════════════════════════════
# Theme 8: Rose Pine
# ════════════════════════════════════════════════════════════
apply_rose_pine() {
    _apply_full \
        "Rose Pine" \
        "Muted rose-tinted dark — lavender and foam accents" \
        "Adwaita-dark" \
        "#26233a" \
        "#191724" \
        "#e0def4" \
        "#191724" \
        "#e0def4" \
        "#26233a;#eb6f92;#31748f;#f6c177;#9ccfd8;#c4a7e7;#ebbcba;#e0def4;#6e6a86;#eb6f92;#31748f;#f6c177;#9ccfd8;#c4a7e7;#ebbcba;#908caa" \
        "Monospace 11" \
        "rose-pine.jpg"
}

# ════════════════════════════════════════════════════════════
# Auto mode
# ════════════════════════════════════════════════════════════
if [ -n "$AUTO_THEME" ]; then
    case "$AUTO_THEME" in
        nord)                apply_nord ;;
        catppuccin-mocha|mocha) apply_catppuccin_mocha ;;
        catppuccin-latte|latte) apply_catppuccin_latte ;;
        solarized|solarized-dark) apply_solarized_dark ;;
        tokyo-night|tokyo)  apply_tokyo_night ;;
        tokyo-night-light|tokyo-light) apply_tokyo_night_light ;;
        gruvbox|gruvbox-dark) apply_gruvbox_dark ;;
        rose-pine|rosepine) apply_rose_pine ;;
        *)
            warn "Unknown theme '$AUTO_THEME'"
            echo "  Available: nord, mocha, latte, solarized, tokyo, tokyo-light, gruvbox, rose-pine"
            exit 1
            ;;
    esac
    exit 0
fi

# ════════════════════════════════════════════════════════════
# Interactive Menu
# ════════════════════════════════════════════════════════════
clear
echo ""
echo "=================================================="
echo "       Termux Desktop — Theme Switcher v2.0"
echo "=================================================="
echo ""
echo "  DARK THEMES:"
echo "    1) Nord             Arctic blues, muted & calm"
echo "    2) Catppuccin Mocha Warm plum, soft pastels"
echo "    3) Solarized Dark   Blue-green, intellectual"
echo "    4) Tokyo Night      Deep navy, neon accents"
echo "    5) Gruvbox Dark     Warm earthy retro groove"
echo "    6) Rose Pine        Rose-tinted, lavender foam"
echo ""
echo "  LIGHT THEMES:"
echo "    7) Catppuccin Latte Warm cream, pastel accents"
echo "    8) Tokyo Night Lt   Clean gray-blue modern"
echo ""
echo "=================================================="
echo ""
read -rp "  Choose theme [1-8]: " CHOICE

case "$CHOICE" in
    1) apply_nord ;;
    2) apply_catppuccin_mocha ;;
    3) apply_solarized_dark ;;
    4) apply_tokyo_night ;;
    5) apply_gruvbox_dark ;;
    6) apply_rose_pine ;;
    7) apply_catppuccin_latte ;;
    8) apply_tokyo_night_light ;;
    *)
        warn "Invalid choice — applying Nord as default"
        apply_nord ;;
esac

echo ""
echo -e "  ${GREEN}Theme change saved.${NC}"
echo "  Run 'xfce4-panel -r' or restart your session."
echo ""
echo "  Switch anytime: bash ~/theme.sh"
