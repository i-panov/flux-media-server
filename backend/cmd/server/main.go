package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"flux/internal/app"
	"flux/internal/config"
)

var version = "dev"

func main() {
	var (
		configPath string
		showVer    bool
		doScan     bool
	)

	flag.StringVar(&configPath, "config", "", "path to config file (default: $CONFIG_PATH or configs/config.yaml)")
	flag.BoolVar(&showVer, "version", false, "print version and exit")
	flag.BoolVar(&doScan, "scan", false, "scan all configured media libraries and exit (no HTTP server)")
	flag.Parse()

	if showVer {
		fmt.Printf("flux-media-server %s\n", version)
		os.Exit(0)
	}

	if configPath == "" {
		configPath = os.Getenv("CONFIG_PATH")
	}
	if configPath == "" {
		configPath = "configs/config.yaml"
	}

	cfg, err := config.Load(configPath)
	if err != nil {
		log.Fatalf("Failed to load config %s: %v", configPath, err)
	}

	if cfg.Server.Debug {
		log.Println("WARNING: debug mode is enabled — OTP codes are returned in API responses and SQL queries are logged. This requires server.env: \"dev\" and must never be used in production.")
	}

	// Консольный режим (-scan): один полный проход по библиотекам и выход.
	// ConsoleMode отключает фоновых работников: первичный скан гонялся бы
	// с консольным за одну БД (ErrScanInProgress), watcher дублировал бы
	// события консольного скана.
	var newOpts []app.Option
	if doScan {
		newOpts = append(newOpts, app.ConsoleMode())
	}

	application, err := app.New(cfg, version, newOpts...)
	if err != nil {
		log.Fatalf("Failed to initialize app: %v", err)
	}

	if doScan {
		code := runScan(application)
		shutdown(application)
		if code != 0 {
			os.Exit(code)
		}
		return
	}

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	serverErr := make(chan error, 1)
	go func() {
		serverErr <- application.Listen()
	}()

	select {
	case err := <-serverErr:
		// Perform graceful shutdown before exiting so background goroutines
		// (watcher, OTP purge, etc.) are cleaned up.
		log.Printf("Server error: %v", err)
		shutdown(application)
		os.Exit(1)
	case <-quit:
		log.Println("Shutting down server...")
	}

	shutdown(application)
	log.Println("Server stopped")
}

// runScan выполняет полный скан библиотек в консольном режиме и возвращает
// код выхода (0 — успех, 1 — ошибка скана, 130 — прервано пользователем).
// Ctrl+C прерывает скан корректно: контекст отменяется, сканер успевает
// завершить текущую операцию.
func runScan(application *app.App) int {
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	scanDone := make(chan error, 1)
	go func() {
		scanDone <- application.Scanner().ScanAll(ctx)
	}()

	select {
	case err := <-scanDone:
		if err != nil {
			log.Printf("Scan finished with error: %v", err)
			return 1
		}
		log.Println("Scan finished successfully")
		return 0
	case <-quit:
		log.Println("Scan interrupted, stopping...")
		cancel()
		if err := <-scanDone; err != nil {
			log.Printf("Scan stopped with error: %v", err)
		}
		return 130
	}
}

// shutdown выполняет полный цикл остановки: воркеры, HTTP-сервер, БД.
func shutdown(application *app.App) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := application.Shutdown(ctx); err != nil {
		log.Printf("Shutdown error: %v", err)
	}
}
