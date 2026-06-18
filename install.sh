#!/bin/bash
# AdBlocker + Squid Cache Proxy — Installer Menu
# Untuk X96Mini / B860H v1 (Armbian)
# Usage: sudo bash install.sh

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

[ "$EUID" -ne 0 ] && { echo -e "${RED}${BOLD}[!] sudo bash $0${NC}"; exit 1; }

# === VARIABEL ===
ADBLOCK_DIR="/etc/adblock"
ADBLOCK_LIST="$ADBLOCK_DIR/blocked.hosts"
ADBLOCK_LOG="/var/log/adblock-update.log"
SQUID_CONF="/etc/squid/squid.conf"
DNSMASQ_CONF="/etc/dnsmasq.conf"
ADBLOCK_UPDATER="/usr/local/bin/update-adblock.sh"

# === FUNGSI UTILITAS ===
banner() {
    clear
    echo ""
    echo -e "  ${CYAN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}  ${BOLD}${MAGENTA}░▀▐▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▌▀░${NC}  ${BOLD}${YELLOW}ADBLOCK + SQUID${NC}      ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}  ${BOLD}${MAGENTA}▄█▓▒░ADBLOCK░▒▓█▄${NC}     ${BOLD}${YELLOW}Installer Menu${NC}       ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}  ${BOLD}${MAGENTA}▀▐▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▌▀${NC}  ${BOLD}${YELLOW}for Armbian${NC}        ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚═══════════════════════════════════════════╝${NC}"
    echo ""
}

sysinfo() {
    echo -e "${BLUE}${BOLD}━━━ SYSTEM ━━━${NC}"
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
    echo -e "  ${DIM}IP  :${NC} ${GREEN}$IP_ADDR${NC}"
    echo -e "  ${DIM}LAN :${NC} $SUBNET"
    echo ""
}

menu() {
    echo -e "${BLUE}${BOLD}━━━ MENU ━━━${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Install ${BOLD}Squid${NC} (cache proxy)"
    echo -e "  ${CYAN}[2]${NC} Install ${BOLD}AdBlock${NC} (dnsmasq)"
    echo -e "  ${CYAN}[3]${NC} Install ${BOLD}Squid + AdBlock${NC} (lengkap)"
    echo -e "  ${CYAN}[4]${NC} ${RED}Hapus${NC} Squid + AdBlock"
    echo -e "  ${CYAN}[5]${NC} ${YELLOW}Optimasi${NC} sesuai perangkat"
    echo -e "  ${CYAN}[6]${NC} ${DIM}Bersihkan${NC} file & paket tidak dipakai"
    echo ""
    echo -e "  ${CYAN}[0]${NC} Keluar"
    echo ""
    echo -ne "${BOLD}Pilih [0-6]:${NC} "
    read -r CHOICE
    echo ""
    case "$CHOICE" in
        1) install_squid ;;
        2) install_adblock ;;
        3) install_full ;;
        4) uninstall_all ;;
        5) optimize_device ;;
        6) cleanup_system ;;
        0) echo -e "${DIM}Keluar.${NC}"; exit 0 ;;
        *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1; menu ;;
    esac
}

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

install_pkg() {
    local pkg=$1
    echo -ne "  ${DIM}Install ${CYAN}$pkg${NC}${DIM}...${NC} "
    if dpkg -s "$pkg" >/dev/null 2>&1; then echo -e "${GREEN}✓${NC}"; return 0; fi
    local logfile
    logfile=$(mktemp)
    apt install -y "$pkg" > "$logfile" 2>&1; local ret=$?
    if [ $ret -ne 0 ]; then
        echo ""
        grep -E '(^E:|^W:|tidak dapat|unable|could not)' "$logfile" | head -3 | while read -r line; do
            echo -e "  ${RED}${line}${NC}"
        done
        rm -f "$logfile"
        return 1
    fi
    rm -f "$logfile"
    echo -e "${GREEN}✓${NC}"
    return 0
}

