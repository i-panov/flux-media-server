package app

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/limiter"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"

	"flux/internal/config"
	"flux/internal/email"
	"flux/internal/handlers"
	"flux/internal/middleware"
	"flux/internal/repository"
	"flux/internal/services"
)

// App holds all application dependencies and the Fiber instance.
type App struct {
	Fiber      *fiber.App
	Config     *config.Config
	OTPStore   *services.OTPStore
	Watcher    *services.WatcherService
	Version    string
}

// New creates a new App with all dependencies wired up.
func New(cfg *config.Config, version string) (*App, error) {
	db, err := repository.InitDB(cfg.Database.Path)
	if err != nil {
		return nil, fmt.Errorf("init database: %w", err)
	}

	if err := repository.AutoMigrate(db); err != nil {
		return nil, fmt.Errorf("migrate database: %w", err)
	}

	// Repositories
	userRepo := repository.NewUserRepository(db)
	mediaRepo := repository.NewMediaRepository(db)
	progressRepo := repository.NewProgressRepository(db)
	libraryRepo := repository.NewLibraryRepository(db)

	// Services
	otpStore := services.NewOTPStore(
		time.Duration(cfg.Auth.CodeExpiry)*time.Second,
		cfg.Auth.CodeLength,
		cfg.Auth.MaxOTPEntries,
	)

	jwtExpiry := time.Duration(cfg.Auth.JWTExpiry) * time.Hour
	if jwtExpiry == 0 {
		jwtExpiry = 24 * time.Hour
	}
	jwtService := services.NewJWTService(cfg.Auth.JWTSecret, jwtExpiry)

	smtpClient := email.NewSMTPClient(email.SMTPConfig{
		Host:     cfg.Auth.SMTP.Host,
		Port:     cfg.Auth.SMTP.Port,
		Username: cfg.Auth.SMTP.Username,
		Password: cfg.Auth.SMTP.Password,
		From:     cfg.Auth.SMTP.From,
	})

	scanner := services.NewScannerService(libraryRepo, mediaRepo, cfg)
	streamer := services.NewStreamerService(libraryRepo)
	thumbSvc := services.NewThumbnailService(cfg.Media.ThumbnailPath)

	// File watcher for automatic library monitoring.
	var watcherService *services.WatcherService
	var watcherInterface services.WatcherInterface
	if cfg.Scanner.WatchEnabled {
		watcherService = services.NewWatcherService(scanner)
		watcherInterface = watcherService
	}

	// Handlers
	authHandler := handlers.NewAuthHandler(userRepo, otpStore, jwtService, smtpClient, cfg)
	mediaHandler := handlers.NewMediaHandler(mediaRepo, streamer)
	thumbHandler := handlers.NewThumbHandler(mediaRepo, thumbSvc)
	uploadHandler := handlers.NewUploadHandler(libraryRepo, mediaRepo, scanner, handlers.UploadConfig{
		AllowedExtensions: cfg.Media.AllowedExtensions,
		MaxFileSize:       2 << 30, // 2GB
	})
	libraryHandler := handlers.NewLibraryHandler(libraryRepo, scanner, watcherInterface)
	progressHandler := handlers.NewProgressHandler(progressRepo)
	metadataHandler := handlers.NewMetadataHandler(mediaRepo)

	// Fiber app
	fiberApp := fiber.New()
	fiberApp.Use(recover.New())
	fiberApp.Use(logger.New())

	allowOrigins := cfg.Server.CORSOrigins
	if allowOrigins == "" {
		allowOrigins = "*"
	}
	fiberApp.Use(cors.New(cors.Config{
		AllowOrigins:     allowOrigins,
		AllowMethods:     "GET, POST, PUT, DELETE, OPTIONS",
		AllowHeaders:     "Origin, Content-Type, Accept, Authorization",
		AllowCredentials: allowOrigins != "*",
	}))

	// Health check
	fiberApp.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"status": "ok", "version": version})
	})

	// Auth rate limiter
	authRateLimiter := limiter.New(limiter.Config{
		Max:        10,
		Expiration: time.Minute,
		KeyGenerator: func(c *fiber.Ctx) string {
			return c.IP()
		},
		LimitReached: func(c *fiber.Ctx) error {
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error": "Rate limit exceeded, please try again later",
			})
		},
	})

	// Public auth routes
	auth := fiberApp.Group("/api/auth")
	auth.Post("/request-code", authRateLimiter, authHandler.RequestCode)
	auth.Post("/verify-code", authHandler.VerifyCode)

	// Protected routes
	api := fiberApp.Group("/api", middleware.AuthMiddleware(jwtService))

	api.Get("/auth/me", authHandler.Me)

	media := api.Group("/media")
	media.Get("", mediaHandler.List)
	media.Get("/:id", mediaHandler.Get)
	media.Post("", mediaHandler.Create)
	media.Post("/upload", uploadHandler.Upload)
	media.Put("/:id", mediaHandler.Update)
	media.Delete("/:id", mediaHandler.Delete)
	media.Get("/:id/stream", mediaHandler.Stream)
	media.Get("/:id/thumb", thumbHandler.Get)

	library := api.Group("/libraries")
	library.Get("", libraryHandler.List)
	library.Post("", libraryHandler.Create)
	library.Put("/:id", libraryHandler.Update)
	library.Delete("/:id", libraryHandler.Delete)
	library.Post("/:id/scan", libraryHandler.Scan)
	library.Get("/:id/scan-status", libraryHandler.ScanStatus)

	progress := api.Group("/progress")
	progress.Get("", progressHandler.List)
	progress.Put("/:mediaId", progressHandler.Update)
	progress.Delete("/:mediaId", progressHandler.Delete)

	metadataGroup := api.Group("/metadata")
	metadataGroup.Get("/search", metadataHandler.Search)
	metadataGroup.Post("/:mediaId/refresh", metadataHandler.Refresh)
	metadataGroup.Put("/:mediaId", metadataHandler.Update)

	// Start file watcher if enabled.
	if watcherService != nil {
		libraries, err := libraryRepo.FindAll(context.Background())
		if err == nil {
			var paths []string
			for _, lib := range libraries {
				if lib.Enabled {
					paths = append(paths, lib.Path)
				}
			}
			if len(paths) > 0 {
				if err := watcherService.StartWithPaths(paths); err != nil {
					log.Printf("Warning: failed to start file watcher: %v", err)
				}
			}
		}
	}

	return &App{
		Fiber:    fiberApp,
		Config:   cfg,
		OTPStore: otpStore,
		Watcher:  watcherService,
		Version:  version,
	}, nil
}

// Listen starts the HTTP server on the configured port.
func (a *App) Listen() error {
	port := a.Config.Server.Port
	if port == 0 {
		port = 8080
	}
	log.Printf("Flux Media Server %s starting on port %d", a.Version, port)
	return a.Fiber.Listen(fmt.Sprintf(":%d", port))
}

// Shutdown gracefully stops the application.
func (a *App) Shutdown() {
	if a.Watcher != nil {
		a.Watcher.Stop()
	}
	a.OTPStore.Stop()
}
