# AdBlocker + Squid Cache Proxy — STB Box (Armbian)

Jadikan STB **X96Mini** atau **B860H v1** kamu sebagai **adblocker seluruh jaringan + caching proxy server** — dua fungsi dalam satu perangkat. Cukup dengan RAM 512 MB.

---

## Cara Kerja

Semua request DNS dari perangkat lain akan dicegat oleh **dnsmasq**. Domain iklan/tracker/malware diarahkan ke `0.0.0.0` (blok). Request HTTP/HTTPS bisa dilewatkan ke **Squid** yang menyimpan cache halaman web.

---

## Fitur

- **DNS Adblocking** — blokir 2-3 juta domain iklan/tracker/malware dari 3 sumber terpercaya
- **DNS Caching** — percepat resolusi DNS hingga 10.000 domain
- **Caching Proxy** — cache halaman web hingga 2 GB
- **Auto-update** — adblock list diperbarui otomatis setiap jam 3 pagi
- **Ringan** — hanya butuh ~100 MB RAM untuk dnsmasq + Squid
- **Plug & Play** — set DNS dan/atau proxy di perangkat lain, langsung jalan

---

## Instalasi

### 1. Persyaratan

- STB **X96Mini** atau **B860H v1** sudah terinstall **Armbian** (booting dari SD Card atau eMMC)
- STB terhubung ke **LAN** — gunakan **IP static**
- Akses **root** via SSH
- Koneksi internet

### 2. Set IP Static

```bash
sudo nmtui
```

Atau edit langsung:

```bash
sudo nano /etc/network/interfaces
```

Contoh:

```ini
auto eth0
iface eth0 inet static
    address 192.168.1.100
    netmask 255.255.255.0
    gateway 192.168.1.1
    dns-nameservers 1.1.1.1 8.8.8.8
```

### 3. Download & Jalankan Installer

SSH ke STB, download & jalankan langsung:

```bash
ssh root@192.168.1.100

# Clone repo atau download file
apt install -y git
git clone https://github.com/budijoi/adblock-n-squid.git /tmp/adblock-squid
sudo bash /tmp/adblock-squid/install.sh
```

Atau pakai wget:

```bash
wget -O /tmp/install.sh https://raw.githubusercontent.com/budijoi/adblock-n-squid/main/install.sh
wget -O /tmp/update-adblock.sh https://raw.githubusercontent.com/budijoi/adblock-n-squid/main/update-adblock.sh
sudo bash /tmp/install.sh
```

Installer akan:
1. Mendeteksi IP dan subnet LAN
2. Install **dnsmasq** + konfigurasi adblock
3. Install **Squid** dengan tuning cache
4. Set Squid pakai dnsmasq sebagai DNS (adblock terbawa otomatis)
5. Download adblock lists dari 3 sumber
6. Buka firewall (port 53 DNS, port 3128 proxy)
7. Pasang cron job update harian
8. Verifikasi service berjalan

---

## Setting Perangkat Lain

### Opsi A — Hanya AdBlocker (set DNS)

**Windows:**
1. Settings > Network & Internet > Change adapter options
2. Klik kanan koneksi > Properties
3. Pilih **Internet Protocol Version 4 (TCP/IPv4)** > Properties
4. **Use the following DNS server addresses**
5. Preferred DNS: `192.168.1.100`, Alternate: `1.1.1.1`

PowerShell (admin):
```powershell
netsh interface ip set dns "Ethernet" static 192.168.1.100
```

**Android:**
1. Settings > Wi-Fi > tap & tahan jaringan > Modify network
2. Advanced options > IP settings > Static
3. DNS 1: `192.168.1.100`

**iPhone/iPad:**
1. Settings > Wi-Fi > tap icon ⓘ
2. Configure DNS > Manual
3. Tambah `192.168.1.100`

### Opsi B — Hanya Cache Proxy (set proxy)

**Windows:**
1. Settings > Network & Internet > Proxy
2. Use a proxy server → ON
3. Address: `192.168.1.100`, Port: `3128`
4. Centang **Bypass proxy for local addresses**

PowerShell (admin):
```powershell
netsh winhttp set proxy 192.168.1.100:3128
```

**Chrome / Edge / Brave:**
- Buka `chrome://settings/?search=proxy`
- Klik **Open your computer's proxy settings**

**Android:**
1. Settings > Wi-Fi > Modify network > Advanced options
2. Proxy > Manual
3. Hostname: `192.168.1.100`, Port: `3128`

### Opsi C — Keduanya (DNS + Proxy)

Setting DNS seperti Opsi A **dan** proxy seperti Opsi B. Iklan hilang + browsing cepat.

---

## Verifikasi

### Tes AdBlocker

```bash
# Dari perangkat lain — domain iklan harus balik 0.0.0.0
nslookup doubleclick.net 192.168.1.100

# Domain normal harus balik IP asli
nslookup google.com 192.168.1.100
```

### Tes Cache Proxy

