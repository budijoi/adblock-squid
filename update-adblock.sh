#!/bin/bash
# AdBlock List Updater — untuk dnsmasq
# Download & gabung multiple reliable blocklists
# Usage: sudo bash update-adblock.sh

ADBLOCK_DIR="/etc/adblock"
ADBLOCK_LIST="$ADBLOCK_DIR/blocked.hosts"
ADBLOCK_LOG="/var/log/adblock-update.log"
TEMP_DIR=$(mktemp -d)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$ADBLOCK_LOG"
    echo -e "$*"
}

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$ADBLOCK_DIR"

log "${CYAN}${BOLD}[*] Memulai update adblock lists...${NC}"

# === Blocklist sources (reliable, maintained, dnsmasq-friendly) ===
SOURCES=(
    # StevenBlack Unified (adware + malware + tracking)
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
    # someonewhocares.org — Dan Pollock's list (updated daily)
    "https://someonewhocares.org/hosts/zero/hosts"
    # OISD Big (domain-only, very comprehensive)
    "https://big.oisd.nl/domainswild"
)

TOTAL=0
FAILED=0
for i in "${!SOURCES[@]}"; do
    url="${SOURCES[$i]}"
    filename=$(basename "$url" | sed 's/[^a-zA-Z0-9]/_/g')
    outfile="$TEMP_DIR/source_${i}_${filename}"

    log "  ${DIM}[$((i+1))/${#SOURCES[@]}] Downloading:${NC} $url"

    if curl -sSL --connect-timeout 15 --max-time 60 "$url" -o "$outfile" 2>/dev/null; then
        lines=$(wc -l < "$outfile")
        TOTAL=$((TOTAL + lines))
        log "    ${GREEN}✓${NC} ${lines} lines downloaded"
    else
        log "    ${RED}✗${NC} Gagal mendownload"
        FAILED=$((FAILED + 1))
    fi
done

log ""
log "${CYAN}${BOLD}[*] Menggabungkan dan memproses...${NC}"

# Gabung semua source, filter hanya domain, hapus duplikat
# Format: 0.0.0.0 domain.com
(
    cat "$TEMP_DIR"/source_* 2>/dev/null

    # Source oisd.nl pake format domain-only (tanpa 0.0.0.0), tambahin prefix
    if [ -f "$TEMP_DIR/source_2_domainswild" ]; then
        sed 's/^/0.0.0.0 /' "$TEMP_DIR/source_2_domainswild"
    fi
) | grep -v -E '^#|^$|^255\.|^127\.0\.0\.1 localhost|^::1' | \
  awk '{print $1, $2}' | \
  grep -E '^0\.0\.0\.0\s+' | \
  awk '{print tolower($2)}' | \
  grep -v -E '(^localhost$|^localhost\.localdomain$|^broadcasthost$|^local$)' | \
  sort -u | \
  awk '{print "0.0.0.0 " $1}' > "$TEMP_DIR/blocked_clean.hosts"

CLEAN_COUNT=$(wc -l < "$TEMP_DIR/blocked_clean.hosts")

log "  ${GREEN}${CLEAN_COUNT}${NC} unique domains akan diblokir"

# Backup existing
if [ -f "$ADBLOCK_LIST" ]; then
    cp "$ADBLOCK_LIST" "${ADBLOCK_LIST}.bak"
fi

# Copy ke lokasi final
cp "$TEMP_DIR/blocked_clean.hosts" "$ADBLOCK_LIST"
chmod 644 "$ADBLOCK_LIST"

# Write stats
cat > "${ADBLOCK_DIR}/stats.txt" << EOF
Last Update: $(date '+%Y-%m-%d %H:%M:%S')
Sources: ${#SOURCES[@]}
Total Domains Blocked: $CLEAN_COUNT
EOF

# Restart dnsmasq
log ""
log "${CYAN}${BOLD}[*] Merestart dnsmasq...${NC}"
if systemctl restart dnsmasq 2>/dev/null; then
    log "  ${GREEN}✓ dnsmasq berhasil direstart${NC}"
else
    log "  ${RED}✗ Gagal restart dnsmasq${NC}"
fi

log ""
log "${GREEN}${BOLD}✓ Update selesai: ${CLEAN_COUNT} domain diblokir${NC}"
exit 0
