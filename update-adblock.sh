#!/bin/bash
# AdBlock List Updater — untuk dnsmasq
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

cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

mkdir -p "$ADBLOCK_DIR"

log "${CYAN}${BOLD}[*] Memulai update adblock lists...${NC}"

SOURCES=(
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
    "https://someonewhocares.org/hosts/zero/hosts"
    "https://big.oisd.nl/domainswild"
    "https://raw.githubusercontent.com/ABPindo/indonesianadblockrules/master/subscriptions/domain.txt"
)

TOTAL=0
FAILED=0
for i in "${!SOURCES[@]}"; do
    url="${SOURCES[$i]}"
    filename=$(basename "$url" | sed 's/[^a-zA-Z0-9]/_/g')
    outfile="$TEMP_DIR/source_${i}_${filename}"

    log "  ${DIM}[$((i+1))/${#SOURCES[@]}] Download:${NC} $url"

    if curl -sSL --connect-timeout 15 --max-time 60 "$url" -o "$outfile" 2>/dev/null; then
        lines=$(wc -l < "$outfile")
        TOTAL=$((TOTAL + lines))
        log "    ${GREEN}✓${NC} ${lines} baris"
    else
        log "    ${RED}✗${NC} Gagal"
        FAILED=$((FAILED + 1))
    fi
done

log ""
log "${CYAN}${BOLD}[*] Memproses blocklist...${NC}"

shopt -s nullglob
(
    cat "$TEMP_DIR"/source_*

    # Domain-only lists — tambah prefix 0.0.0.0
    for domain_src in "$TEMP_DIR"/source_2_domainswild "$TEMP_DIR"/source_3_domain_txt; do
        [ -f "$domain_src" ] && sed 's/^/0.0.0.0 /' "$domain_src"
    done
) | grep -v -E '^#|^$|^255\.|^127\.0\.0\.1 localhost|^::1' | \
  awk '{print $1, $2}' | \
  grep -E '^0\.0\.0\.0\s+' | \
  awk '{print tolower($2)}' | \
  grep -v -E '(^localhost$|^localhost\.localdomain$|^broadcasthost$|^local$)' | \
  sort -u | \
  awk '{print "0.0.0.0 " $1}' > "$TEMP_DIR/blocked_clean.hosts"
shopt -u nullglob

CLEAN_COUNT=$(wc -l < "$TEMP_DIR/blocked_clean.hosts")
log "  ${GREEN}${CLEAN_COUNT}${NC} unique domain akan diblokir"

[ -f "$ADBLOCK_LIST" ] && cp "$ADBLOCK_LIST" "${ADBLOCK_LIST}.bak"
cp "$TEMP_DIR/blocked_clean.hosts" "$ADBLOCK_LIST"
chmod 644 "$ADBLOCK_LIST"

cat > "${ADBLOCK_DIR}/stats.txt" << EOF
Last Update: $(date '+%Y-%m-%d %H:%M:%S')
Sources: ${#SOURCES[@]}
Total Domains: $CLEAN_COUNT
EOF

log ""
log "${CYAN}${BOLD}[*] Restart dnsmasq...${NC}"
if systemctl restart dnsmasq 2>/dev/null; then
    log "  ${GREEN}✓${NC} OK"
else
    log "  ${RED}✗${NC} Gagal restart"
fi

log ""
log "${GREEN}${BOLD}✓ Selesai: ${CLEAN_COUNT} domain${NC}"
exit 0
