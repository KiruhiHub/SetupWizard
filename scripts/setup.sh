#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  ArchInit — Ana Kurulum Betiği
#
#  Kullanım:
#    setup.sh --profile <profil> [seçenekler]
#
#  Seçenekler:
#    --profile  gunluk | yazilimci | ozel   (zorunlu)
#    --drivers  Kapalı kaynak GPU sürücüleri
#    --cloud    google | icloud | onedrive | none
#    --apps     "app1,app2"  (ozel profil için)
#    --aur      AUR desteği (yay kurulumu)
#
#  Arkaplanda çalıştırma:
#    setup.sh --profile gunluk &
#    Loglar: /tmp/archinit_<tarih>.log
# ═══════════════════════════════════════════════════════════════

# ── Argümanlar ────────────────────────────────────────────────
PROFILE=""
DRIVERS=false
CLOUD="none"
APPS=""
AUR=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="$2"; shift 2 ;;
        --drivers) DRIVERS=true; shift ;;
        --cloud)   CLOUD="$2";   shift 2 ;;
        --apps)    APPS="$2";    shift 2 ;;
        --aur)     AUR=true;     shift ;;
        *)         shift ;;
    esac
done

# ── Log dosyası (Wails bunu okur) ─────────────────────────────
export LOG_FILE="/tmp/archinit_$(date +%Y%m%d_%H%M%S).log"

# ── Ortak kütüphane ───────────────────────────────────────────
source "$SCRIPT_DIR/lib/common.sh"

# ── Log başlığı ───────────────────────────────────────────────
{
    echo "══════════════════════════════════════════"
    echo "  ArchInit Kurulum Logu"
    echo "  Tarih  : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  Profil : $PROFILE"
    echo "  Bulut  : $CLOUD"
    echo "  Sürücü : $DRIVERS"
    echo "  AUR    : $AUR"
    echo "  PID    : $$"
    echo "══════════════════════════════════════════"
} > "$LOG_FILE"

# Log dosyasını stdout'a da yaz (Wails stream için)
echo "[ARCHINIT] Log: $LOG_FILE"
echo "[ARCHINIT] PID: $$"

# ── Profil doğrulama ──────────────────────────────────────────
if [[ -z "$PROFILE" ]]; then
    log_error "--profile belirtilmedi. Kullanım: gunluk | yazilimci | ozel"
    exit 1
fi

# ── Donanım tespiti ───────────────────────────────────────────
detect_hardware() {
    log_section "Donanım Tespiti"

    # Laptop kontrolü
    if [[ -d /sys/class/power_supply/BAT0 ]] || [[ -d /sys/class/power_supply/BAT1 ]]; then
        log_info "Laptop tespit edildi — TLP güç yönetimi kuruluyor..."
        install_pkg "tlp"
        install_pkg "tlp-rdw"
        sudo systemctl enable --now tlp >> "$LOG_FILE" 2>&1 || true
        log_ok "TLP etkin."
    fi

    # GPU tespiti
    if lspci 2>/dev/null | grep -qi "nvidia"; then
        log_info "NVIDIA GPU tespit edildi."
        if [[ "$DRIVERS" == "true" ]]; then
            install_pkg "nvidia"
            install_pkg "nvidia-utils"
            install_pkg "nvidia-settings"
            log_ok "NVIDIA sürücüsü kuruldu."
        else
            log_warn "NVIDIA sürücüsü atlandı (--drivers ile etkinleştirin)."
        fi
    elif lspci 2>/dev/null | grep -qi "amd\|radeon"; then
        log_info "AMD GPU — mesa + vulkan-radeon kuruluyor."
        install_pkg "mesa"
        install_pkg "vulkan-radeon"
    elif lspci 2>/dev/null | grep -qi "intel"; then
        log_info "Intel GPU — mesa + vulkan-intel kuruluyor."
        install_pkg "mesa"
        install_pkg "vulkan-intel"
    fi
}

