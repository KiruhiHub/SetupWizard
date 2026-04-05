#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  ArchInit — Common Library v2
#  Tüm profil betikleri bu dosyayı source eder.
#  set -e KULLANILMAZ — her hata loglanır, kurulum devam eder.
# ═══════════════════════════════════════════════════════════════

# ── Renkler ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Log fonksiyonları (stdout → frontend stream) ──────────────
log_ok()      { echo -e "${GREEN}[OK]${RESET} $*";    echo "[OK] $*"    >> "${LOG_FILE:-/tmp/archinit.log}"; }
log_info()    { echo -e "${CYAN}[>>]${RESET} $*";    echo "[>>] $*"    >> "${LOG_FILE:-/tmp/archinit.log}"; }
log_warn()    { echo -e "${YELLOW}[!!]${RESET} $*";  echo "[!!] $*"    >> "${LOG_FILE:-/tmp/archinit.log}"; }
log_error()   { echo -e "${RED}[ERR]${RESET} $*";   echo "[ERR] $*"   >> "${LOG_FILE:-/tmp/archinit.log}"; }
log_section() { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}\n"; echo "" >> "${LOG_FILE:-/tmp/archinit.log}"; echo "══ $* ══" >> "${LOG_FILE:-/tmp/archinit.log}"; }
log_done()    { echo -e "\n${GREEN}${BOLD}[DONE] $*${RESET}\n"; echo "[DONE] $*" >> "${LOG_FILE:-/tmp/archinit.log}"; }

# ── Kontrol yardımcıları ──────────────────────────────────────
is_installed()      { command -v "$1" &>/dev/null; }
pkg_installed()     { pacman -Qi "$1" &>/dev/null 2>&1; }
flatpak_installed() { flatpak list --app --columns=application 2>/dev/null | grep -qx "$1"; }

# ── sudo önbelleği — tek seferlik şifre, sonra timestamp ──────
# Wails uygulaması başlamadan önce kullanıcıdan sudo alınır.
# Betik boyunca sudo -n ile şifresiz çalışır.
refresh_sudo() {
    if sudo -n true 2>/dev/null; then
        return 0
    fi
    log_warn "Kurulum için sudo gerekiyor. Şifrenizi girin:"
    sudo -v || { log_error "sudo alınamadı, kurulum durduruluyor."; exit 1; }
    # Arka planda her 4 dakikada bir sudo timestamp yenile
    (while true; do sudo -n true; sleep 240; done) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
}

# ── pacman ────────────────────────────────────────────────────
install_pkg() {
    local pkg="$1"
    if pkg_installed "$pkg"; then
        log_warn "$pkg zaten kurulu."
        return 0
    fi
    log_info "pacman: $pkg kuruluyor..."
    if sudo pacman -S --noconfirm --needed "$pkg" >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1; then
        log_ok "$pkg kuruldu."
    else
        log_error "$pkg KURULAMADI (pacman)"
        echo "[FAIL:pacman] $pkg" >> "${LOG_FILE:-/tmp/archinit.log}"
    fi
}

# ── AUR (yay) ─────────────────────────────────────────────────
install_aur() {
    local pkg="$1"
    if ! is_installed yay; then
        log_warn "yay bulunamadı — AUR paketi atlanıyor: $pkg"
        return 1
    fi
    if pkg_installed "$pkg"; then
        log_warn "$pkg zaten kurulu."
        return 0
    fi
    log_info "AUR: $pkg kuruluyor..."
    if yay -S --noconfirm --needed --noprogressbar "$pkg" >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1; then
        log_ok "$pkg kuruldu (AUR)."
    else
        log_error "$pkg KURULAMADI (AUR)"
        echo "[FAIL:aur] $pkg" >> "${LOG_FILE:-/tmp/archinit.log}"
    fi
}

# ── Flatpak ───────────────────────────────────────────────────
install_flatpak() {
    local app_id="$1"
    if ! is_installed flatpak; then
        log_warn "Flatpak bulunamadı — atlanıyor: $app_id"
        return 1
    fi
    if flatpak_installed "$app_id"; then
        log_warn "$app_id zaten kurulu."
        return 0
    fi
    log_info "Flatpak: $app_id kuruluyor..."
    if flatpak install -y --noninteractive flathub "$app_id" >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1; then
        log_ok "$app_id kuruldu (Flatpak)."
    else
        log_error "$app_id KURULAMADI (Flatpak)"
        echo "[FAIL:flatpak] $app_id" >> "${LOG_FILE:-/tmp/archinit.log}"
    fi
}

# ── Sistem güncellemesi ───────────────────────────────────────
update_system() {
    log_info "Sistem güncelleniyor (pacman -Syu)..."
    if sudo pacman -Syu --noconfirm >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1; then
        log_ok "Sistem güncellendi."
    else
        log_warn "Sistem güncellemesi başarısız — devam ediliyor."
    fi
}

# ── multilib ──────────────────────────────────────────────────
enable_multilib() {
    if grep -q "^\[multilib\]" /etc/pacman.conf; then
        return 0
    fi
    log_info "multilib deposu etkinleştiriliyor..."
    sudo sed -i '/^#\[multilib\]/{n;s/^#//}; s/^#\[multilib\]/[multilib]/' /etc/pacman.conf
    sudo pacman -Sy --noconfirm >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1 || true
    log_ok "multilib etkinleştirildi."
}

# ── Flatpak + Flathub ─────────────────────────────────────────
setup_flatpak() {
    if ! is_installed flatpak; then
        log_info "Flatpak kuruluyor..."
        sudo pacman -S --noconfirm --needed flatpak >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1 || true
    fi
    if ! flatpak remotes 2>/dev/null | grep -q flathub; then
        log_info "Flathub ekleniyor..."
        flatpak remote-add --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo \
            >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1 || true
    fi
    log_ok "Flatpak + Flathub hazır."
}

# ── yay (AUR helper) ──────────────────────────────────────────
setup_yay() {
    if is_installed yay; then
        log_ok "yay zaten kurulu."
        return 0
    fi
    log_info "yay (AUR helper) kuruluyor..."
    sudo pacman -S --noconfirm --needed git base-devel >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1 || true
    local tmp
    tmp=$(mktemp -d)
    if git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$tmp/yay" >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1; then
        (cd "$tmp/yay" && makepkg -si --noconfirm >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1) || true
        log_ok "yay kuruldu."
    else
        log_error "yay klonlanamadı — AUR paketleri atlanacak."
    fi
    rm -rf "$tmp"
}
