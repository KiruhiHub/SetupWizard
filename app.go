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

// Sabit tanımlamalar (Magic Strings yerine)
const (
	EventSetupLog      = "setup:log"
	EventSetupFinished = "setup:finished"
	RcloneTimeout      = 45 * time.Second
)

// App struct definition
type App struct {
	ctx context.Context
}

func NewApp() *App {
	return &App{}
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}

// ====================== RCLONE SERVICE ======================

// RcloneAuthorize sağlayıcıya göre yetkilendirme URL'sini döndürür.
func (a *App) RcloneAuthorize(provider string) (string, error) {
	rcloneType := map[string]string{
		"google":   "drive",
		"onedrive": "onedrive",
		"icloud":   "webdav",
	}[strings.ToLower(provider)]

	if rcloneType == "" {
		return "", fmt.Errorf("desteklenmeyen bulut sağlayıcı: %s", provider)
	}

	ctx, cancel := context.WithTimeout(a.ctx, RcloneTimeout)
	defer cancel()

	// --auth-no-open-browser bayrağı ile URL'yi terminale bastırıyoruz
	cmd := exec.CommandContext(ctx, "rclone", "authorize", rcloneType, "--auth-no-open-browser")

	stderr, err := cmd.StderrPipe()
	if err != nil {
		return "", fmt.Errorf("pipe hatası: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("rclone başlatılamadı: %w", err)
	}

	return a.captureAuthURL(stderr, cmd, ctx)
}

// captureAuthURL stderr üzerinden akan veriden URL'yi ayıklar.
func (a *App) captureAuthURL(r io.Reader, cmd *exec.Cmd, ctx context.Context) (string, error) {
	authURL := ""
	scanner := bufio.NewScanner(r)

	// URL'yi yakalamak için okuma yapıyoruz
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if idx := strings.LastIndex(line, "http"); idx != -1 {
			authURL = line[idx:]
			break
		}
	}

	// Arka planda komutun bitişini bekle (Zombi process önleme)
	go func() {
		_ = cmd.Wait()
	}()

	if authURL == "" {
		return "", fmt.Errorf("yetkilendirme adresi (URL) bulunamadı")
	}

	return authURL, nil
}

// ====================== SETUP ENGINE ======================

// RunSetup kurulum betiğini argümanlarla çalıştırır.
func (a *App) RunSetup(profile, drivers, cloud string, apps []string, aur string) (string, error) {
	if profile == "" {
		return "", fmt.Errorf("profil seçimi zorunludur")
	}

	args := a.buildSetupArgs(profile, drivers, cloud, apps, aur)
	cmd := exec.Command("bash", args...)

	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()

	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("betik başlatılamadı: %w", err)
	}

	// Logları asenkron olarak stream et
	go a.streamOutput(stdout, "stdout")
	go a.streamOutput(stderr, "stderr")

	// Süreci takip et ve sonucu bildir
	go a.monitorProcess(cmd)

	return fmt.Sprintf("Kurulum işlemi başlatıldı (PID: %d)", cmd.Process.Pid), nil
}

// buildSetupArgs komut satırı argümanlarını temiz bir şekilde inşa eder.
func (a *App) buildSetupArgs(profile, drivers, cloud string, apps []string, aur string) []string {
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

// monitorProcess komutun bitişini bekler ve Wails Event ile frontend'i bilgilendirir.
func (a *App) monitorProcess(cmd *exec.Cmd) {
	err := cmd.Wait()

	payload := map[string]any{
		"success": err == nil,
		"time":    time.Now().Format(time.RFC3339),
	}

	if err != nil {
		payload["error"] = err.Error()
		log.Printf("Setup failed: %v", err)
	}

	runtime.EventsEmit(a.ctx, EventSetupFinished, payload)
}

// streamOutput pipe üzerindeki her satırı anlık olarak frontend'e gönderir.
func (a *App) streamOutput(pipe io.ReadCloser, source string) {
	defer pipe.Close()
	scanner := bufio.NewScanner(pipe)

	for scanner.Scan() {
		runtime.EventsEmit(a.ctx, EventSetupLog, map[string]string{
			"source": source,
			"line":   scanner.Text(),
		})
	}
}