# ── Kapalı kaynak codec'ler ───────────────────────────────────
install_codecs() {
    if [[ "$DRIVERS" != "true" ]]; then return 0; fi
    log_section "Kapalı Kaynak Codec'ler"
    enable_multilib
    install_pkg "lib32-mesa"
    install_pkg "ffmpeg"
    log_ok "Codec'ler kuruldu."
}

# ── Bulut senkronizasyonu ─────────────────────────────────────
setup_cloud() {
    if [[ "$CLOUD" == "none" ]] || [[ -z "$CLOUD" ]]; then return 0; fi
    log_section "Bulut: $CLOUD"

    install_pkg "rclone"

    local mount_dir="$HOME/Cloud/$CLOUD"
    mkdir -p "$mount_dir"

    # systemd user servisi
    local svc_dir="$HOME/.config/systemd/user"
    mkdir -p "$svc_dir"

    cat > "$svc_dir/rclone-${CLOUD}.service" <<EOF
[Unit]
Description=rclone — $CLOUD
After=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount ${CLOUD}: ${mount_dir} \\
    --vfs-cache-mode writes \\
    --vfs-cache-max-size 512M \\
    --log-level INFO
ExecStop=/bin/fusermount -u ${mount_dir}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload >> "$LOG_FILE" 2>&1 || true
    log_ok "rclone servisi oluşturuldu → $mount_dir"
    log_warn "Aktifleştirmek için: rclone config && systemctl --user enable --now rclone-${CLOUD}"
}

# ── Profil çalıştır ───────────────────────────────────────────
run_profile() {
    case "$PROFILE" in
        yazilimci|developer|dev)
            bash "$SCRIPT_DIR/profiles/developer.sh"
            ;;
        gunluk|daily)
            bash "$SCRIPT_DIR/profiles/daily.sh"
            ;;
        ozel|custom)
            export CUSTOM_APPS="$APPS"
            bash "$SCRIPT_DIR/profiles/custom.sh"
            ;;
        *)
            log_error "Bilinmeyen profil: '$PROFILE'"
            exit 1
            ;;
    esac
}

# ── Özet rapor ────────────────────────────────────────────────
print_summary() {
    local fails
    fails=$(grep -c "^\[FAIL" "$LOG_FILE" 2>/dev/null || echo 0)

    echo ""
    echo "══════════════════════════════════════════"
    echo "  ArchInit Kurulum Tamamlandı"
    echo "  Profil : $PROFILE"
    echo "  Tarih  : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  Log    : $LOG_FILE"
    if [[ "$fails" -gt 0 ]]; then
        echo "  Uyarı  : $fails paket kurulamadı (log'u inceleyin)"
    else
        echo "  Durum  : Tüm paketler başarıyla kuruldu"
    fi
    echo "══════════════════════════════════════════"
    echo ""

    # Wails event için özel satır
    if [[ "$fails" -gt 0 ]]; then
        echo "[ARCHINIT:DONE:WARN] $fails paket başarısız"
    else
        echo "[ARCHINIT:DONE:OK] Kurulum tamamlandı"
    fi
}

# ── Ana akış ──────────────────────────────────────────────────
main() {
    log_section "ArchInit Başlatılıyor"
    log_info "Profil: $PROFILE | Log: $LOG_FILE"

    # sudo önbelleği yoksa kullanıcıyı bilgilendir
    if ! sudo -n true 2>/dev/null; then
        log_error "sudo önbelleği bulunamadı!"
        log_error "Lütfen bir terminal açın ve şunu çalıştırın:"
        log_error "  sudo -v"
        log_error "Ardından uygulamayı tekrar başlatın."
        echo "[ARCHINIT:DONE:FAIL] sudo önbelleği yok"
        exit 1
    fi

    detect_hardware
    install_codecs
    run_profile
    setup_cloud
    print_summary
}

main
