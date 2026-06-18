#!/bin/bash
# AdBlocker + Squid Cache Proxy All-in-One Installer
# Untuk X96Mini / B860H v1 (Armbian)
# Usage: sudo bash install.sh

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${BOLD}[!] Jalankan dengan sudo: sudo bash $0${NC}"; exit 1
fi

# === PROGRESS ===
BAR_LEN=40; TOTAL_STEPS=0; CUR_STEP=0
init_progress() { TOTAL_STEPS=$1; CUR_STEP=0; }
show_progress() {
    CUR_STEP=$((CUR_STEP + 1))
    local pct=$((CUR_STEP * 100 / TOTAL_STEPS))
    local filled=$((pct * BAR_LEN / 100))
    local empty=$((BAR_LEN - filled))
    local bar=$(printf "${GREEN}%${filled}s${NC}" | tr ' ' '█')
    bar+=$(printf "${DIM}%${empty}s${NC}" | tr ' ' '░')
    echo -ne "\r${CYAN}${BOLD}[${NC}${bar}${CYAN}${BOLD}] ${pct}%${NC} ${1}"
    [ "$CUR_STEP" -eq "$TOTAL_STEPS" ] && echo ""
}
spinner() {
    local pid=$1 msg=$2 spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}%c${NC} %s" "${spin:$i:1}" "$msg"
        i=$(( (i + 1) % 10 )); sleep 0.1
    done
    printf "\r${GREEN}✓${NC} %s\n" "$msg"
}
run_spinner() {
    local msg=$1; shift
    ("$@" > /dev/null 2>&1) &
    spinner $! "$msg"; wait $!; return $?
}

# === BANNER ===
clear
echo ""
echo -e "  ${CYAN}╔═══════════════════════════════════════════╗${NC}"
echo -e "  ${CYAN}║${NC}  ${BOLD}${MAGENTA}░▀▐▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▌▀░${NC}  ${BOLD}${YELLOW}ADBLOCK + SQUID${NC}      ${CYAN}║${NC}"
echo -e "  ${CYAN}║${NC}  ${BOLD}${MAGENTA}▄█▓▒░ADBLOCK░▒▓█▄${NC}     ${BOLD}${YELLOW}All-in-One Installer${NC}${CYAN}║${NC}"
echo -e "  ${CYAN}║${NC}  ${BOLD}${MAGENTA}▀▐▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▌▀${NC}  ${BOLD}${YELLOW}for Armbian${NC}        ${CYAN}║${NC}"
echo -e "  ${CYAN}╚═══════════════════════════════════════════╝${NC}"
echo ""

# === VARIABEL ===
ADBLOCK_DIR="/etc/adblock"
ADBLOCK_LIST="$ADBLOCK_DIR/blocked.hosts"
ADBLOCK_LOG="/var/log/adblock-update.log"
SQUID_CONF="/etc/squid/squid.conf"
SQUID_BACKUP="/etc/squid/squid.conf.bak.adblock"
DNSMASQ_CONF="/etc/dnsmasq.conf"
DNSMASQ_ADBLOCK_CONF="/etc/dnsmasq.d/adblock.conf"

# === DETEKSI SISTEM ===
echo -e "${BLUE}${BOLD}━━━ SYSTEM INFORMATION ━━━${NC}"
echo -e "  ${DIM}Hostname :${NC} $(hostname)"
echo -e "  ${DIM}Kernel   :${NC} $(uname -r)"
echo -e "  ${DIM}Arch     :${NC} $(uname -m)"
echo -e "  ${DIM}Memory   :${NC} $(free -h | awk '/^Mem:/ {print $2}')"
echo -e "  ${DIM}Disk     :${NC} $(df -h / | awk 'NR==2 {print $4}') free"
echo ""

IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
IP_ADDR=$(ip addr show "$IFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
SUBNET=$(ip route 2>/dev/null | grep -E "link src $IP_ADDR|$IFACE.*proto kernel" | grep -oP '\d+\.\d+\.\d+\.\d+/\d+' | head -1)
[ -z "$SUBNET" ] && SUBNET=$(ip route 2>/dev/null | grep "$IFACE" | grep -oP '\d+\.\d+\.\d+\.\d+/\d+' | head -1)
[ -z "$SUBNET" ] && SUBNET="192.168.1.0/24"
echo -e "  ${DIM}IP Address:${NC} ${GREEN}$IP_ADDR${NC}"
echo -e "  ${DIM}Subnet LAN :${NC} $SUBNET"
echo ""

# === PRE-FLIGHT ===
echo -e "${BLUE}${BOLD}━━━ PRE-FLIGHT CHECKS ━━━${NC}"
echo -ne "  ${DIM}Internet  :${NC} "
if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo -e "${GREEN}Connected${NC}"
else
    echo -e "${RED}No connection${NC}"
    echo -e "  ${YELLOW}⚠ Pastikan STB terhubung ke internet.${NC}"
fi
echo ""

# === DETEKSI KONFLIK SERVICE ===
echo -e "${BLUE}${BOLD}━━━ CONFLICT DETECTION ━━━${NC}"

detect_conflicts() {
    local conflicts=()

    # DNS/adblock services (port 53)
    for svc in systemd-resolved pihole-FTL adguardhome bind9 unbound stubby dnscrypt-proxy dnsmasq; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            conflicts+=("$svc (running)")
        elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            conflicts+=("$svc (enabled, not running)")
        fi
    done

    # Proxy services (port 3128)
    for svc in privoxy tinyproxy haproxy squid; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            conflicts+=("$svc (running)")
        elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            conflicts+=("$svc (enabled, not running)")
        fi
    done

    # Pi-hole via binary check
    if command -v pihole &> /dev/null && ! systemctl is-enabled --quiet pihole-FTL 2>/dev/null; then
        conflicts+=("pihole (binary terinstall)")
    fi

    # AdGuard Home via binary check
    if [ -f /opt/AdGuardHome/AdGuardHome ] && ! systemctl is-enabled --quiet adguardhome 2>/dev/null; then
        conflicts+=("AdGuard Home (binary terinstall)")
    fi

    # Cek port occupancy (tanpa netstat/ss fallback)
    local port53 port3128
    if command -v ss &> /dev/null; then
        port53=$(ss -tlnp 2>/dev/null | grep ':53 ' | head -1)
        port3128=$(ss -tlnp 2>/dev/null | grep ':3128 ' | head -1)
    elif command -v netstat &> /dev/null; then
        port53=$(netstat -tlnp 2>/dev/null | grep ':53 ' | head -1)
        port3128=$(netstat -tlnp 2>/dev/null | grep ':3128 ' | head -1)
    fi

    if [ -n "$port53" ]; then
        local proc53
        proc53=$(echo "$port53" | grep -oP 'pid=\K[0-9]+|users:\(\("\K[^"]+' | head -1)
        conflicts+=("Port 53: $port53")
    fi
    if [ -n "$port3128" ]; then
        conflicts+=("Port 3128: $port3128")
    fi

    printf '%s\n' "${conflicts[@]}"
}

# Collect conflicts
mapfile -t CONFLICTS < <(detect_conflicts)

if [ ${#CONFLICTS[@]} -gt 0 ]; then
    echo -e "  ${YELLOW}${BOLD}⚠ Service/port konflik ditemukan:${NC}"
    for c in "${CONFLICTS[@]}"; do
        echo -e "    ${RED}◈${NC} $c"
    done
    echo ""
    echo -e "  ${YELLOW}Installer akan menonaktifkan service tersebut untuk${NC}"
    echo -e "  ${YELLOW}mencegah konflik port. Backup config akan dibuat.${NC}"
    echo ""
    echo -ne "  ${BOLD}Lanjutkan? [Y/n]:${NC} "
    read -r CONFIRM
    if [[ "$CONFIRM" =~ ^[Nn] ]]; then
        echo -e "  ${RED}Dibatalkan oleh user.${NC}"
        exit 1
    fi

    # Stop & disable conflicting services
    for svc in systemd-resolved pihole-FTL adguardhome bind9 unbound stubby dnscrypt-proxy dnsmasq privoxy tinyproxy haproxy squid; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            # Backup config before disabling
            case "$svc" in
                dnsmasq)  [ -f /etc/dnsmasq.conf ] && cp /etc/dnsmasq.conf "/etc/dnsmasq.conf.bak.$(date +%Y%m%d%H%M%S)" ;;
                squid)    [ -f /etc/squid/squid.conf ] && cp /etc/squid/squid.conf "/etc/squid/squid.conf.bak.$(date +%Y%m%d%H%M%S)" ;;
                bind9)    [ -f /etc/bind/named.conf ] && cp /etc/bind/named.conf "/etc/bind/named.conf.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true ;;
            esac
            systemctl stop "$svc" 2>/dev/null || true
            systemctl disable "$svc" 2>/dev/null || true
            echo -e "  ${DIM}→ $svc dihentikan & dinonaktifkan${NC}"
        fi
    done
    echo -e "  ${GREEN}✓ Konflik dibersihkan${NC}"
