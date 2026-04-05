#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  ArchInit — Common Library
#  set -e YOK — hata loglanır, kurulum devam eder.
#
#  Şifresiz kurulum stratejisi:
#    pacman/AUR  → yay (kendi sudo cache'ini halleder)
#    Flatpak     → flatpak install --user  (root gerekmez)
#    systemd     → systemctl --user        (root gerekmez)
# ═══════════════════════════════════════════════════════════════

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

_log() { echo "[${1}] ${*:2}" >> "${LOG_FILE:-/tmp/archinit.log}"; }

log_ok()      { echo -e "${GREEN}[OK]${RESET} $*";  _log OK "$*"; }
log_info()    { echo -e "${CYAN}[>>]${RESET} $*";   _log ">>" "$*"; }
log_warn()    { echo -e "${YELLOW}[!!]${RESET} $*"; _log "!!" "$*"; }
log_error()   { echo -e "${RED}[ERR]${RESET} $*";  _log ERR "$*"; }
log_section() {
    echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}\n"
    echo -e "\n══ $* ══" >> "${LOG_FILE:-/tmp/archinit.log}"
}
log_done() {
    echo -e "\n${GREEN}${BOLD}[DONE] $*${RESET}\n"
    _log DONE "$*"
}

is_installed()  { command -v "$1" &>/dev/null; }
pkg_installed() { pacman -Qi "$1" &>/dev/null 2>&1; }

# Flatpak: önce --user scope'ta ara, sonra sistem genelinde
flatpak_installed() {
    flatpak list --app --user   --columns=application 2>/dev/null | grep -qx "$1" ||
    flatpak list --app --system --columns=application 2>/dev/null | grep -qx "$1"
}

# ── pacman / AUR — yay üzerinden ─────────────────────────────
# yay kendi sudo cache'ini halleder; şifre sadece ilk yay
# kurulumunda bir kez sorulur.
install_pkg() {
    local pkg="$1"
    if pkg_installed "$pkg"; then
        log_warn "$pkg zaten kurulu."
        return 0
    fi
    log_info "Kuruluyor: $pkg"
    if yay -S --noconfirm --needed --noprogressbar "$pkg" \
            >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1; then
        log_ok "$pkg kuruldu."
    else
        log_error "$pkg KURULAMADI"
        echo "[FAIL] $pkg" >> "${LOG_FILE:-/tmp/archinit.log}"
    fi
}

# AUR ayrı fonksiyon — yay zaten AUR'u destekler
install_aur() { install_pkg "$1"; }

# ── Flatpak — --user flag ile şifresiz ───────────────────────
install_flatpak() {
    local app_id="$1"

    if ! is_installed flatpak; then
        log_warn "Flatpak kurulu değil — atlanıyor: $app_id"
        return 1
    fi

    if flatpak_installed "$app_id"; then
        log_warn "$app_id zaten kurulu."
        return 0
    fi

    log_info "Flatpak (--user): $app_id"
    if flatpak install --user -y --noninteractive flathub "$app_id" \
            >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1; then
        log_ok "$app_id kuruldu (Flatpak --user)."
    else
        log_error "$app_id KURULAMADI (Flatpak)"
        echo "[FAIL:flatpak] $app_id" >> "${LOG_FILE:-/tmp/archinit.log}"
    fi
}

# ── Sistem güncellemesi ───────────────────────────────────────
update_system() {
    log_info "Sistem güncelleniyor (yay -Syu)..."
    if yay -Syu --noconfirm --noprogressbar \
            >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1; then
        log_ok "Sistem güncellendi."
    else
        log_warn "Güncelleme başarısız — devam ediliyor."
    fi
}

# ── multilib ──────────────────────────────────────────────────
enable_multilib() {
    grep -q "^\[multilib\]" /etc/pacman.conf && return 0
    log_info "multilib etkinleştiriliyor..."
    # yay sudo'yu halleder
    yay -S --noconfirm --needed multilib-devel \
        >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1 || true
}

# ── Flatpak + Flathub (--user remote) ────────────────────────
setup_flatpak() {
    # Flatpak yoksa yay ile kur (tek sudo gerekebilir)
    if ! is_installed flatpak; then
        log_info "Flatpak kuruluyor..."
        yay -S --noconfirm --needed flatpak \
            >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1 || true
    fi

    # --user remote — şifre gerekmez
    if ! flatpak remotes --user 2>/dev/null | grep -q flathub; then
        log_info "Flathub (--user) ekleniyor..."
        flatpak remote-add --user --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo \
            >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1 || true
    fi

    log_ok "Flatpak + Flathub (--user) hazır."
}

# ── yay kurulumu ──────────────────────────────────────────────
setup_yay() {
    if is_installed yay; then
        log_ok "yay zaten kurulu."
        return 0
    fi

    log_info "yay kuruluyor (tek seferlik sudo)..."
    # Bu tek sudo — yay kurulduktan sonra her şey şifresiz
    sudo pacman -S --noconfirm --needed git base-devel \
        >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1 || true

    local tmp
    tmp=$(mktemp -d)
    if git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$tmp/yay" \
            >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1; then
        (cd "$tmp/yay" && makepkg -si --noconfirm \
            >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1) || true
        log_ok "yay kuruldu."
    else
        log_error "yay klonlanamadı — AUR paketleri atlanacak."
    fi
    rm -rf "$tmp"
}

# ── systemd user servisi etkinleştir (şifresiz) ───────────────
enable_user_service() {
    local svc="$1"
    systemctl --user enable --now "$svc" \
        >> "${LOG_FILE:-/tmp/archinit.log}" 2>&1 \
        && log_ok "$svc (user service) etkin." \
        || log_warn "$svc etkinleştirilemedi."
}
