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
	rootDir string
}

func NewApp() *App { return &App{} }

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx

	exe, err := os.Executable()
	if err != nil {
		a.rootDir, _ = os.Getwd()
	} else {
		exe, _ = filepath.EvalSymlinks(exe)
		a.rootDir = filepath.Dir(exe)
	}

	// Dev modunda binary tmp'de olabilir — scripts/ klasörünü yukarı çıkarak bul
	if _, err := os.Stat(filepath.Join(a.rootDir, "scripts", "setup.sh")); err != nil {
		for dir := a.rootDir; dir != "/"; dir = filepath.Dir(dir) {
			if _, err := os.Stat(filepath.Join(dir, "scripts", "setup.sh")); err == nil {
				a.rootDir = dir
				break
			}
		}
	}

	log.Printf("[ArchInit] rootDir: %s", a.rootDir)
}

// ── KDE Masaüstü Teması ───────────────────────────────────────

// ApplyKDETheme KDE Plasma masaüstü stilini gerçek zamanlı uygular.
// style: "windows" | "macos" | "kde"
func (a *App) ApplyKDETheme(style string) error {
	themeMap := map[string]string{
		"windows": "org.kde.breeze.desktop",
		"macos":   "com.github.vinceliuice.WhiteSur-dark",
		"kde":     "org.kde.breezedark.desktop",
	}

	theme, ok := themeMap[strings.ToLower(style)]
	if !ok {
		return fmt.Errorf("bilinmeyen stil: %s", style)
	}

	// lookandfeeltool ile temayı uygula (KDE Plasma)
	cmd := exec.Command("lookandfeeltool", "--apply", theme)
	cmd.Env = append(os.Environ(),
		"DISPLAY=:0",
		"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus",
	)

	out, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("[KDE] lookandfeeltool hata: %v — %s", err, string(out))
		return fmt.Errorf("tema uygulanamadı: %w", err)
	}

	log.Printf("[KDE] Tema uygulandı: %s", theme)
	return nil
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
		return "", fmt.Errorf("auth URL bulunamadı — rclone kurulu mu?")
	}
	return authURL, nil
}

// ── Setup Runner ──────────────────────────────────────────────

func (a *App) RunSetup(profile, drivers, cloud string, apps []string, aur string) (string, error) {
	if profile == "" {
		return "", fmt.Errorf("profil seçimi zorunludur")
	}

	setupScript := filepath.Join(a.rootDir, "scripts", "setup.sh")
	if _, err := os.Stat(setupScript); err != nil {
		return "", fmt.Errorf("setup.sh bulunamadı: %s", setupScript)
	}

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

	cmd := exec.Command("bash", args...)
	cmd.Dir = a.rootDir
	// NOT: SUDO_ASKPASS kaldırıldı — yay kendi sudo'sunu halleder
	cmd.Env = os.Environ()

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
	log.Printf("[ArchInit] Setup PID=%d profile=%s", pid, profile)

	go a.streamLines(stdout, "out")
	go a.streamLines(stderr, "err")
	go a.watchProcess(cmd)

	return fmt.Sprintf("Kurulum başlatıldı (PID %d)", pid), nil
}

func (a *App) streamLines(pipe io.ReadCloser, source string) {
	defer pipe.Close()
	scanner := bufio.NewScanner(pipe)
	for scanner.Scan() {
		line := scanner.Text()
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
