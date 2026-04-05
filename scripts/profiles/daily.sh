#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  ArchInit — Günlük Kullanıcı Profili
#
#  Açık kaynak (pacman):
#    VLC · Thunderbird · LibreOffice · Evince · CUPS · codec'ler
#
#  AUR (kapalı kaynak):
#    LibreWolf · Google Chrome
#
#  Flatpak:
#    Spotify · WhatsApp · Zoom
#
#  Web App (xdg-open kısayolu):
#    Microsoft 365
# ═══════════════════════════════════════════════════════════════
source "$(dirname "$0")/../lib/common.sh"

# ── Paket listeleri ───────────────────────────────────────────
PACMAN_PKGS=(
    # Medya
    vlc
    ffmpeg
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst-plugins-ugly
    gst-libav          # H.264 / AAC / MP3
    x265
    x264
    flac
    opus
    # Ofis & Belgeler
    libreoffice-fresh
    libreoffice-fresh-tr
    evince             # PDF görüntüleyici
    # E-posta
    thunderbird
    # Yazıcı
    cups
    system-config-printer
    hplip              # HP sürücüsü
    # Yardımcılar
    curl
    wget
    unzip
    p7zip
    file-roller        # Arşiv yöneticisi
    xdg-utils          # Web app kısayolları için
)

AUR_PKGS=(
    librewolf-bin      # Gizlilik odaklı tarayıcı
    google-chrome      # Kapalı kaynak Chrome
)

FLATPAK_APPS=(
    com.spotify.Client                    # Spotify
    com.github.eneshecan.WhatsAppForLinux # WhatsApp
    us.zoom.Zoom                          # Zoom
)

# ── CUPS yazıcı servisi ───────────────────────────────────────
configure_cups() {
    log_info "CUPS yazıcı servisi etkinleştiriliyor..."
    # CUPS system service — sudo gerekir
    sudo systemctl enable --now cups >> "${LOG_FILE}" 2>&1 || \
        log_warn "CUPS etkinleştirilemedi (sudo gerekli)."
    log_ok "CUPS hazır."
}

# ── Microsoft 365 web app kısayolu ───────────────────────────
create_m365_shortcut() {
    local desktop_dir="$HOME/.local/share/applications"
    mkdir -p "$desktop_dir"
    cat > "$desktop_dir/microsoft365.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Microsoft 365
Comment=Microsoft 365 Web Uygulaması
Exec=xdg-open https://www.office.com
Icon=applications-office
Terminal=false
Categories=Office;
EOF
    chmod +x "$desktop_dir/microsoft365.desktop"
    log_ok "Microsoft 365 web app kısayolu oluşturuldu."
}

# ── Ana akış ──────────────────────────────────────────────────
main() {
    log_section "Günlük Kullanıcı Profili"

    update_system
    setup_yay
    setup_flatpak

    log_section "Temel Uygulamalar (pacman)"
    for pkg in "${PACMAN_PKGS[@]}"; do install_pkg "$pkg"; done

    log_section "Kapalı Kaynak (AUR)"
    for pkg in "${AUR_PKGS[@]}"; do install_aur "$pkg"; done

    log_section "Flatpak Uygulamaları"
    for app in "${FLATPAK_APPS[@]}"; do install_flatpak "$app"; done

    log_section "Servisler & Kısayollar"
    configure_cups
    create_m365_shortcut

    log_done "Günlük Kullanıcı Profili"
}

main