detect_network() {
    IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
    IP_ADDR=$(ip addr show "$IFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    SUBNET=$(ip route 2>/dev/null | grep -E "link src $IP_ADDR|$IFACE.*proto kernel" | grep -oP '\d+\.\d+\.\d+\.\d+/\d+' | head -1)
    [ -z "$SUBNET" ] && SUBNET=$(ip route 2>/dev/null | grep "$IFACE" | grep -oP '\d+\.\d+\.\d+\.\d+/\d+' | head -1)
    [ -z "$SUBNET" ] && SUBNET="192.168.1.0/24"
}

subnet_covered() {
    case "$1" in
        10.*) return 0 ;; 192.168.*) return 0 ;;
        172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 0 ;;
        100.6[4-9].*|100.1[0-1][0-9].*|100.12[0-7].*) return 0 ;;
        169.254.*) return 0 ;; fc*|fd*) return 0 ;; fe80:*) return 0 ;;
    esac
    return 1
}

ufw_allow() {
    command -v ufw &> /dev/null && ufw allow "$1" comment "$2" > /dev/null 2>&1 || true
}

ufw_deny() {
    command -v ufw &> /dev/null && ufw delete allow "$1" > /dev/null 2>&1 || true
}

apt_quick_update() {
    echo -e "  ${DIM}Update apt...${NC}"
    run_spinner "Memperbarui package list" apt update -qq
}

# Gunakan local dnsmasq sebagai DNS setelah service berjalan
dns_use_local() {
    chattr -i /etc/resolv.conf 2>/dev/null || true
    cat > /etc/resolv.conf << 'LOCAL'
nameserver 127.0.0.1
nameserver 1.1.1.1
LOCAL
    chattr +i /etc/resolv.conf 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} DNS → local dnsmasq (127.0.0.1)"
}

# Lepas proteksi resolv.conf (dipanggil saat uninstall)
dns_unprotect() {
    chattr -i /etc/resolv.conf 2>/dev/null || true
    cat > /etc/resolv.conf << 'PUBLIC'
nameserver 1.1.1.1
nameserver 8.8.8.8
PUBLIC
}

# =============================================
# CONFLICT DETECTION
# =============================================
detect_and_disable_conflicts() {
    local filter="$1"  # "dns", "proxy", or "all"
    local conflicts=()

    if [ "$filter" = "dns" ] || [ "$filter" = "all" ]; then
        for svc in systemd-resolved pihole-FTL adguardhome bind9 unbound stubby dnscrypt-proxy dnsmasq; do
            systemctl is-active --quiet "$svc" 2>/dev/null && conflicts+=("$svc (running)")
            systemctl is-enabled --quiet "$svc" 2>/dev/null && conflicts+=("$svc (enabled)")
        done
        command -v pihole &> /dev/null && ! systemctl is-enabled --quiet pihole-FTL 2>/dev/null && conflicts+=("pihole (binary)")
        [ -f /opt/AdGuardHome/AdGuardHome ] && ! systemctl is-enabled --quiet adguardhome 2>/dev/null && conflicts+=("AdGuard Home (binary)")
    fi
    if [ "$filter" = "proxy" ] || [ "$filter" = "all" ]; then
        for svc in privoxy tinyproxy haproxy squid; do
            systemctl is-active --quiet "$svc" 2>/dev/null && conflicts+=("$svc (running)")
            systemctl is-enabled --quiet "$svc" 2>/dev/null && conflicts+=("$svc (enabled)")
        done
    fi

    if [ ${#conflicts[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} Tidak ada konflik"
        return 0
    fi

    echo -e "  ${YELLOW}${BOLD}⚠ Konflik ditemukan:${NC}"
    for c in "${conflicts[@]}"; do echo -e "    ${RED}◈${NC} $c"; done
    echo ""
    echo -e "  ${YELLOW}Akan dinonaktifkan (backup config otomatis).${NC}"
    echo -ne "  ${BOLD}Lanjutkan? [Y/n]:${NC} "
    read -r CONFIRM
    [[ "$CONFIRM" =~ ^[Nn] ]] && { echo -e "  ${RED}Batal.${NC}"; return 1; }

    # DNS fallback: jika systemd-resolved akan dimatikan, set resolv.conf dulu
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        echo -e "  ${YELLOW}⚠ systemd-resolved akan dinonaktifkan. Memasang DNS fallback...${NC}"
        rm -f /etc/resolv.conf
        cat > /etc/resolv.conf << 'RESOLV'
nameserver 1.1.1.1
nameserver 8.8.8.8
RESOLV
        # Lindungi dari overwrite
        chattr -i /etc/resolv.conf 2>/dev/null || true
        chattr +i /etc/resolv.conf 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} DNS fallback: 1.1.1.1, 8.8.8.8"
    fi

    local svc_list=""
    [ "$filter" = "dns" ] || [ "$filter" = "all" ] && svc_list="$svc_list systemd-resolved pihole-FTL adguardhome bind9 unbound stubby dnscrypt-proxy dnsmasq"
    [ "$filter" = "proxy" ] || [ "$filter" = "all" ] && svc_list="$svc_list privoxy tinyproxy haproxy squid"

    for svc in $svc_list; do
        systemctl is-active --quiet "$svc" 2>/dev/null || continue
        case "$svc" in
            dnsmasq) [ -f /etc/dnsmasq.conf ] && cp /etc/dnsmasq.conf "/etc/dnsmasq.conf.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null ;;
            squid)   [ -f /etc/squid/squid.conf ] && cp /etc/squid/squid.conf "/etc/squid/squid.conf.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null ;;
        esac
        systemctl stop "$svc" 2>/dev/null || true
        systemctl is-active --quiet "$svc" 2>/dev/null && { pkill -9 -x "$svc" 2>/dev/null || true; sleep 1; }
        systemctl disable "$svc" 2>/dev/null || true
    done
    echo -e "  ${GREEN}✓${NC} Konflik dibersihkan"
    return 0
}