else
    echo -e "  ${GREEN}✓ Tidak ada konflik${NC}"
fi
echo ""

# =============================================
# STEP 1: INSTALL & CONFIGURE DNSMASQ + ADBLOCK
# =============================================
echo -e "${BLUE}${BOLD}━━━ [1/4] ADBLOCKER (dnsmasq) ━━━${NC}"

init_progress 6

# Install dnsmasq
run_spinner "Menginstall dnsmasq" apt install -y dnsmasq
show_progress "dnsmasq terinstall"

# Buat direktori adblock
mkdir -p "$ADBLOCK_DIR"
show_progress "Direktori adblock siap"

show_progress "Port 53 siap"

# Backup dnsmasq config
[ -f "$DNSMASQ_CONF" ] && cp "$DNSMASQ_CONF" "${DNSMASQ_CONF}.bak.$(date +%Y%m%d%H%M%S)"
mkdir -p /etc/dnsmasq.d

# Tulis konfigurasi dnsmasq
cat > "$DNSMASQ_CONF" << EOF
# === Auto-generated dnsmasq config ===
# Listen on all interfaces
interface=$IFACE
bind-interfaces

# DNS
domain-needed
bogus-priv
no-resolv
server=1.1.1.1
server=8.8.8.8

# Cache DNS (percepat browsing)
cache-size=10000

# Adblock file
addn-hosts=$ADBLOCK_LIST

# Logging (opsional — comment untuk matikan)
# log-queries
# log-facility=/var/log/dnsmasq.log
EOF

# Konfigurasi Squid biar pake dnsmasq sebagai DNS
# (akan ditambahkan nanti di konfigurasi Squid)
show_progress "dnsmasq dikonfigurasi"

# Download initial adblock lists
ADBLOCK_UPDATER="/usr/local/bin/update-adblock.sh"
if [ -f "$(dirname "$0")/update-adblock.sh" ]; then
    cp "$(dirname "$0")/update-adblock.sh" "$ADBLOCK_UPDATER"
    chmod +x "$ADBLOCK_UPDATER"
elif [ -f "$ADBLOCK_UPDATER" ]; then
    : # sudah ada
fi
run_spinner "Mendownload adblock lists" bash "$ADBLOCK_UPDATER"
show_progress "Adblock lists siap"

# Start dnsmasq
run_spinner "Memulai dnsmasq" systemctl restart dnsmasq
show_progress "dnsmasq berjalan"

systemctl enable dnsmasq > /dev/null 2>&1 || true

# =============================================
# STEP 2: INSTALL & CONFIGURE SQUID CACHE
# =============================================
echo ""
echo -e "${BLUE}${BOLD}━━━ [2/4] SQUID CACHE PROXY ━━━${NC}"

init_progress 8

# Install squid
if ! command -v squid &> /dev/null; then
    run_spinner "Menginstall Squid" apt install -y squid