```bash
curl -I --proxy http://192.168.1.100:3128 https://google.com
```

Response `200` atau `301` berarti proxy berfungsi.

Cek header `X-Cache`:
```bash
# Pertama: MISS
curl -I --proxy http://192.168.1.100:3128 https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css 2>&1 | grep -i x-cache

# Kedua: HIT (sudah di-cache)
curl -I --proxy http://192.168.1.100:3128 https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css 2>&1 | grep -i x-cache
```

### Cek Status di STB

```bash
# Status dnsmasq
sudo systemctl status dnsmasq

# Status Squid
sudo systemctl status squid

# Jumlah domain diblokir
sudo grep -c '^0.0.0.0' /etc/adblock/blocked.hosts

# Update manual adblock
sudo bash /usr/local/bin/update-adblock.sh
```

---

## Perintah Berguna

### dnsmasq (AdBlocker)

| Perintah | Fungsi |
|---|---|
| `sudo systemctl status dnsmasq` | Cek status |
| `sudo systemctl restart dnsmasq` | Restart |
| `sudo journalctl -u dnsmasq --no-pager -n 30` | Cek log |
| `sudo grep -c '^0.0.0.0' /etc/adblock/blocked.hosts` | Cek jumlah blokir |
| `sudo bash /path/to/update-adblock.sh` | Update manual adblock |
| `tail -f /var/log/adblock-update.log` | Log update adblock |

### Squid (Cache Proxy)

| Perintah | Fungsi |
|---|---|
| `sudo systemctl status squid` | Cek status |
| `sudo systemctl restart squid` | Restart |
| `sudo tail -f /var/log/squid/access.log` | Log request real-time |
| `sudo tail -f /var/log/squid/cache.log` | Log cache / debugging |
| `sudo squid -k info` | Informasi cache |
| `du -sh /var/spool/squid` | Ukuran cache di disk |

**Hapus semua cache:**
```bash
sudo systemctl stop squid
sudo rm -rf /var/spool/squid/*
sudo squid -z
sudo systemctl start squid
```

---

## Update AdBlock List

Otomatis setiap jam 3 pagi via cron. Manual:
```bash
sudo bash /path/to/update-adblock.sh
```

Sumber blocklist:

| Sumber | Domain | Update |
|---|---|---|
| StevenBlack Unified | adware + malware + tracking | Harian |
| someonewhocares.org | hosts-based blocking | Harian |
| OISD Big | comprehensive domain block | Harian |

---

## Troubleshooting

### AdBlocker

| Masalah | Penyebab | Solusi |
|---|---|---|
| `nslookup` timeout | Port 53 diblokir firewall | `sudo ufw allow 53/tcp && sudo ufw allow 53/udp` |
| DNS tidak merespon | systemd-resolved konflik | `sudo systemctl disable --now systemd-resolved` |
| Iklan masih muncul | Belum ada di blocklist | Update: `sudo bash update-adblock.sh` |
| Address already in use | Port 53 dipakai | `sudo lsof -i :53`, matikan service konflik |

### Cache Proxy

| Masalah | Penyebab | Solusi |
|---|---|---|
| Proxy server refusing connections | Squid tidak jalan | `sudo systemctl restart squid` |
| Web error 503 | DNS gagal | Cek `sudo tail -f /var/log/squid/cache.log` |
| Squid hanya di localhost | Firewall blokir | `sudo ufw allow 3128/tcp` |
| Lambat di awal | Cache kosong | Biarkan, akan cepat setelah beberapa kunjungan |
| BCP 177 violation | IPv6 loopback | Aman diabaikan |
| DNS resolution failure | Squid tidak bisa hubungi DNS | Cek `sudo systemctl status dnsmasq` |

---

## Spesifikasi

| Sumber Daya | Minimal | Rekomendasi |
|---|---|---|
| RAM | 512 MB | 1 GB (X96Mini / B860H v1) |
| Storage | 1 GB free | 4 GB free |
| Network | 100 Mbps | 100/1000 Mbps |
| OS | Armbian kernel 5.x+ | Armbian Focal / Jammy |

---

## Perbandingan

| Fitur | Squid Saja | Squid + AdBlocker |
|---|---|---|
| Caching halaman web | Ya | Ya |
| Blokir iklan & tracker | Tidak | Ya |
| DNS caching | Tidak | Ya (10.000 domain) |
| Beban RAM | ~60 MB | ~100 MB |

---

## File Structure

```
adblock n Squid/
├── install.sh              # All-in-one installer
├── update-adblock.sh       # AdBlock list updater
└── README.md               # Dokumentasi ini
```

---

## Kredit

- [Squid-Cache](http://www.squid-cache.org/)
- [dnsmasq](https://thekelleys.org.uk/dnsmasq/doc.html)
- [StevenBlack/hosts](https://github.com/StevenBlack/hosts)
- [someonewhocares.org](https://someonewhocares.org/)
- [OISD](https://oisd.nl/)

---

## Lisensi

MIT