# =============================================
# INSTALL SQUID
# =============================================
install_squid() {
    echo -e "${BLUE}${BOLD}━━━ INSTALL SQUID ━━━${NC}"
    detect_network
    apt_quick_update
    detect_and_disable_conflicts "proxy" || return

    init_progress 7

    install_pkg squid || return
    show_progress "Squid terinstall"

    [ -f "$SQUID_CONF" ] && cp "$SQUID_CONF" "${SQUID_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    show_progress "Backup config"

    cat > "$SQUID_CONF" << CONF
# Squid Cache Config
# LAN: $SUBNET | IP: $IP_ADDR

acl localnet src 0.0.0.1-0.255.255.255
acl localnet src 10.0.0.0/8
acl localnet src 100.64.0.0/10
acl localnet src 169.254.0.0/16
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl localnet src fc00::/7
acl localnet src fe80::/10
CONF
    ! subnet_covered "$SUBNET" && echo "acl localnet src $SUBNET" >> "$SQUID_CONF"

    cat >> "$SQUID_CONF" << CONF
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
http_port 3128
cache_mem 256 MB
maximum_object_size_in_memory 512 KB
minimum_object_size 0 KB
maximum_object_size 64 MB
cache_dir ufs /var/spool/squid 2048 16 256
dns_nameservers 1.1.1.1 8.8.8.8
memory_replacement_policy heap GDSF
cache_replacement_policy heap LFUDA
access_log daemon:/var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
coredump_dir /var/spool/squid
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320
CONF
    show_progress "Config ditulis"

    squid -k parse 2>/dev/null | grep -q "unrecognized.*dns_order" && sed -i '/^dns_order/d' "$SQUID_CONF" 2>/dev/null || true
    mkdir -p /var/log/squid && chown proxy:proxy /var/log/squid 2>/dev/null || true
    squid -z > /dev/null 2>&1 || true
    show_progress "Cache siap"

    systemctl restart squid 2>/dev/null || systemctl start squid 2>/dev/null || true
    systemctl enable squid 2>/dev/null || true
    show_progress "Service start"

    ufw_allow 3128/tcp "Squid Proxy"
    show_progress "Firewall OK"

    if systemctl is-active --quiet squid 2>/dev/null; then
        echo ""
        echo -e "${GREEN}${BOLD}✓ Squid berjalan di http://$IP_ADDR:3128${NC}"
        echo ""
    else
        echo -e "${RED}✗ Squid gagal start. Cek: sudo journalctl -u squid --no-pager -n 30${NC}"
    fi
    echo -e "${DIM}Tekan Enter untuk kembali ke menu...${NC}"; read -r
    banner; sysinfo; menu
}

