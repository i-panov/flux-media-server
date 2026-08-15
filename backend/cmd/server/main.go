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
	)

	flag.StringVar(&configPath, "config", "", "path to config file (default: $CONFIG_PATH or configs/config.yaml)")
	flag.BoolVar(&showVer, "version", false, "print version and exit")
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

	application, err := app.New(cfg, version)
	if err != nil {
		log.Fatalf("Failed to initialize app: %v", err)
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

// shutdown выполняет полный цикл остановки: воркеры, HTTP-сервер, БД.
func shutdown(application *app.App) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := application.Shutdown(ctx); err != nil {
		log.Printf("Shutdown error: %v", err)
	}
}
