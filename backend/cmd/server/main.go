package main

import (
	"fmt"
	"log"
	"os"
	"time"

	"github.com/gofiber/fiber/v2"

	"flux/internal/config"
	"flux/internal/email"
	"flux/internal/handlers"
	"flux/internal/middleware"
	"flux/internal/repository"
	"flux/internal/services"
)

func main() {
	configPath := os.Getenv("CONFIG_PATH")
	if configPath == "" {
		configPath = "configs/config.yaml"
	}

	cfg, err := config.Load(configPath)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	db, err := repository.InitDB(cfg.Database.Path)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	if err := repository.AutoMigrate(db); err != nil {
		log.Fatalf("Failed to migrate database: %v", err)
	}

	userRepo := repository.NewUserRepository(db)
	mediaRepo := repository.NewMediaRepository(db)
	progressRepo := repository.NewProgressRepository(db)
	libraryRepo := repository.NewLibraryRepository(db)

	opStore := services.NewOTPStore(time.Duration(cfg.Auth.CodeExpiry) * time.Second)
	jwtService := services.NewJWTService(cfg.Auth.JWTSecret, 24*time.Hour)
	smtpClient := email.NewSMTPClient(email.SMTPConfig{
		Host:     cfg.Auth.SMTP.Host,
		Port:     cfg.Auth.SMTP.Port,
		Username: cfg.Auth.SMTP.Username,
		Password: cfg.Auth.SMTP.Password,
		From:     cfg.Auth.SMTP.From,
	})
	scanner := services.NewScannerService(libraryRepo, mediaRepo, cfg)
	streamer := services.NewStreamerService()

	authHandler := handlers.NewAuthHandler(userRepo, opStore, jwtService, smtpClient, cfg)
	mediaHandler := handlers.NewMediaHandler(mediaRepo, streamer)
	libraryHandler := handlers.NewLibraryHandler(libraryRepo, scanner)
	progressHandler := handlers.NewProgressHandler(progressRepo)

	app := fiber.New()

	auth := app.Group("/api/auth")
	auth.Post("/request-code", authHandler.RequestCode)
	auth.Post("/verify-code", authHandler.VerifyCode)

	api := app.Group("/api", middleware.AuthMiddleware(jwtService))

	api.Get("/auth/me", authHandler.Me)

	media := api.Group("/media")
	media.Get("", mediaHandler.List)
	media.Get("/:id", mediaHandler.Get)
	media.Post("", mediaHandler.Create)
	media.Put("/:id", mediaHandler.Update)
	media.Delete("/:id", mediaHandler.Delete)
	media.Get("/:id/stream", mediaHandler.Stream)

	library := api.Group("/libraries")
	library.Get("", libraryHandler.List)
	library.Post("", libraryHandler.Create)
	library.Put("/:id", libraryHandler.Update)
	library.Delete("/:id", libraryHandler.Delete)
	library.Post("/:id/scan", libraryHandler.Scan)

	progress := api.Group("/progress")
	progress.Get("", progressHandler.List)
	progress.Put("/:mediaId", progressHandler.Update)
	progress.Delete("/:mediaId", progressHandler.Delete)

	port := cfg.Server.Port
	if port == 0 {
		port = 8080
	}

	log.Printf("Flux Media Server starting on port %d", port)
	log.Fatal(app.Listen(fmt.Sprintf(":%d", port)))
}
