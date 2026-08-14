package app

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/limiter"
	"github.com/gofiber/fiber/v2/middleware/logger"
	fiberrecover "github.com/gofiber/fiber/v2/middleware/recover"

	"flux/internal/config"
	"flux/internal/email"
	"flux/internal/handlers"
	"flux/internal/middleware"
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
	cleanupOnce sync.Once
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
	favRepo := repository.NewFavoriteRepository(db)
	colRepo := repository.NewCollectionRepository(db)
	colItemRepo := repository.NewCollectionItemRepository(db)
	lyricsRepo := repository.NewLyricsRepository(db)
	refreshTokenRepo := repository.NewRefreshTokenRepository(db)
	artistRepo := repository.NewArtistRepository(db)

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

	scanner := services.NewScannerService(mediaRepo, cfg)
	streamer := services.NewStreamerService(cfg)
	thumbSvc := services.NewThumbnailService(cfg.Media.ThumbnailPath)

	// File watcher for automatic library monitoring.
	var watcherService *services.WatcherService
	if cfg.Scanner.WatchEnabled {
		watcherService = services.NewWatcherService(scanner)
	}

	// Handlers
	authHandler := handlers.NewAuthHandler(userRepo, refreshTokenRepo, otpStore, jwtService, smtpClient, cfg)
	mediaHandler := handlers.NewMediaHandler(mediaRepo, streamer, thumbSvc)
	thumbHandler := handlers.NewThumbHandler(mediaRepo, thumbSvc)
	uploadHandler := handlers.NewUploadHandler(mediaRepo, scanner, thumbSvc, cfg.Media, handlers.UploadConfig{
		MaxFileSize: cfg.Server.MaxUploadSize,
	})

	// Ensure media directories exist.
	if err := os.MkdirAll(cfg.Media.VideoPath, 0755); err != nil {
		return nil, fmt.Errorf("create video dir: %w", err)
	}
	if err := os.MkdirAll(cfg.Media.AudioPath, 0755); err != nil {
		return nil, fmt.Errorf("create audio dir: %w", err)
	}

	progressHandler := handlers.NewProgressHandler(progressRepo, mediaRepo)
	metadataHandler := handlers.NewMetadataHandler(mediaRepo)
	favoriteHandler := handlers.NewFavoriteHandler(favRepo, mediaRepo, artistRepo)
	collectionHandler := handlers.NewCollectionHandler(colRepo, colItemRepo, mediaRepo)
	lyricsHandler := handlers.NewLyricsHandler(lyricsRepo, mediaRepo)
	artistHandler := handlers.NewArtistHandler(artistRepo)

	// Fiber app
	fiberApp := fiber.New(fiber.Config{
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Minute,
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
	fiberApp.Use(fiberrecover.New())
	fiberApp.Use(logger.New())

	// fasthttp buffers the whole request body in memory. The global BodyLimit
	// equals the max upload size (potentially gigabytes), so cap the body size
	// for all non-upload routes to prevent memory exhaustion.
	// ContentLength == -1 means chunked/streamed — fasthttp will buffer the
	// whole body anyway, so we reject those outright for non-upload routes.
	// Исключения задаются по конкретным зарегистрированным путям:
	// POST /api/media/upload и PUT /api/media/:id/cover (multipart).
	fiberApp.Use(func(c *fiber.Ctx) error {
		p := c.Path()
		if p == "/api/media/upload" {
			return c.Next()
		}
		if c.Method() == fiber.MethodPut &&
			strings.HasPrefix(p, "/api/media/") && strings.HasSuffix(p, "/cover") {
			return c.Next()
		}
		if c.Request().Header.ContentLength() == -1 {
			return c.Status(fiber.StatusRequestEntityTooLarge).JSON(fiber.Map{
				"error": "Chunked/streamed request body not allowed",
			})
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

	// Health check — единственный канонический эндпоинт /api/health
	// (его используют фронтенд и Dockerfile HEALTHCHECK).
	fiberApp.Get("/api/health", handlers.HealthCheck)

	// Auth rate limiter — parameters from config.
	authRateLimiter := limiter.New(limiter.Config{
		Max:        cfg.RateLimiter.Max,
		Expiration: time.Duration(cfg.RateLimiter.Expiration) * time.Second,
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
	media.Delete("/:id", requireAdmin, mediaHandler.Delete)
	media.Get("/:id/stream", mediaHandler.Stream)
	media.Get("/:id/thumb", thumbHandler.Get)
	media.Get("/:id/cover", thumbHandler.GetCover)
	media.Put("/:id/cover", requireAdmin, thumbHandler.UploadCover)

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

	// Artists
	api.Get("/artists", artistHandler.List)

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
		var paths []string
		for _, mp := range cfg.Media.MediaPaths() {
			if mp.Path != "" {
				paths = append(paths, mp.Path)
			}
		}
		if len(paths) > 0 {
			if err := watcherService.StartWithPaths(paths); err != nil {
				log.Printf("Warning: failed to start file watcher: %v", err)
			}
		}
	}

	// Periodically purge expired refresh tokens so the table does not grow
	// unboundedly.
	cleanupStop := make(chan struct{})
	goSafe(func() {
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
	})

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

// getClientIP returns the client IP for rate limiting. We deliberately do
// NOT trust X-Forwarded-For / X-Real-IP headers because an attacker can
// trivially spoof them, obtaining a unique key per request and bypassing
// the rate limiter. If the server runs behind a reverse proxy, configure
// Fiber's TrustedProxies instead.
func getClientIP(c *fiber.Ctx) string {
	return c.IP()
}

// goSafe runs fn in a goroutine, recovering from panics so a bug in a
// background task cannot crash the whole process.
func goSafe(fn func()) {
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("panic in background goroutine: %v", r)
			}
		}()
		fn()
	}()
}

// Shutdown gracefully stops the application.
func (a *App) Shutdown() {
	if a.Watcher != nil {
		a.Watcher.Stop()
	}
	a.OTPStore.Stop()
	a.cleanupOnce.Do(func() {
		close(a.cleanupStop)
	})
}
