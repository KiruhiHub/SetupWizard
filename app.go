package main

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"log"
	"os/exec"
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
	ctx context.Context
}

func NewApp() *App { return &App{} }

func (a *App) startup(ctx context.Context) { a.ctx = ctx }

// ── Rclone OAuth URL ──────────────────────────────────────────

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

	args := buildArgs(profile, drivers, cloud, apps, aur)

	// Betiği bash ile çalıştır
	cmd := exec.Command("bash", args...)

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

	// Logları frontend'e stream et (arkaplanda)
	go a.streamLines(stdout, "out")
	go a.streamLines(stderr, "err")

	// Bitişi izle (arkaplanda — UI bloklanmaz)
	go a.watchProcess(cmd)

	return fmt.Sprintf("Kurulum başlatıldı (PID %d)", cmd.Process.Pid), nil
}

// buildArgs setup.sh için argüman listesi oluşturur.
func buildArgs(profile, drivers, cloud string, apps []string, aur string) []string {
	args := []string{"./scripts/setup.sh", "--profile", profile}

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
	return args
}

// streamLines pipe'tan satır satır okur, her satırı frontend'e gönderir.
func (a *App) streamLines(pipe io.ReadCloser, source string) {
	defer pipe.Close()
	scanner := bufio.NewScanner(pipe)
	for scanner.Scan() {
		line := scanner.Text()

		// Log dosyası yolunu yakala ve frontend'e ilet
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
