#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
#   Termux Desktop — Uninstaller
#   Removes packages, configs, scripts, shortcuts, wallpapers,
#   and releases the wake lock.
#
#   Usage:
#     bash ~/uninstall.sh
# ============================================================

set -eo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!!]${NC} $1"; }
info() { echo -e "  ${CYAN}->${NC} $1"; }
fail() { echo -e "  ${RED}[XX]${NC} $1"; exit 1; }

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
PROJECT_VER=$(cat "$HOME/.termux-desktop-version" 2>/dev/null || echo "?")

echo ""
echo -e "${BOLD}==============================================${NC}"
echo -e "${BOLD}  Termux Desktop v${PROJECT_VER} — Uninstall${NC}"
echo -e "${BOLD}==============================================${NC}"
echo ""

echo -e "${YELLOW}WARNING: This will remove Termux Desktop files and configs.${NC}"
echo -e "${DIM}  Packages marked as user-installed will be removed.${NC}"
echo -e "${DIM}  Your home directory contents (documents, projects) will NOT be touched.${NC}"
echo ""
read -rp "$(echo -e "${BOLD}Continue? [y/N]${NC} ")" confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo ""
    warn "Uninstall cancelled."
    exit 0
fi

echo ""

# ── Remove scripts from $HOME ─────────────────────────
info "Removing scripts..."
SCRIPTS=(start-desktop.sh setup.sh theme.sh manage-apps.sh dashboard.sh td-update.sh lib.sh install.sh uninstall.sh VERSION)
for _s in "${SCRIPTS[@]}"; do
    rm -f "$HOME/$_s" 2>/dev/null || true
done
rm -f "$HOME/.termux-desktop-version" 2>/dev/null || true
rm -f "$HOME/.termux-desktop-sha256sums" 2>/dev/null || true
rm -f "$HOME/termux-desktop-install.log" 2>/dev/null || true
ok "Scripts removed"

# ── Remove shell commands ─────────────────────────────
info "Removing shell commands..."
rm -f "$PREFIX/bin/startdesktop" 2>/dev/null || true
rm -f "$PREFIX/bin/td-update" 2>/dev/null || true
ok "Commands removed"

# ── Remove widget shortcuts ───────────────────────────
info "Removing widget shortcuts..."
rm -rf "$HOME/.shortcuts" 2>/dev/null || true
ok "Shortcuts removed"

# ── Remove config directories ─────────────────────────
info "Removing configs..."
rm -rf "$HOME/.config/xfce4" 2>/dev/null || true
rm -rf "$HOME/.config/gtk-3.0" 2>/dev/null || true
rm -rf "$HOME/.config/gtk-4.0" 2>/dev/null || true
rm -rf "$HOME/.config/picom" 2>/dev/null || true
rm -rf "$HOME/.config/termux-desktop" 2>/dev/null || true
rm -rf "$HOME/.config/Thunar" 2>/dev/null || true
rm -rf "$PREFIX/share/termux-desktop" 2>/dev/null || true
ok "Configs removed"

# ── Remove wallpapers ─────────────────────────────────
info "Removing wallpapers..."
rm -rf "$PREFIX/share/wallpapers" 2>/dev/null || true
ok "Wallpapers removed"

# ── Release wake lock ─────────────────────────────────
info "Releasing wake lock..."
termux-wake-unlock 2>/dev/null || true
ok "Wake lock released"

# ── Summary ───────────────────────────────────────────
echo ""
echo -e "${BOLD}Done!${NC} Termux Desktop has been uninstalled."
echo -e "  ${DIM}Re-run the installer anytime:${NC}"
echo -e "  ${CYAN}curl -fsSL https://raw.githubusercontent.com/Tanmay-1122/Termux-desktop/main/install.sh | bash${NC}"
echo ""
echo -e "  ${DIM}Note: Packages (xfce4, etc.) are still installed.${NC}"
echo -e "  ${DIM}To remove them too, run:${NC}"
echo -e "  ${DIM}  pkg remove xfce4 termux-x11-nightly pulseaudio dbus${NC}"
echo ""