# =============================================
# INSTALL ADBLOCK
# =============================================
install_adblock() {
    echo -e "${BLUE}${BOLD}━━━ INSTALL ADBLOCK (dnsmasq) ━━━${NC}"
    detect_network
    apt_quick_update
    detect_and_disable_conflicts "dns" || return

    init_progress 7

    install_pkg dnsmasq || return
    show_progress "dnsmasq terinstall"

    mkdir -p "$ADBLOCK_DIR"
    show_progress "Direktori adblock"

    [ -f "$DNSMASQ_CONF" ] && cp "$DNSMASQ_CONF" "${DNSMASQ_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    mkdir -p /etc/dnsmasq.d

    cat > "$DNSMASQ_CONF" << EOF
interface=$IFACE
bind-interfaces
domain-needed
bogus-priv
no-resolv
server=1.1.1.1
server=8.8.8.8
cache-size=10000
addn-hosts=$ADBLOCK_LIST
EOF
    show_progress "Config dnsmasq"

    # Copy updater
    SRC_UPDATE="$(dirname "$0")/update-adblock.sh"
    if [ -f "$SRC_UPDATE" ]; then
        cp "$SRC_UPDATE" "$ADBLOCK_UPDATER" && chmod +x "$ADBLOCK_UPDATER"
    elif [ ! -f "$ADBLOCK_UPDATER" ]; then
        curl -sSL -o "$ADBLOCK_UPDATER" "https://raw.githubusercontent.com/budijoi/adblock-n-squid/main/update-adblock.sh" 2>/dev/null && chmod +x "$ADBLOCK_UPDATER" || true
    fi
    show_progress "Updater siap"

    bash "$ADBLOCK_UPDATER"
    show_progress "Adblock lists"

    systemctl restart dnsmasq 2>/dev/null || systemctl start dnsmasq 2>/dev/null
    systemctl enable dnsmasq > /dev/null 2>&1 || true
    show_progress "Service start"

    if systemctl is-active --quiet dnsmasq 2>/dev/null; then
        dns_use_local
    fi

    ufw_allow 53/tcp "dnsmasq DNS"
    ufw_allow 53/udp "dnsmasq DNS"
    show_progress "Firewall OK"

    # Cron
    CRON_JOB="0 3 * * * $ADBLOCK_UPDATER"
    (crontab -l 2>/dev/null | grep -v "update-adblock.sh"; echo "$CRON_JOB") | crontab - 2>/dev/null || true
    show_progress "Cron job"

    if systemctl is-active --quiet dnsmasq 2>/dev/null; then
        local count=0
        [ -f "$ADBLOCK_LIST" ] && count=$(grep -c "^0\.0\.0\.0" "$ADBLOCK_LIST" 2>/dev/null || echo 0)
        echo ""
        echo -e "${GREEN}${BOLD}✓ AdBlock berjalan — DNS: $IP_ADDR (port 53)${NC}"
        echo -e "  ${DIM}Domain diblokir:${NC} ${YELLOW}$count${NC}"
        echo ""
    else
        echo -e "${RED}✗ dnsmasq gagal start. Cek: sudo journalctl -u dnsmasq --no-pager -n 30${NC}"
    fi
    echo -e "${DIM}Tekan Enter untuk kembali ke menu...${NC}"; read -r
    banner; sysinfo; menu
}

