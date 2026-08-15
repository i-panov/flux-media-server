package app

import (
	"context"
	"database/sql"
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
	"github.com/valyala/fasthttp"

	"flux/internal/config"
	"flux/internal/email"
	"flux/internal/handlers"
	"flux/internal/middleware"
	"flux/internal/repository"
	"flux/internal/services"
)

// maxAPIBodySize caps request bodies for all non-upload endpoints (JSON API).
const maxAPIBodySize = 4 << 20 // 4 MB

// globalBodyLimit — запасной глобальный потолок размера тела запроса для
// fasthttp. Реальный per-route лимит задаёт HeaderReceived (см. ниже):
// не-upload роуты ограничены maxAPIBodySize, upload/cover — MaxUploadSize.
// Этот запасной лимит применяется только если HeaderReceived по какой-то
// причине не сработал, поэтому он не должен быть ниже maxAPIBodySize.
const globalBodyLimit = 25 << 20 // 25 MB

// maxConcurrentConnections — потолок одновременных соединений (fasthttp
// Concurrency). Ограничивает число параллельно буферизуемых тел.
const maxConcurrentConnections = 256

// refreshTokensPurgeInterval — периодичность очистки истёкших refresh-токенов.
const refreshTokensPurgeInterval = 24 * time.Hour

// Пути upload/cover: используются и в body-size middleware, и при
// регистрации роутов ниже — держать синхронными.
const (
	apiMediaRoute     = "/api/media"
	uploadRouteSuffix = "/upload" // POST /api/media/upload
	coverRouteSuffix  = "/cover"  // PUT /api/media/:id/cover
)

// isUploadPath определяет запросы, которым разрешены большие тела
// (multipart upload и смена обложки). Единая точка для HeaderReceived
// (лимит применяется до чтения тела) и body-size middleware.
func isUploadPath(method, path string) bool {
	if path == apiMediaRoute+uploadRouteSuffix {
		return method == fiber.MethodPost
	}
	return method == fiber.MethodPut &&
		strings.HasPrefix(path, apiMediaRoute+"/") && strings.HasSuffix(path, coverRouteSuffix)
}

