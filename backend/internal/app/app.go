package app

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"
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
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

// maxAPIBodySize caps request bodies for all non-upload endpoints (JSON API).
const maxAPIBodySize = 4 << 20 // 4 MB

// App holds all application dependencies and the Fiber instance.
type App struct {
	Fiber       *fiber.App
	Config      *config.Config
	OTPStore    *services.OTPStore
	Watcher     *services.WatcherService
	Version     string
	cleanupStop chan struct{}
}

// New creates a new App with all dependencies wired up.
func New(cfg *config.Config, version string) (*App, error) {
	db, err := repository.InitDB(cfg.Database.Path, cfg.Server.Debug)
	if err != nil {
		return nil, fmt.Errorf("init database: %w", err)
	}

	if err := repository.RunMigrations(db); err != nil {
		return nil, fmt.Errorf("run migrations: %w", err)
	}

	if err := repository.AutoMigrate(db); err != nil {
		return nil, fmt.Errorf("migrate database: %w", err)
	}

	// Repositories
	userRepo := repository.NewUserRepository(db)
	mediaRepo := repository.NewMediaRepository(db)
	progressRepo := repository.NewProgressRepository(db)
	libraryRepo := repository.NewLibraryRepository(db)
	favRepo := repository.NewFavoriteRepository(db)
	colRepo := repository.NewCollectionRepository(db)
	colItemRepo := repository.NewCollectionItemRepository(db)
	lyricsRepo := repository.NewLyricsRepository(db)
	refreshTokenRepo := repository.NewRefreshTokenRepository(db)

	// Services
	otpStore := services.NewOTPStore(
		time.Duration(cfg.Auth.CodeExpiry)*time.Second,
		cfg.Auth.CodeLength,
		cfg.Auth.MaxOTPEntries,
	)

	jwtService := services.NewJWTService(
		cfg.Auth.JWTSecret,
		time.Duration(cfg.Auth.JWTExpiry)*time.Hour,
		time.Duration(cfg.Auth.RefreshExpiry)*time.Hour,
	)

	smtpClient := email.NewSMTPClient(email.SMTPConfig{
		Host:        cfg.Auth.SMTP.Host,
		Port:        cfg.Auth.SMTP.Port,
		Username:    cfg.Auth.SMTP.Username,
		Password:    cfg.Auth.SMTP.Password,
		From:        cfg.Auth.SMTP.From,
		RequireTLS:  cfg.Auth.SMTP.RequireTLS,
		ImplicitTLS: cfg.Auth.SMTP.ImplicitTLS,
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
	authHandler := handlers.NewAuthHandler(userRepo, refreshTokenRepo, otpStore, jwtService, smtpClient, cfg)
	mediaHandler := handlers.NewMediaHandler(mediaRepo, streamer)
	thumbHandler := handlers.NewThumbHandler(mediaRepo, thumbSvc)
	uploadHandler := handlers.NewUploadHandler(libraryRepo, mediaRepo, scanner, thumbSvc, handlers.UploadConfig{
		MaxFileSize: cfg.Server.MaxUploadSize,
	})
	libraryHandler := handlers.NewLibraryHandler(libraryRepo, scanner, watcherInterface, cfg)

	// Auto-create default libraries if they don't exist.
	if _, err := libraryRepo.FindByPath(context.Background(), cfg.Media.VideoPath); err != nil {
		libraryRepo.Create(context.Background(), &models.MediaLibrary{
			Name:    "Video",
			Path:    cfg.Media.VideoPath,
			Type:    "video",
			Enabled: true,
		})
		os.MkdirAll(cfg.Media.VideoPath, 0755)
	}
	if _, err := libraryRepo.FindByPath(context.Background(), cfg.Media.AudioPath); err != nil {
		libraryRepo.Create(context.Background(), &models.MediaLibrary{
			Name:    "Audio",
			Path:    cfg.Media.AudioPath,
			Type:    "audio",
			Enabled: true,
		})
		os.MkdirAll(cfg.Media.AudioPath, 0755)
	}
	progressHandler := handlers.NewProgressHandler(progressRepo)
	metadataHandler := handlers.NewMetadataHandler(mediaRepo)
	favoriteHandler := handlers.NewFavoriteHandler(favRepo, mediaRepo)
	collectionHandler := handlers.NewCollectionHandler(colRepo, colItemRepo, mediaRepo)
	lyricsHandler := handlers.NewLyricsHandler(lyricsRepo)

	// Fiber app
	fiberApp := fiber.New(fiber.Config{
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 120 * time.Second,
		IdleTimeout:  60 * time.Second,
		BodyLimit:    int(cfg.Server.MaxUploadSize),
		ErrorHandler: func(c *fiber.Ctx, err error) error {
			code := fiber.StatusInternalServerError
			if e, ok := err.(*fiber.Error); ok {
				code = e.Code
			}
			if code == fiber.StatusRequestEntityTooLarge {
				return c.Status(code).JSON(fiber.Map{
					"error": fmt.Sprintf("File too large. Maximum upload size is %d MB", cfg.Server.MaxUploadSize/(1<<20)),
				})
			}
			if code >= fiber.StatusInternalServerError {
				// Do not leak internal error details (paths, DB errors) to clients.
				log.Printf("internal error: %v", err)
				return c.Status(code).JSON(fiber.Map{
					"error": "Internal server error",
				})
			}
			return c.Status(code).JSON(fiber.Map{
				"error": err.Error(),
			})
		},
	})
	fiberApp.Use(recover.New())
	fiberApp.Use(logger.New())

	// fasthttp buffers the whole request body in memory. The global BodyLimit
	// equals the max upload size (potentially gigabytes), so cap the body size
	// for all non-upload routes to prevent memory exhaustion.
	fiberApp.Use(func(c *fiber.Ctx) error {
		p := c.Path()
		// Allow multipart uploads for media upload and cover upload.
		if p == "/api/media/upload" || (c.Method() == "PUT" && strings.HasSuffix(p, "/cover")) {
			return c.Next()
		}
		if int64(c.Request().Header.ContentLength()) > maxAPIBodySize {
			return c.Status(fiber.StatusRequestEntityTooLarge).JSON(fiber.Map{
				"error": "Request body too large",
			})
		}
		return c.Next()
	})

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
	fiberApp.Get("/api/health", handlers.HealthCheck)
	fiberApp.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"status": "ok", "version": version})
	})

	// Auth rate limiter
	authRateLimiter := limiter.New(limiter.Config{
		Max:        10,
		Expiration: time.Minute,
		KeyGenerator: func(c *fiber.Ctx) string {
			return getClientIP(c)
		},
		LimitReached: func(c *fiber.Ctx) error {
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error": "Rate limit exceeded, please try again later",
			})
		},
	})

	// Public auth routes. All of them are rate-limited: verify-code without a
	// limiter would allow brute-forcing the 6-digit OTP within its TTL.
	auth := fiberApp.Group("/api/auth")
	auth.Post("/request-code", authRateLimiter, authHandler.RequestCode)
	auth.Post("/verify-code", authRateLimiter, authHandler.VerifyCode)
	auth.Post("/refresh", authRateLimiter, authHandler.Refresh)

	// Protected routes
	api := fiberApp.Group("/api", middleware.AuthMiddleware(jwtService))

	api.Get("/auth/me", authHandler.Me)
	api.Post("/auth/logout", authHandler.Logout)

	// Admin-only middleware for destructive/administrative operations.
	requireAdmin := middleware.RequireAdmin(userRepo)

	media := api.Group("/media")
	media.Get("", mediaHandler.List)
	media.Get("/:id", mediaHandler.Get)
	media.Post("", requireAdmin, mediaHandler.Create)
	media.Post("/upload", requireAdmin, uploadHandler.Upload)
	media.Post("/check-hash", mediaHandler.CheckHash)
	media.Put("/:id", requireAdmin, mediaHandler.Update)
	media.Delete("/:id", mediaHandler.Delete)
	media.Get("/:id/stream", mediaHandler.Stream)
	media.Get("/:id/thumb", thumbHandler.Get)
	media.Get("/:id/cover", thumbHandler.GetCover)
	media.Put("/:id/cover", requireAdmin, thumbHandler.UploadCover)

	library := api.Group("/libraries")
	library.Get("", libraryHandler.List)
	library.Post("", requireAdmin, libraryHandler.Create)
	library.Put("/:id", requireAdmin, libraryHandler.Update)
	library.Delete("/:id", requireAdmin, libraryHandler.Delete)
	library.Post("/:id/scan", requireAdmin, libraryHandler.Scan)
	library.Get("/:id/scan-status", libraryHandler.ScanStatus)

	progress := api.Group("/progress")
	progress.Get("", progressHandler.List)
	progress.Put("/:mediaId", progressHandler.Update)
	progress.Delete("/:mediaId", progressHandler.Delete)

	metadataGroup := api.Group("/metadata")
	metadataGroup.Get("/search", metadataHandler.Search)
	metadataGroup.Post("/:mediaId/refresh", metadataHandler.Refresh)
	metadataGroup.Put("/:mediaId", metadataHandler.Update)

	// Favorites
	api.Post("/media/:id/favorite", favoriteHandler.AddFavorite)
	api.Delete("/media/:id/favorite", favoriteHandler.RemoveFavorite)
	api.Get("/favorites", favoriteHandler.ListFavorites)
	api.Post("/favorites/artist", favoriteHandler.AddArtistFavorite)
	api.Delete("/favorites/artist", favoriteHandler.RemoveArtistFavorite)

	// Collections
	api.Post("/collections", collectionHandler.Create)
	api.Get("/collections", collectionHandler.List)
	api.Put("/collections/:id", collectionHandler.Update)
	api.Delete("/collections/:id", collectionHandler.Delete)
	api.Post("/collections/:id/items", collectionHandler.AddItem)
	api.Delete("/collections/:id/items/:mediaId", collectionHandler.RemoveItem)
	api.Get("/collections/:id/items", collectionHandler.ListItems)

	// Lyrics
	api.Get("/media/:id/lyrics", lyricsHandler.GetLyrics)
	api.Put("/media/:id/lyrics", lyricsHandler.UpsertLyrics)

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

	// Periodically purge expired refresh tokens so the table does not grow
	// unboundedly.
	cleanupStop := make(chan struct{})
	go func() {
		ticker := time.NewTicker(24 * time.Hour)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				if err := refreshTokenRepo.DeleteExpired(context.Background()); err != nil {
					log.Printf("purge expired refresh tokens: %v", err)
				}
			case <-cleanupStop:
				return
			}
		}
	}()

	return &App{
		Fiber:       fiberApp,
		Config:      cfg,
		OTPStore:    otpStore,
		Watcher:     watcherService,
		Version:     version,
		cleanupStop: cleanupStop,
	}, nil
}

// Listen starts the HTTP server on the configured host and port.
func (a *App) Listen() error {
	host := a.Config.Server.Host
	port := a.Config.Server.Port
	if port == 0 {
		port = 8080
	}
	log.Printf("Flux Media Server %s starting on %s:%d", a.Version, host, port)
	return a.Fiber.Listen(fmt.Sprintf("%s:%d", host, port))
}

// getClientIP extracts the real client IP from proxy headers, falling back
// to the direct connection address.
func getClientIP(c *fiber.Ctx) string {
	if ip := c.Get("X-Forwarded-For"); ip != "" {
		return ip
	}
	if ip := c.Get("X-Real-IP"); ip != "" {
		return ip
	}
	return c.IP()
}

// Shutdown gracefully stops the application.
func (a *App) Shutdown() {
	if a.Watcher != nil {
		a.Watcher.Stop()
	}
	a.OTPStore.Stop()
	if a.cleanupStop != nil {
		close(a.cleanupStop)
	}
}