# =============================================
# INSTALL FULL (SQUID + ADBLOCK)
# =============================================
install_full() {
    echo -e "${BLUE}${BOLD}━━━ INSTALL SQUID + ADBLOCK ━━━${NC}"
    detect_network
    apt_quick_update
    detect_and_disable_conflicts "all" || return

    init_progress 12

    install_pkg squid || return
    show_progress "Squid terinstall"

    install_pkg dnsmasq || return
    show_progress "dnsmasq terinstall"

    mkdir -p "$ADBLOCK_DIR"
    show_progress "Direktori adblock"

    # Config dnsmasq
    [ -f "$DNSMASQ_CONF" ] && cp "$DNSMASQ_CONF" "${DNSMASQ_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    mkdir -p /etc/dnsmasq.d
    cat > "$DNSMASQ_CONF" << EOF
interface=$IFACE
bind-interfaces
domain-needed
bogus-priv
no-resolv
server=1.1.1.1
server=8.8.8.8
cache-size=10000
addn-hosts=$ADBLOCK_LIST
EOF
    show_progress "Config dnsmasq"

    # Copy updater
    SRC_UPDATE="$(dirname "$0")/update-adblock.sh"
    if [ -f "$SRC_UPDATE" ]; then
        cp "$SRC_UPDATE" "$ADBLOCK_UPDATER" && chmod +x "$ADBLOCK_UPDATER"
    elif [ ! -f "$ADBLOCK_UPDATER" ]; then
        curl -sSL -o "$ADBLOCK_UPDATER" "https://raw.githubusercontent.com/budijoi/adblock-n-squid/main/update-adblock.sh" 2>/dev/null && chmod +x "$ADBLOCK_UPDATER" || true
    fi

    bash "$ADBLOCK_UPDATER"
    show_progress "Adblock lists"

    systemctl restart dnsmasq 2>/dev/null || systemctl start dnsmasq 2>/dev/null
    systemctl enable dnsmasq > /dev/null 2>&1 || true
    show_progress "dnsmasq start"

    if systemctl is-active --quiet dnsmasq 2>/dev/null; then
        dns_use_local
    fi

    # Config Squid
    [ -f "$SQUID_CONF" ] && cp "$SQUID_CONF" "${SQUID_CONF}.bak.$(date +%Y%m%d%H%M%S)"

    cat > "$SQUID_CONF" << CONF
# Squid Cache + AdBlock Config
# LAN: $SUBNET | IP: $IP_ADDR

acl localnet src 0.0.0.1-0.255.255.255
acl localnet src 10.0.0.0/8
acl localnet src 100.64.0.0/10
acl localnet src 169.254.0.0/16
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl localnet src fc00::/7
acl localnet src fe80::/10
CONF
    ! subnet_covered "$SUBNET" && echo "acl localnet src $SUBNET" >> "$SQUID_CONF"

    cat >> "$SQUID_CONF" << CONF
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
http_port 3128
cache_mem 256 MB
maximum_object_size_in_memory 512 KB
minimum_object_size 0 KB
maximum_object_size 64 MB
cache_dir ufs /var/spool/squid 2048 16 256
dns_nameservers 127.0.0.1
memory_replacement_policy heap GDSF
cache_replacement_policy heap LFUDA
access_log daemon:/var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
coredump_dir /var/spool/squid
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320
CONF
    show_progress "Config Squid"

    squid -k parse 2>/dev/null | grep -q "unrecognized.*dns_order" && sed -i '/^dns_order/d' "$SQUID_CONF" 2>/dev/null || true
    mkdir -p /var/log/squid && chown proxy:proxy /var/log/squid 2>/dev/null || true
    squid -z > /dev/null 2>&1 || true
    show_progress "Cache siap"

    systemctl restart squid 2>/dev/null || systemctl start squid 2>/dev/null || true
    systemctl enable squid 2>/dev/null || true
    show_progress "Squid start"

    ufw_allow 53/tcp "dnsmasq DNS"
    ufw_allow 53/udp "dnsmasq DNS"
    ufw_allow 3128/tcp "Squid Proxy"
    show_progress "Firewall OK"

    CRON_JOB="0 3 * * * $ADBLOCK_UPDATER"
    (crontab -l 2>/dev/null | grep -v "update-adblock.sh"; echo "$CRON_JOB") | crontab - 2>/dev/null || true
    show_progress "Cron job"

    # Final
    DNSMASQ_OK=false; SQUID_OK=false
    systemctl is-active --quiet dnsmasq 2>/dev/null && DNSMASQ_OK=true
    systemctl is-active --quiet squid 2>/dev/null && SQUID_OK=true
    local count=0
    [ -f "$ADBLOCK_LIST" ] && count=$(grep -c "^0\.0\.0\.0" "$ADBLOCK_LIST" 2>/dev/null || echo 0)

    echo ""
    echo -e "${GREEN}${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}       INSTALASI BERHASIL!${NC}"
    echo -e "${GREEN}${BOLD}══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}AdBlocker${NC}   DNS: ${CYAN}$IP_ADDR${NC} (port 53)"
    echo -e "  ${BOLD}Squid${NC}       ${CYAN}http://$IP_ADDR:3128${NC}"
    echo -e "  ${BOLD}Blokir${NC}      ${YELLOW}$count${NC} domain iklan/malware"
    echo ""
    echo -e "  ${YELLOW}A. Set DNS${NC}  ${DIM}→ adblock${NC}"
    echo -e "  ${YELLOW}B. Set Proxy${NC} ${DIM}→ cache${NC}"
    echo -e "  ${YELLOW}C. Keduanya${NC}  ${DIM}→ maksimal${NC}"
    echo ""

    if [ "$SQUID_OK" = false ] || [ "$DNSMASQ_OK" = false ]; then
        echo -e "${RED}⚠ Ada service gagal:${NC}"
        [ "$DNSMASQ_OK" = false ] && echo -e "  ${RED}• dnsmasq${NC} → sudo journalctl -u dnsmasq --no-pager -n 30"
        [ "$SQUID_OK" = false ] && echo -e "  ${RED}• squid${NC}   → sudo journalctl -u squid --no-pager -n 30"
    fi
    echo -e "${DIM}Tekan Enter untuk kembali ke menu...${NC}"; read -r
    banner; sysinfo; menu
}

