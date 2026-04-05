#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  ArchInit — Yazılımcı Profili
#  VSCodium · Alacritty · Docker · Git · SSH · zsh+omz · btop · Postman
# ═══════════════════════════════════════════════════════════════
# set -e YOK — hata loglanır, kurulum devam eder
source "$(dirname "$0")/../lib/common.sh"

# ── Paketler ──────────────────────────────────────────────────
PACMAN_PKGS=(
    git
    openssh
    docker
    docker-compose
    alacritty
    zsh
    btop
    curl
    wget
    unzip
    base-devel
    man-db
    ripgrep
    fd
    jq
)

AUR_PKGS=(
    vscodium-bin
    postman-bin
)

# ── Docker ────────────────────────────────────────────────────
configure_docker() {
    log_info "Docker servisi etkinleştiriliyor..."
    sudo systemctl enable --now docker >> "${LOG_FILE}" 2>&1 || true
    # Kullanıcıyı docker grubuna ekle (sudosuz docker)
    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER"
        log_ok "Kullanıcı docker grubuna eklendi (yeniden giriş gerekli)."
    fi
    log_ok "Docker hazır."
}

# ── Alacritty config ──────────────────────────────────────────
configure_alacritty() {
    local cfg="$HOME/.config/alacritty/alacritty.toml"
    [[ -f "$cfg" ]] && { log_warn "Alacritty config zaten var."; return 0; }
    mkdir -p "$(dirname "$cfg")"
    cat > "$cfg" <<'TOML'
[window]
opacity        = 0.95
padding        = { x = 14, y = 12 }
decorations    = "full"

[font]
normal         = { family = "JetBrains Mono", style = "Regular" }
size           = 13.0

[colors.primary]
background     = "#0c0e14"
foreground     = "#e8eaf2"

[colors.normal]
black          = "#1e2535"
red            = "#f87171"
green          = "#34d399"
yellow         = "#fbbf24"
blue           = "#60a5fa"
magenta        = "#a78bfa"
cyan           = "#22d3ee"
white          = "#e8eaf2"
TOML
    log_ok "Alacritty config oluşturuldu."
}

# ── Oh My Zsh + eklentiler ────────────────────────────────────
install_ohmyzsh() {
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        log_warn "Oh My Zsh zaten kurulu."
    else
        log_info "Oh My Zsh kuruluyor..."
        RUNZSH=no CHSH=no \
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
            >> "${LOG_FILE}" 2>&1 || { log_error "Oh My Zsh kurulamadı."; return 1; }
        log_ok "Oh My Zsh kuruldu."
    fi

    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    # zsh-autosuggestions
    if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
            "$ZSH_CUSTOM/plugins/zsh-autosuggestions" >> "${LOG_FILE}" 2>&1 || true
    fi

    # zsh-syntax-highlighting
    if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
            "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" >> "${LOG_FILE}" 2>&1 || true
    fi

    # .zshrc — eklentileri etkinleştir
    if [[ -f "$HOME/.zshrc" ]]; then
        sed -i 's/^plugins=(.*/plugins=(git docker zsh-autosuggestions zsh-syntax-highlighting)/' \
            "$HOME/.zshrc" 2>/dev/null || true
    fi

    # Varsayılan shell → zsh
    if [[ "$SHELL" != "$(which zsh)" ]]; then
        sudo chsh -s "$(which zsh)" "$USER" >> "${LOG_FILE}" 2>&1 || true
        log_ok "Varsayılan shell zsh olarak ayarlandı."
    fi

    log_ok "Oh My Zsh + eklentiler hazır."
}

# ── SSH dizini ────────────────────────────────────────────────
configure_ssh() {
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    # Varsayılan SSH config
    if [[ ! -f "$HOME/.ssh/config" ]]; then
        cat > "$HOME/.ssh/config" <<'EOF'
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    AddKeysToAgent yes
EOF
        chmod 600 "$HOME/.ssh/config"
    fi
    log_ok "SSH dizini ve config hazır."
}

# ── Ana akış ──────────────────────────────────────────────────
main() {
    log_section "Yazılımcı Profili"

    refresh_sudo
    update_system
    setup_yay

    log_section "Temel Araçlar (pacman)"
    for pkg in "${PACMAN_PKGS[@]}"; do install_pkg "$pkg"; done

    log_section "AUR Paketleri"
    for pkg in "${AUR_PKGS[@]}"; do install_aur "$pkg"; done

    log_section "Yapılandırma"
    configure_docker
    configure_alacritty
    install_ohmyzsh
    configure_ssh

    log_done "Yazılımcı Profili"
}

main