fi
show_progress "Squid terinstall"

# Backup existing config
if [ -f "$SQUID_CONF" ]; then
    cp "$SQUID_CONF" "$SQUID_BACKUP"
    show_progress "Backup config Squid"
else
    show_progress "Tidak ada config lama"
fi

# Tulis konfigurasi Squid baru — dengan DNS指向 ke dnsmasq lokal
cat > "$SQUID_CONF" << CONFEOFB
# === Auto-generated Squid Config (AdBlock + Cache) ===
# LAN: $SUBNET | IP: $IP_ADDR

# ACL subnet lokal
acl localnet src 0.0.0.1-0.255.255.255
acl localnet src 10.0.0.0/8
acl localnet src 100.64.0.0/10
acl localnet src 169.254.0.0/16
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl localnet src fc00::/7
acl localnet src fe80::/10
acl localnet src $SUBNET

# Port aman
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 21
acl Safe_ports port 443
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535
acl Safe_ports port 280
acl Safe_ports port 488
acl Safe_ports port 591
acl Safe_ports port 777

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager
http_access allow localhost
http_access deny to_localhost
http_access deny to_linklocal
http_access allow localnet
http_access deny all

# Port proxy
http_port 3128

# Cache settings — tuning untuk STB 1-2GB RAM
cache_mem 256 MB
maximum_object_size_in_memory 512 KB
minimum_object_size 0 KB
maximum_object_size 64 MB
cache_dir ufs /var/spool/squid 2048 16 256

# DNS — pakai dnsmasq lokal (adblock otomatis terbawa)
dns_nameservers 127.0.0.1

# Performance
memory_replacement_policy heap GDSF
cache_replacement_policy heap LFUDA

# Logging
access_log daemon:/var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
coredump_dir /var/spool/squid

# Refresh pattern
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320
CONFEOFB

show_progress "Konfigurasi Squid ditulis"

# Fix deprecated dns_order jika ada
squid -k parse 2>/dev/null | grep -q "unrecognized.*dns_order" && \
    sed -i '/^dns_order/d' "$SQUID_CONF" 2>/dev/null || true
show_progress "Validasi konfigurasi"

# Setup direktori cache & log
mkdir -p /var/log/squid
chown proxy:proxy /var/log/squid 2>/dev/null || true
show_progress "Direktori cache & log siap"

# Inisialisasi cache
squid -z > /dev/null 2>&1 || true
show_progress "Inisialisasi cache"

# Start service
systemctl restart squid 2>/dev/null || systemctl start squid 2>/dev/null || true
systemctl enable squid 2>/dev/null || true
show_progress "Squid berjalan"

# Firewall
if command -v ufw &> /dev/null; then
    ufw allow 53/tcp comment 'dnsmasq DNS' > /dev/null 2>&1
    ufw allow 53/udp comment 'dnsmasq DNS' > /dev/null 2>&1
    ufw allow 3128/tcp comment 'Squid Proxy' > /dev/null 2>&1
fi
show_progress "Firewall: port 53 & 3128 dibuka"

# =============================================
# STEP 3: SETUP CRON JOB
# =============================================
echo ""
echo -e "${BLUE}${BOLD}━━━ [3/4] CRON JOB UPDATE ADBLOCK ━━━${NC}"

init_progress 2

CRON_SCHEDULE="0 3 * * *"  # Setiap jam 3 pagi

# Hapus cron lama jika ada
crontab -l 2>/dev/null | grep -v "update-adblock.sh" | crontab - 2>/dev/null || true

# Tambah cron baru
(crontab -l 2>/dev/null; echo "$CRON_SCHEDULE root $ADBLOCK_UPDATER") | crontab - 2>/dev/null || true
show_progress "Cron job terpasang (update setiap jam 3 pagi)"

# Jalankan update-adblock.sh via cron path
echo -e "  ${DIM}Next update :${NC} setiap hari jam 03:00"
show_progress "Selesai"