# =============================================
# UNINSTALL
# =============================================
uninstall_all() {
    echo -e "${BLUE}${BOLD}━━━ HAPUS SQUID + ADBLOCK ━━━${NC}"
    echo ""
    echo -e "  ${RED}${BOLD}Akan dihapus:${NC}"
    echo -e "    • Squid (package + config + cache)"
    echo -e "    • dnsmasq (package + config)"
    echo -e "    • Adblock lists & updater"
    echo -e "    • Cron job update adblock"
    echo -e "    • Firewall rules (port 53, 3128)"
    echo ""
    echo -ne "${BOLD}Lanjutkan? [y/N]:${NC} "
    read -r CONFIRM
    [[ ! "$CONFIRM" =~ ^[Yy] ]] && { echo -e "${DIM}Dibatalkan.${NC}"; sleep 1; banner; sysinfo; menu; return; }

    # Stop services
    echo -e "  ${DIM}Menghentikan service...${NC}"
    systemctl stop squid 2>/dev/null || true
    systemctl stop dnsmasq 2>/dev/null || true
    pkill -9 squid 2>/dev/null || true
    pkill -9 dnsmasq 2>/dev/null || true
    sleep 1

    # Remove packages
    echo -e "  ${DIM}Menghapus paket...${NC}"
    apt remove --purge -y squid dnsmasq > /dev/null 2>&1 || true
    apt autoremove -y > /dev/null 2>&1 || true

    # Remove config & data
    echo -e "  ${DIM}Menghapus config & data...${NC}"
    rm -rf /etc/squid /var/spool/squid /var/log/squid
    rm -rf /etc/dnsmasq* /var/log/dnsmasq*
    rm -rf "$ADBLOCK_DIR" "$ADBLOCK_UPDATER" "$ADBLOCK_LOG"
    rm -f /etc/dnsmasq.d/adblock.conf

    # Remove cron
    crontab -l 2>/dev/null | grep -v "update-adblock.sh" | crontab - 2>/dev/null || true

    # Remove firewall rules
    ufw_deny 53/tcp
    ufw_deny 53/udp
    ufw_deny 3128/tcp

    # Kembalikan DNS ke public
    dns_unprotect

    echo ""
    echo -e "${GREEN}${BOLD}✓ Squid + AdBlock berhasil dihapus.${NC}"
    echo -e "  ${DIM}Backup config (jika ada): /etc/*.bak.*${NC}"
    echo ""
    echo -e "${DIM}Tekan Enter untuk kembali ke menu...${NC}"; read -r
    banner; sysinfo; menu
}

