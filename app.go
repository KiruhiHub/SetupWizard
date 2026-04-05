package main

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

const (
	EventSetupLog      = "setup:log"
	EventSetupFinished = "setup:finished"
	RcloneTimeout      = 45 * time.Second
)

type App struct {
	ctx     context.Context
	rootDir string // binary'nin bulunduğu dizin
}

func NewApp() *App { return &App{} }

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx

	// Binary'nin gerçek konumunu bul (dev ve production için)
	exe, err := os.Executable()
	if err != nil {
		// fallback: çalışma dizini
		a.rootDir, _ = os.Getwd()
	} else {
		// Symlink'leri çöz
		exe, _ = filepath.EvalSymlinks(exe)
		a.rootDir = filepath.Dir(exe)
	}

	// Wails dev modunda binary tmp dizininde olabilir,
	// bu durumda proje kökünü bul
	if _, err := os.Stat(filepath.Join(a.rootDir, "scripts", "setup.sh")); err != nil {
		// Yukarı çık, scripts/ klasörünü ara (dev modu)
		for dir := a.rootDir; dir != "/"; dir = filepath.Dir(dir) {
			if _, err := os.Stat(filepath.Join(dir, "scripts", "setup.sh")); err == nil {
				a.rootDir = dir
				break
			}
		}
	}

	log.Printf("[ArchInit] rootDir: %s", a.rootDir)
}

// ── Rclone OAuth ──────────────────────────────────────────────

func (a *App) RcloneAuthorize(provider string) (string, error) {
	rcloneType := map[string]string{
		"google":   "drive",
		"onedrive": "onedrive",
		"icloud":   "webdav",
	}[strings.ToLower(provider)]

	if rcloneType == "" {
		return "", fmt.Errorf("desteklenmeyen sağlayıcı: %s", provider)
	}

	ctx, cancel := context.WithTimeout(a.ctx, RcloneTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, "rclone", "authorize", rcloneType, "--auth-no-open-browser")
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return "", fmt.Errorf("pipe hatası: %w", err)
	}
	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("rclone başlatılamadı: %w", err)
	}

	authURL := ""
	scanner := bufio.NewScanner(stderr)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if idx := strings.LastIndex(line, "http"); idx != -1 {
			authURL = line[idx:]
			break
		}
	}
	go func() { _ = cmd.Wait() }()

	if authURL == "" {
		return "", fmt.Errorf("auth URL bulunamadı")
	}
	return authURL, nil
}

// ── Setup Runner ──────────────────────────────────────────────

// RunSetup kurulum betiğini arkaplanda başlatır.
// Loglar setup:log eventi ile frontend'e akar.
// Bitince setup:finished eventi gönderilir.
func (a *App) RunSetup(profile, drivers, cloud string, apps []string, aur string) (string, error) {
	if profile == "" {
		return "", fmt.Errorf("profil seçimi zorunludur")
	}

	// setup.sh'ın absolute path'i
	setupScript := filepath.Join(a.rootDir, "scripts", "setup.sh")
	if _, err := os.Stat(setupScript); err != nil {
		return "", fmt.Errorf("setup.sh bulunamadı: %s", setupScript)
	}

	// Argüman listesi
	args := []string{setupScript, "--profile", profile}
	if drivers == "true" || drivers == "1" {
		args = append(args, "--drivers")
	}
	if cloud != "" && cloud != "none" {
		args = append(args, "--cloud", cloud)
	}
	if aur == "true" || aur == "1" {
		args = append(args, "--aur")
	}
	if len(apps) > 0 {
		args = append(args, "--apps", strings.Join(apps, ","))
	}

	// bash ile çalıştır, çalışma dizini proje kökü
	cmd := exec.Command("bash", args...)
	cmd.Dir = a.rootDir

	// sudo için mevcut ortamı aktar (SUDO_ASKPASS vs.)
	cmd.Env = append(os.Environ(),
		"SUDO_ASKPASS=/bin/false", // interaktif sudo'yu engelle
	)

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return "", fmt.Errorf("stdout pipe: %w", err)
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return "", fmt.Errorf("stderr pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("betik başlatılamadı: %w", err)
	}

	pid := cmd.Process.Pid
	log.Printf("[ArchInit] Setup started PID=%d profile=%s", pid, profile)

	// Logları frontend'e stream et (arkaplanda — UI bloklanmaz)
	go a.streamLines(stdout, "out")
	go a.streamLines(stderr, "err")
	go a.watchProcess(cmd)

	return fmt.Sprintf("Kurulum başlatıldı (PID %d)", pid), nil
}

// streamLines pipe'tan satır satır okur, her satırı frontend'e gönderir.
func (a *App) streamLines(pipe io.ReadCloser, source string) {
	defer pipe.Close()
	scanner := bufio.NewScanner(pipe)
	for scanner.Scan() {
		line := scanner.Text()

		// Log dosyası yolunu yakala
		if strings.HasPrefix(line, "[ARCHINIT] Log:") {
			logPath := strings.TrimSpace(strings.TrimPrefix(line, "[ARCHINIT] Log:"))
			runtime.EventsEmit(a.ctx, "setup:logfile", logPath)
		}

		runtime.EventsEmit(a.ctx, EventSetupLog, map[string]string{
			"source": source,
			"line":   line,
		})
	}
}

// watchProcess kurulum bitince setup:finished eventi gönderir.
func (a *App) watchProcess(cmd *exec.Cmd) {
	err := cmd.Wait()
	payload := map[string]any{
		"success": err == nil,
		"time":    time.Now().Format(time.RFC3339),
	}
	if err != nil {
		payload["error"] = err.Error()
		log.Printf("[ArchInit] Setup failed: %v", err)
	}
	runtime.EventsEmit(a.ctx, EventSetupFinished, payload)
}
