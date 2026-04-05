#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  ArchInit — Özel Profil
#  Çevre değişkeni: CUSTOM_APPS="chrome,spotify,docker,..."
# ═══════════════════════════════════════════════════════════════
source "$(dirname "$0")/../lib/common.sh"

# ── Uygulama kataloğu ─────────────────────────────────────────
# Format: ["anahtar"]="kaynak:paket_id"
declare -A CATALOG=(
    # Tarayıcılar
    ["librewolf"]="aur:librewolf-bin"
    ["chrome"]="aur:google-chrome"
    ["firefox"]="pacman:firefox"
    ["chromium"]="pacman:chromium"

    # Medya
    ["vlc"]="pacman:vlc"
    ["spotify"]="flatpak:com.spotify.Client"
    ["mpv"]="pacman:mpv"

    # İletişim
    ["whatsapp"]="flatpak:com.github.eneshecan.WhatsAppForLinux"
    ["zoom"]="flatpak:us.zoom.Zoom"
    ["discord"]="flatpak:com.discordapp.Discord"
    ["telegram"]="flatpak:org.telegram.desktop"
    ["thunderbird"]="pacman:thunderbird"
    ["signal"]="flatpak:org.signal.Signal"

    # Ofis
    ["libreoffice"]="pacman:libreoffice-fresh"
    ["onlyoffice"]="flatpak:org.onlyoffice.desktopeditors"
    ["evince"]="pacman:evince"

    # Geliştirme
    ["vscodium"]="aur:vscodium-bin"
    ["vscode"]="aur:visual-studio-code-bin"
    ["docker"]="pacman:docker"
    ["git"]="pacman:git"
    ["btop"]="pacman:btop"
    ["alacritty"]="pacman:alacritty"
    ["postman"]="aur:postman-bin"
    ["zsh"]="pacman:zsh"
    ["neovim"]="pacman:neovim"

    # Sistem
    ["timeshift"]="aur:timeshift"
    ["gparted"]="pacman:gparted"
    ["htop"]="pacman:htop"
)

# ── Tek uygulama kur ──────────────────────────────────────────
install_app() {
    local key
    key="$(echo "$1" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    local entry="${CATALOG[$key]:-}"

    if [[ -z "$entry" ]]; then
        log_warn "Katalogda bulunamadı: $key — atlanıyor."
        return 0
    fi

    local src="${entry%%:*}"
    local pkg="${entry#*:}"

    case "$src" in
        pacman)  install_pkg     "$pkg" ;;
        aur)     install_aur     "$pkg" ;;
        flatpak) install_flatpak "$pkg" ;;
        *)       log_error "Bilinmeyen kaynak: $src" ;;
    esac
}

# ── Ana akış ──────────────────────────────────────────────────
main() {
    local apps_raw="${CUSTOM_APPS:-}"

    if [[ -z "$apps_raw" ]]; then
        log_warn "CUSTOM_APPS boş — hiç uygulama seçilmedi."
        exit 0
    fi

    log_section "Özel Profil"

    refresh_sudo
    update_system
    setup_yay
    setup_flatpak

    log_section "Seçilen Uygulamalar"
    IFS=',' read -ra apps <<< "$apps_raw"
    for app in "${apps[@]}"; do
        install_app "$app"
    done

    log_done "Özel Profil"
}

main