# =============================================
# OPTIMASI
# =============================================
optimize_device() {
    echo -e "${BLUE}${BOLD}━━━ OPTIMASI PERANGKAT ━━━${NC}"
    echo ""
    echo -e "  ${DIM}Penerapan tuning untuk STB (RAM 512MB-2GB, flash storage)${NC}"
    echo ""

    # Backup sysctl
    cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true

    # 1. vm.swappiness — kurangi swap (flash storage)
    echo -e "  ${BOLD}1.${NC} vm.swappiness = 10"
    sysctl -w vm.swappiness=10 > /dev/null 2>&1
    grep -q "vm.swappiness" /etc/sysctl.conf && sed -i 's/vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf || echo "vm.swappiness=10" >> /etc/sysctl.conf

    # 2. vfs cache pressure
    echo -e "  ${BOLD}2.${NC} vm.vfs_cache_pressure = 50"
    sysctl -w vm.vfs_cache_pressure=50 > /dev/null 2>&1
    grep -q "vm.vfs_cache_pressure" /etc/sysctl.conf && sed -i 's/vm.vfs_cache_pressure=.*/vm.vfs_cache_pressure=50/' /etc/sysctl.conf || echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf

    # 3. TCP BBR
    echo -e "  ${BOLD}3.${NC} TCP BBR (congestion control)"
    if grep -q "tcp_congestion_control" /etc/sysctl.conf 2>/dev/null; then
        sed -i 's/net.core.default_qdisc=.*/net.core.default_qdisc=fq/' /etc/sysctl.conf
        sed -i 's/net.ipv4.tcp_congestion_control=.*/net.ipv4.tcp_congestion_control=bbr/' /etc/sysctl.conf
    else
        cat >> /etc/sysctl.conf << EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    fi
    sysctl -p > /dev/null 2>&1 || true

    # 4. Disable services
    echo -e "  ${BOLD}4.${NC} Nonaktifkan service tidak perlu..."
    for svc in bluetooth avahi-daemon cups whoopsie ModemManager; do
        if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            systemctl stop "$svc" 2>/dev/null || true
            systemctl disable "$svc" 2>/dev/null || true
            echo -e "     ${DIM}→ $svc dinonaktifkan${NC}"
        fi
    done

    # 5. noatime untuk mengurangi write
    echo -e "  ${BOLD}5.${NC} Set noatime pada filesystem..."
    if mount | grep " / " | grep -v noatime > /dev/null 2>&1; then
        local root_dev
        root_dev=$(findmnt -n -o SOURCE /)
        if [ -n "$root_dev" ]; then
            mount -o remount,noatime "$root_dev" / 2>/dev/null && echo -e "     ${GREEN}✓${NC} noatime aktif"
        fi
    else
        echo -e "     ${GREEN}✓${NC} sudah noatime"
    fi

    # 6. Kernel printk (kurangi log console)
    echo -e "  ${BOLD}6.${NC} Kernel printk tuning"
    sysctl -w kernel.printk="3 3 3 3" > /dev/null 2>&1
    grep -q "kernel.printk" /etc/sysctl.conf && sed -i 's/kernel.printk=.*/kernel.printk=3 3 3 3/' /etc/sysctl.conf || echo "kernel.printk=3 3 3 3" >> /etc/sysctl.conf

    echo ""
    echo -e "${GREEN}${BOLD}✓ Optimasi selesai!${NC}"
    echo -e "  ${DIM}Beberapa perubahan butuh reboot agar efektif.${NC}"
    echo -ne "  ${BOLD}Reboot sekarang? [y/N]:${NC} "
    read -r REBOOT
    [[ "$REBOOT" =~ ^[Yy] ]] && { echo -e "  ${YELLOW}Reboot...${NC}"; reboot; }
    echo -e "${DIM}Tekan Enter untuk kembali ke menu...${NC}"; read -r
    banner; sysinfo; menu
}

# =============================================
# CLEANUP
# =============================================
cleanup_system() {
    echo -e "${BLUE}${BOLD}━━━ PEMBERSIHAN SISTEM ━━━${NC}"
    echo ""

    echo -e "  ${BOLD}1.${NC} Paket tidak dipakai (apt autoremove)..."
    apt autoremove -y > /dev/null 2>&1 && echo -e "     ${GREEN}✓${NC}"

    echo -e "  ${BOLD}2.${NC} Cache apt (apt autoclean)..."
    apt autoclean > /dev/null 2>&1 && echo -e "     ${GREEN}✓${NC}"
    apt clean > /dev/null 2>&1 && echo -e "     ${GREEN}✓${NC}"

    echo -e "  ${BOLD}3.${NC} Journal log (max 100MB)..."
    journalctl --vacuum-size=100M > /dev/null 2>&1 && echo -e "     ${GREEN}✓${NC}"

    echo -e "  ${BOLD}4.${NC} Temporary files..."
    rm -rf /tmp/* /var/tmp/* 2>/dev/null
    echo -e "     ${GREEN}✓${NC}"

    echo -e "  ${BOLD}5.${NC} Package cache..."

    # Bersihkan .deb di /var/cache/apt
    du -sh /var/cache/apt/archives/ 2>/dev/null
    apt clean > /dev/null 2>&1

    # Tampilkan ringkasan
    local freed
    freed=$(df -h / | awk 'NR==2 {print $4}')
    echo ""
    echo -e "${GREEN}${BOLD}✓ Selesai!${NC} Disk tersedia: ${YELLOW}$freed${NC}"
    echo ""
    echo -e "${DIM}Tekan Enter untuk kembali ke menu...${NC}"; read -r
    banner; sysinfo; menu
}

# =============================================
# MAIN
# =============================================
banner
sysinfo
menu
