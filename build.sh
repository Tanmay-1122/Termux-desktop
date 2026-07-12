#!/bin/bash
# ============================================================
#   build.sh — Local package builder (Linux / WSL / Termux)
#   Run this after editing scripts in termux-dex-pkgsrc/
#   to regenerate the repo/ .deb and Packages index.
#
#   Usage:
#     bash build.sh          # builds + updates repo/
#     bash build.sh --check  # syntax-checks all scripts only
# ============================================================
set -euo pipefail

SRC="termux-dex-pkgsrc/termux-dex_1.0_all"
REPO="repo"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }
info() { echo -e "  → $1"; }

# ── Syntax check all shell scripts ────────────────────────────
check_syntax() {
    local errors=0
    info "Checking bash syntax..."
    while IFS= read -r -d '' f; do
        if bash -n "$f" 2>&1; then
            ok "$(basename "$f")"
        else
            echo -e "  ${RED}FAIL${NC}: $f"
            errors=$((errors + 1))
        fi
    done < <(find "$SRC/data" . -maxdepth 1 -name "*.sh" -print0 2>/dev/null)
    [ "$errors" -eq 0 ] && ok "All scripts pass syntax check" || fail "$errors script(s) have syntax errors"
}

check_syntax

[ "${1:-}" = "--check" ] && exit 0

# ── Check dependencies ─────────────────────────────────────────
for cmd in dpkg-deb dpkg-scanpackages gzip; do
    command -v "$cmd" &>/dev/null || fail "'$cmd' not found. Install: sudo apt install dpkg-dev apt-utils"
done

# ── Read version ───────────────────────────────────────────────
VERSION=$(cat VERSION 2>/dev/null || grep '^Version:' "$SRC/DEBIAN/control" | awk '{print $2}')
DEB_NAME="termux-dex_${VERSION}_all.deb"
echo ""
info "Building $DEB_NAME ..."

# ── Fix permissions ────────────────────────────────────────────
chmod 755 "$SRC/DEBIAN/postinst" "$SRC/DEBIAN/postrm" 2>/dev/null || true
find "$SRC/data" -type f -name "*.sh" -exec chmod 755 {} \;

# ── Build .deb ─────────────────────────────────────────────────
dpkg-deb --build --root-owner-group "$SRC" "$REPO/$DEB_NAME"
ok "Built: $REPO/$DEB_NAME"

# ── Regenerate Packages index ──────────────────────────────────
info "Regenerating apt Packages index..."
(cd "$REPO" && dpkg-scanpackages --multiversion . > Packages && gzip -k -f Packages)
ok "repo/Packages and repo/Packages.gz updated"

# ── Regenerate SHA-256 checksums ──────────────────────────────
info "Regenerating sha256sums.txt..."
FILES=$(find . -maxdepth 1 -type f \( -name "*.sh" -o -name "*.css" -o -name "*.conf" -o -name "VERSION" \) | sort)
if command -v sha256sum &>/dev/null; then
    (cd . && sha256sum $FILES) > sha256sums.txt
    ok "sha256sums.txt regenerated (${VERSION})"
else
    warn "sha256sum not available — skipping checksum regeneration"
fi

echo ""
echo -e "${CYAN}Done! Commit and push:${NC}"
echo "  git add repo/ && git commit -m 'build: termux-dex v${VERSION}' && git push"
echo ""