// App holds all application dependencies and the Fiber instance.
type App struct {
	Fiber       *fiber.App
	Config      *config.Config
	OTPStore    *services.OTPStore
	Watcher     *services.WatcherService
	Version     string
	sqlDB       *sql.DB
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

	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("get sql db: %w", err)
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

	// На error-путях освобождаем созданные ресурсы: горутину OTPStore и
	// подключение к БД. ok=true ставится перед успешным возвратом.
	ok := false
	defer func() {
		if !ok {
			otpStore.Stop()
			_ = sqlDB.Close()
		}
	}()

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
		ReadTimeout: 10 * time.Second,
		// WriteTimeout: 0 — fasthttp ставит write-deadline на весь ответ
		// один раз, поэтому лимит 10 мин обрывал бы стримы/скачивания
		// больших файлов. Защита от slowloris остаётся на ReadTimeout и
		// IdleTimeout.
		WriteTimeout: 0,
		IdleTimeout:  60 * time.Second,
		// Запасной глобальный лимит тела: реальные per-route лимиты задаёт
		// HeaderReceived (см. выше), это значение — только fallback.
		BodyLimit: int(min(cfg.Server.MaxUploadSize, globalBodyLimit)),
		// Ограничение одновременных соединений против исчерпания памяти.
		Concurrency: maxConcurrentConnections,
		ErrorHandler: func(c *fiber.Ctx, err error) error {
			code := fiber.StatusInternalServerError
			if e, ok := err.(*fiber.Error); ok {
				code = e.Code
			}
			if code == fiber.StatusRequestEntityTooLarge {
				return c.Status(code).JSON(fiber.Map{
					"error": "Request body too large",
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
	fiberApp.Use(middleware.SecurityHeaders())
	fiberApp.Use(logger.New())

	// Per-route лимиты тела: fasthttp буферизует тело целиком ДО вызова
	// хендлеров, но HeaderReceived позволяет выбрать лимит по одним лишь
	// заголовкам — до начала чтения тела. Обычные роуты ограничены
	// maxAPIBodySize (защита от DoS), upload/cover получают настоящий
	// MaxUploadSize. Остаточный риск (атакующий шлёт большие тела на
	// upload-роут до проверки auth) ограничен Concurrency и upload rate
	// limiter'ом — это плата за поддержку больших загрузок.
	fiberApp.Server().HeaderReceived = func(h *fasthttp.RequestHeader) fasthttp.RequestConfig {
		var u fasthttp.URI
		_ = u.Parse(nil, h.RequestURI()) // при ошибке path пуст → лимит 4 МБ (безопасный дефолт)
		limit := maxAPIBodySize
		if isUploadPath(string(h.Method()), string(u.Path())) {
			limit = int(cfg.Server.MaxUploadSize)
		}
		return fasthttp.RequestConfig{MaxRequestBodySize: limit}
	}

	// fasthttp буферизует тело запроса в памяти; реальные лимиты задаёт
	// HeaderReceived (см. выше) — этот middleware остаётся страховкой для
	// chunked/streamed запросов (ContentLength == -1), которые fasthttp
	// буферизует без Content-Length.
	// Исключения — по зарегистрированным путям (см. константы):
	// POST /api/media/upload и PUT /api/media/:id/cover (multipart).
	fiberApp.Use(func(c *fiber.Ctx) error {
		if isUploadPath(c.Method(), c.Path()) {
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

	// Upload limiter — upload-запросы тяжёлые (multipart, ffprobe), их
	// нужно лимитировать отдельно от auth-роутов.
	uploadRateLimiter := limiter.New(limiter.Config{
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
	media.Post(uploadRouteSuffix, requireAdmin, uploadRateLimiter, uploadHandler.Upload)
	media.Post("/check-hash", mediaHandler.CheckHash)
	media.Put("/:id", requireAdmin, mediaHandler.Update)
	media.Delete("/:id", requireAdmin, mediaHandler.Delete)
	media.Get("/:id/stream", mediaHandler.Stream)
	media.Get("/:id/thumb", thumbHandler.Get)
	media.Get("/:id/cover", thumbHandler.GetCover)
	media.Put("/:id"+coverRouteSuffix, requireAdmin, thumbHandler.UploadCover)

	progress := api.Group("/progress")
	progress.Get("", progressHandler.List)
	progress.Put("/:mediaId", progressHandler.Update)
	progress.Delete("/:mediaId", progressHandler.Delete)

	metadataGroup := api.Group("/metadata")
	metadataGroup.Get("/search", metadataHandler.Search)
	metadataGroup.Post("/:mediaId/refresh", requireAdmin, metadataHandler.Refresh)
	metadataGroup.Put("/:mediaId", requireAdmin, metadataHandler.Update)

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
		ticker := time.NewTicker(refreshTokensPurgeInterval)
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

	ok = true
	return &App{
		Fiber:       fiberApp,
		Config:      cfg,
		OTPStore:    otpStore,
		Watcher:     watcherService,
		Version:     version,
		sqlDB:       sqlDB,
		cleanupStop: cleanupStop,
	}, nil
}

// Listen starts the HTTP server on the configured host and port.
func (a *App) Listen() error {
	host := a.Config.Server.Host
	port := a.Config.Server.Port
	log.Printf("Flux Media Server %s starting on %s:%d", a.Version, host, port)
	return a.Fiber.Listen(fmt.Sprintf("%s:%d", host, port))
}

// getClientIP returns the client IP for rate limiting. We deliberately do
// NOT trust X-Forwarded-For / X-Real-IP headers because an attacker can
// trivially spoof them, obtaining a unique key per request and bypassing
// the rate limiter. Note: this also means that behind a reverse proxy all
// clients share the proxy's IP; TrustedProxies is not configurable yet.
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

// Shutdown gracefully stops the application: background workers, the HTTP
// server and the database. ctx bounds the time spent waiting for in-flight
// requests; when omitted, context.Background() is used.
func (a *App) Shutdown(ctx ...context.Context) error {
	shutdownCtx := context.Background()
	if len(ctx) > 0 {
		shutdownCtx = ctx[0]
	}

	a.cleanupOnce.Do(func() {
		close(a.cleanupStop)
	})
	if a.Watcher != nil {
		a.Watcher.Stop()
	}
	a.OTPStore.Stop()

	err := a.Fiber.ShutdownWithContext(shutdownCtx)
	if a.sqlDB != nil {
		if dbErr := a.sqlDB.Close(); dbErr != nil && err == nil {
			err = dbErr
		}
	}
	return err
}