# =============================================
# STEP 4: VERIFICATION
# =============================================
echo ""
echo -e "${BLUE}${BOLD}━━━ [4/4] VERIFICATION ━━━${NC}"

init_progress 3

sleep 1

# Cek dnsmasq
DNSMASQ_OK=false
if systemctl is-active --quiet dnsmasq 2>/dev/null; then
    DNSMASQ_OK=true
fi
show_progress "Cek dnsmasq: $([ "$DNSMASQ_OK" = true ] && echo "${GREEN}✓ Running${NC}" || echo "${RED}✗ Error${NC}")"

# Cek squid
SQUID_OK=false
if systemctl is-active --quiet squid 2>/dev/null; then
    SQUID_OK=true
fi
show_progress "Cek Squid: $([ "$SQUID_OK" = true ] && echo "${GREEN}✓ Running${NC}" || echo "${RED}✗ Error${NC}")"

# Cek jumlah domain terblokir
if [ -f "$ADBLOCK_LIST" ]; then
    BLOCK_COUNT=$(grep -c "^0\.0\.0\.0\|^127\.0\.0\.1" "$ADBLOCK_LIST" 2>/dev/null || echo 0)
else
    BLOCK_COUNT=0
fi
show_progress "Domain terblokir: ${YELLOW}$BLOCK_COUNT${NC}"

echo ""

# === FINAL OUTPUT ===
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}       INSTALASI BERHASIL!${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}📡 AdBlocker (DNS via dnsmasq)${NC}"
echo -e "    ${DIM}DNS Server  :${NC} ${CYAN}$IP_ADDR${NC} (port 53)"
echo -e "    ${DIM}Domain blok :${NC} ${YELLOW}$BLOCK_COUNT${NC} domain iklan/malware"
echo ""
echo -e "  ${BOLD}⚡ Caching Proxy (Squid)${NC}"
echo -e "    ${DIM}Proxy       :${NC} ${CYAN}http://$IP_ADDR:3128${NC}"
echo ""
echo -e "  ${BOLD}📋 Cara Pengaturan di Perangkat Lain:${NC}"
echo ""
echo -e "  ${YELLOW}A. Set DNS (untuk adblock):${NC}"
echo -e "     Settings > Network > DNS Manual > ${CYAN}$IP_ADDR${NC}"
echo ""
echo -e "  ${YELLOW}B. Set Proxy (untuk caching):${NC}"
echo -e "     Settings > Proxy > ON"
echo -e "     Address: ${CYAN}$IP_ADDR${NC}  Port: ${CYAN}3128${NC}"
echo ""
echo -e "  ${YELLOW}C. Atau keduanya — dapatkan adblock + cache!${NC}"
echo ""
echo -e "  ${BOLD}🔧 Perintah Berguna:${NC}"
echo -e "    ${DIM}Cek dnsmasq  :${NC} sudo systemctl status dnsmasq"
echo -e "    ${DIM}Cek Squid    :${NC} sudo systemctl status squid"
echo -e "    ${DIM}Cek blokir   :${NC} sudo grep -c '^0.0.0.0' $ADBLOCK_LIST"
echo -e "    ${DIM}Update adblk :${NC} sudo bash $ADBLOCK_UPDATER"
echo -e "    ${DIM}Log update   :${NC} tail -f $ADBLOCK_LOG"
echo -e "    ${DIM}Test adblock :${NC} nslookup doubleclick.net $IP_ADDR"
echo -e "    ${DIM}Test proxy   :${NC} curl -I --proxy http://$IP_ADDR:3128 https://google.com"
echo ""

if [ "$SQUID_OK" = false ] || [ "$DNSMASQ_OK" = false ]; then
    echo -e "${RED}${BOLD}⚠ Ada service yang gagal. Cek log di atas.${NC}"
    echo -e "  ${DIM}Jalankan:${NC} sudo journalctl -u dnsmasq --no-pager -n 20"
    echo -e "  ${DIM}Jalankan:${NC} sudo journalctl -u squid --no-pager -n 20"
    exit 1
fi
