package app

import (
	"context"
	"database/sql"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/limiter"
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

// minUploadSpeedFloor — минимальная скорость заливки, из которой считаем
// ReadTimeout для upload-роутов: MaxUploadSize должен успеть залиться
// даже по медленной связи. Глобальные 10 секунд рвали соединение
// посреди больших файлов (клиент видел Connection reset by peer /
// Write failed). Slowloris через это окно не пролезет: upload-роуты
// требуют auth (requireAdmin), плюс Concurrency и rate limiter.
const minUploadSpeedFloor = 50 << 10 // 50 KB/s

// uploadReadTimeout — сколько даём на чтение тела загрузки: время
// прокачки MaxUploadSize на полу minUploadSpeedFloor плюс минута запаса
// на медленный старт. Нулевой/крошечный лимит — минимум 10 минут.
func uploadReadTimeout(maxUploadSize int64) time.Duration {
	const minTimeout = 10 * time.Minute
	if maxUploadSize <= 0 {
		return minTimeout
	}
	seconds := maxUploadSize/minUploadSpeedFloor + 60
	timeout := time.Duration(seconds) * time.Second
	if timeout < minTimeout {
		return minTimeout
	}
	return timeout
}

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
	if method == fiber.MethodPost &&
		strings.HasPrefix(path, "/api/artists/") &&
		strings.HasSuffix(path, "/cover") {
		return true
	}
	return method == fiber.MethodPut &&
		strings.HasPrefix(path, apiMediaRoute+"/") && strings.HasSuffix(path, coverRouteSuffix)
}

// App holds all application dependencies and the Fiber instance.
type App struct {
	Fiber        *fiber.App
	Config       *config.Config
	OTPStore     *services.OTPStore
	Watcher      *services.WatcherService
	UploadQueue  *services.UploadQueue
	ExtractQueue *services.ExtractService
	// TranscodeQueue — очередь нормализации видео из карантина.
	TranscodeQueue *services.TranscodeQueue
	Version        string
	sqlDB          *sql.DB
	cleanupStop    chan struct{}
	cleanupOnce    sync.Once
	scanner        *services.ScannerService
	// scanCancelFn отменяет фоновый первичный скан при Shutdown.
	// nil, если фоновый скан не был запущен.
	scanCancelFn context.CancelFunc
	// scanWG дожидается завершения фонового скана до закрытия БД.
	scanWG *sync.WaitGroup
	// backfillWG дожидается разовой заливки dimensions.
	backfillWG       *sync.WaitGroup
	dimensionsCancel context.CancelFunc
}

// Scanner возвращает сервис сканирования для консольного режима (-scan).
func (a *App) Scanner() *services.ScannerService {
	return a.scanner
}

// Option модифицирует поведение New.
type Option func(*options)

type options struct {
	// backgroundWorkers — запускать ли фоновых работников при старте:
	// первичный скан и файловый watcher.
	backgroundWorkers bool
}

// ConsoleMode отключает фоновых работников при старте (первичный скан и
// файловый watcher). Используется консольным режимом (-scan): фоновый скан
// гонялся бы с консольным за одну БД (консольный мог получить
// ErrScanInProgress), а watcher дублировал бы события консольного скана.
func ConsoleMode() Option {
	return func(o *options) {
		o.backgroundWorkers = false
	}
}

// New creates a new App with all dependencies wired up.
func New(cfg *config.Config, version string, opts ...Option) (*App, error) {
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
	deviceAuthRepo := repository.NewDeviceAuthRepository(db)
	artistRepo := repository.NewArtistRepository(db)
	taskRepo := repository.NewTranscodeTaskRepository(db)
	subRepo := repository.NewSubtitleRepository(db)
	settingRepo := repository.NewSettingRepository(db)

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
		RequireTLS:  cfg.Auth.SMTP.RequireTLS != nil && *cfg.Auth.SMTP.RequireTLS,
		ImplicitTLS: cfg.Auth.SMTP.ImplicitTLS,
	})

	scanner := services.NewScannerService(mediaRepo, cfg)
	streamer := services.NewStreamerService(cfg)
	thumbSvc := services.NewThumbnailService(cfg.Media.ThumbnailPath)

	// Дефолты новых секций: тесты обходят config.Load, где живут
	// основные дефолты, поэтому здесь те же значения (дублирование
	// осознанное — в одном месте их не собрать без рефакторинга Load).
	if cfg.Storage.OriginalsDir == "" {
		cfg.Storage.OriginalsDir = "./data/originals"
	}
	if cfg.Storage.TempDir == "" {
		cfg.Storage.TempDir = "./data/tmp"
	}
	crf := 20
	if cfg.Transcode.CRF != nil {
		crf = *cfg.Transcode.CRF
	}
	// Дефолты read-бюджета: тесты обходят config.Load, где живут основные
	// дефолты, поэтому здесь те же значения через общие константы.
	if cfg.RateLimiter.ReadMax == 0 {
		cfg.RateLimiter.ReadMax = config.DefaultReadMax
	}
	if cfg.RateLimiter.ReadExpiration == 0 {
		cfg.RateLimiter.ReadExpiration = config.DefaultReadExpiration
	}

	// Ensure media directories exist.
	if err := os.MkdirAll(cfg.Media.VideoPath, 0755); err != nil {
		return nil, fmt.Errorf("create video dir: %w", err)
	}
	if err := os.MkdirAll(cfg.Media.AudioPath, 0755); err != nil {
		return nil, fmt.Errorf("create audio dir: %w", err)
	}
	if err := os.MkdirAll(cfg.Storage.OriginalsDir, 0755); err != nil {
		return nil, fmt.Errorf("create originals dir: %w", err)
	}
	if err := os.MkdirAll(cfg.Storage.TempDir, 0755); err != nil {
		return nil, fmt.Errorf("create temp dir: %w", err)
	}
	// Каталоги контента не должны пересекаться: иначе сканер
	// проиндексирует карантин как библиотеку, а чистка удалит не то.
	// Fail fast с понятной ошибкой вместо тихих дублей.
	contentDirs := map[string]string{
		"media.video_path":      cfg.Media.VideoPath,
		"media.audio_path":      cfg.Media.AudioPath,
		"storage.originals_dir": cfg.Storage.OriginalsDir,
		"storage.temp_dir":      cfg.Storage.TempDir,
	}
	// image_path необязателен в конфиге (config.Load подставляет дефолт),
	// но тесты и встраиваемые конфиги могут его не задавать.
	if cfg.Media.ImagePath != "" {
		contentDirs["media.image_path"] = cfg.Media.ImagePath
	}
	if err := services.ValidateContentDirs(contentDirs); err != nil {
		return nil, fmt.Errorf("validate content dirs: %w", err)
	}
	if cfg.Media.ImagePath != "" {
		if err := os.MkdirAll(cfg.Media.ImagePath, 0755); err != nil {
			return nil, fmt.Errorf("create image dir: %w", err)
		}
	}

	// Очередь нормализации видео: один воркер (ffmpeg тяжёлый),
	// задания в БД (переживают рестарт).
	transcodeQueue := services.NewTranscodeQueue(
		context.Background(),
		services.TranscodeWorkerConfig{
			CRF:             crf,
			Preset:          cfg.Transcode.Preset,
			MaxHeight:       cfg.Transcode.MaxHeight,
			EstimateFactor:  cfg.Transcode.EstimateFactor,
			MaxAttempts:     cfg.Transcode.MaxAttempts,
			LibraryVideoDir: cfg.Media.VideoPath,
			OriginalsDir:    cfg.Storage.OriginalsDir,
			TempDir:         cfg.Storage.TempDir,
			AutoCleanup:     cfg.Storage.AutoCleanupOriginals,
		},
		taskRepo,
		mediaRepo,
		subRepo,
		thumbSvc,
		services.NewSystemFFmpegRunner(),
	)
	if n, err := transcodeQueue.RequeueInterrupted(context.Background()); err != nil {
		log.Printf("transcode: requeue interrupted: %v", err)
	} else if n > 0 {
		log.Printf("transcode: requeued %d interrupted tasks", n)
	}

	// Персистентная настройка авточистки перекрывает конфиг: админка
	// меняет её без рестарта. Ошибка чтения не фатальна — работаем на
	// значении из YAML (config остаётся fallback'ом).
	if enabled, ok, err := settingRepo.GetBool(context.Background(), repository.SettingAutoCleanupOriginals); err != nil {
		log.Printf("settings: read %s, using config fallback: %v", repository.SettingAutoCleanupOriginals, err)
	} else if ok {
		transcodeQueue.SetAutoCleanup(enabled)
	}

	// Фоновая очередь обработки загрузок: POST /upload сохраняет файл и
	// отвечает 202, хэш/ffprobe/ffmpeg выполняют воркеры очереди.
	// Строки заданий персистентны: рестарт поднимает незавершённые
	// обратно в очередь.
	uploadQueue := services.NewUploadQueue(context.Background(), mediaRepo, repository.NewUploadTaskRepository(db), thumbSvc,
		services.DefaultUploadQueueWorkers, services.DefaultUploadQueueLimit)

	// File watcher for automatic library monitoring.
	var watcherService *services.WatcherService
	if cfg.Scanner.WatchEnabled {
		watcherService = services.NewWatcherService(scanner)
	}

	// Handlers
	authHandler := handlers.NewAuthHandler(userRepo, refreshTokenRepo, deviceAuthRepo, otpStore, jwtService, smtpClient, cfg)
	mediaHandler := handlers.NewMediaHandler(mediaRepo, streamer, thumbSvc)
	thumbHandler := handlers.NewThumbHandler(mediaRepo, thumbSvc)
	uploadHandler := handlers.NewUploadHandler(mediaRepo, uploadQueue, transcodeQueue, cfg.Media, cfg.Storage, handlers.UploadConfig{
		MaxFileSize: cfg.Server.MaxUploadSize,
	})
	transcodeHandler := handlers.NewTranscodeHandler(mediaRepo, transcodeQueue)
	subsHandler := handlers.NewSubsHandler(mediaRepo, subRepo, cfg.Media)
	adminHandler := handlers.NewAdminHandler(mediaRepo, taskRepo, transcodeQueue, cfg.Storage, cfg.Media, userRepo, settingRepo)
	// Очередь извлечения аудио из видео: отдельный воркер (ffmpeg тяжёлый),
	// механика статусов — как у загрузок. Строки заданий персистентны:
	// рестарт поднимает незавершённые обратно в очередь.
	extractQueue := services.NewExtractService(
		context.Background(),
		mediaRepo,
		repository.NewExtractTaskRepository(db),
		thumbSvc,
		cfg.Media.AudioPath,
		services.DefaultExtractQueueWorkers,
		services.DefaultExtractQueueLimit,
	)
	extractHandler := handlers.NewExtractHandler(mediaRepo, extractQueue)

	progressHandler := handlers.NewProgressHandler(progressRepo, mediaRepo)
	metadataHandler := handlers.NewMetadataHandler(mediaRepo)
	favoriteHandler := handlers.NewFavoriteHandler(favRepo, mediaRepo, artistRepo)
	collectionHandler := handlers.NewCollectionHandler(colRepo, colItemRepo, mediaRepo)
	trashHandler := handlers.NewTrashHandler(mediaRepo, colRepo, streamer, thumbSvc, subRepo)
	lyricsHandler := handlers.NewLyricsHandler(lyricsRepo, mediaRepo)
	artistHandler := handlers.NewArtistHandler(artistRepo, cfg.Media.ThumbnailPath)

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

	// Доверенные прокси парсим один раз: X-Forwarded-For принимаем
	// только от них, иначе клиент подделает IP и обойдёт лимитер.
	// Нужно и лимитерам, и access-логгеру — поэтому вычисляем до них.
	trustedProxies := parseTrustedProxies(cfg.Server.TrustedProxies)
	clientKey := func(c *fiber.Ctx) string {
		return getClientIP(c, trustedProxies)
	}

	// Свой access-логгер вместо middleware/logger: тот пишет c.IP(), то есть
	// IP прокси (шлюз docker-бриджа), потому что EnableTrustedProxyCheck не
	// включён — доверять X-Forwarded-For целиком нельзя (Fiber берёт самый
	// левый адрес, который клиент подставляет сам). Здесь IP берётся через
	// getClientIP, формат строки сохранён как у Fiber.
	fiberApp.Use(requestLogger(os.Stdout, clientKey))

	// Per-route лимиты тела: fasthttp буферизует тело запроса целиком ДО
	// вызова хендлеров (в памяти, O(size) на соединение — см. комментарий
	// к max_upload_size в config.example.yaml), но HeaderReceived позволяет
	// выбрать лимит по одним лишь заголовкам — до начала чтения тела.
	// Обычные роуты ограничены maxAPIBodySize (защита от DoS), upload/cover
	// получают настоящий MaxUploadSize. Остаточный риск (атакующий шлёт
	// большие тела на upload-роут до проверки auth) ограничен Concurrency
	// и upload rate limiter'ом — это плата за поддержку больших загрузок.
	//
	// ReadTimeout тоже per-route: глобальные 10 с режут ЧТЕНИЕ ТЕЛА
	// целиком, и заливка большого файла обрывалась на середине —
	// клиент видел Connection reset by peer / Write failed.
	// До чтения тела проверяем access-токен для upload/cover: иначе
	// неаутентифицированный клиент может держать соединение с телом до
	// MaxUploadSize часами. Валидному клиенту оставляем большой лимит,
	// но с разумным потолком времени.
	uploadAuthorized := func(h *fasthttp.RequestHeader) bool {
		token := ""
		if auth := string(h.Peek("Authorization")); auth != "" {
			parts := strings.SplitN(auth, " ", 2)
			if len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
				token = parts[1]
			}
		}
		if token == "" {
			for _, part := range strings.Split(string(h.Peek("Cookie")), ";") {
				key, value, found := strings.Cut(strings.TrimSpace(part), "=")
				if found && key == middleware.CookieAccessToken {
					token = value
					break
				}
			}
		}
		if token == "" {
			return false
		}
		claims, err := jwtService.ValidateToken(token)
		if err != nil {
			return false
		}
		// Большой upload-лимит — только админам: requireAdmin выполняется
		// после чтения тела, поэтому роль проверяем здесь.
		user, err := userRepo.FindByID(context.Background(), claims.UserID)
		return err == nil && user.IsAdmin
	}
	fiberApp.Server().HeaderReceived = func(h *fasthttp.RequestHeader) fasthttp.RequestConfig {
		var u fasthttp.URI
		_ = u.Parse(nil, h.RequestURI()) // при ошибке path пуст → лимит 4 МБ (безопасный дефолт)
		if isUploadPath(string(h.Method()), string(u.Path())) {
			if !uploadAuthorized(h) {
				return fasthttp.RequestConfig{
					MaxRequestBodySize: maxAPIBodySize,
					ReadTimeout:        30 * time.Second,
				}
			}
			return fasthttp.RequestConfig{
				MaxRequestBodySize: int(cfg.Server.MaxUploadSize),
				ReadTimeout:        uploadReadTimeout(cfg.Server.MaxUploadSize),
			}
		}
		return fasthttp.RequestConfig{MaxRequestBodySize: maxAPIBodySize}
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
	// (его используют фронтенд и Dockerfile HEALTHCHECK). Версия внутри —
	// для сверки свежести бэкенда из приложения (Настройки → О приложении).
	fiberApp.Get("/api/health", func(c *fiber.Ctx) error {
		return c.Status(fiber.StatusOK).JSON(fiber.Map{
			"status":  "ok",
			"version": version,
		})
	})

	// Auth rate limiter — parameters from config.
	authRateLimiter := limiter.New(limiter.Config{
		Max:          cfg.RateLimiter.Max,
		Expiration:   time.Duration(cfg.RateLimiter.Expiration) * time.Second,
		KeyGenerator: clientKey,
		LimitReached: func(c *fiber.Ctx) error {
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error": "Rate limit exceeded, please try again later",
			})
		},
	})

	// Device-code poll идёт каждые 3 секунды, поэтому общий auth-лимит
	// (10/мин) его бы душил. 120/мин хватает нескольким ТВ за одним IP.
	deviceRateLimiter := limiter.New(limiter.Config{
		Max:          120,
		Expiration:   time.Minute,
		KeyGenerator: clientKey,
		LimitReached: func(c *fiber.Ctx) error {
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error": "Rate limit exceeded, please try again later",
			})
		},
	})

	// Отдельный лимит на ручной ввод кода: 20/мин на IP. Polling
	// /device/token его не использует и остаётся на 120/мин.
	deviceApproveLimiter := limiter.New(limiter.Config{
		Max:          20,
		Expiration:   time.Minute,
		KeyGenerator: clientKey,
		LimitReached: func(c *fiber.Ctx) error {
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error": "Rate limit exceeded, please try again later",
			})
		},
	})

	// Upload limiter — upload-запросы тяжёлые (multipart-тело), их
	// нужно лимитировать отдельно от auth-роутов.
	uploadMax := cfg.RateLimiter.UploadMax
	if uploadMax <= 0 {
		uploadMax = cfg.RateLimiter.Max * 30
	}
	uploadExpiration := cfg.RateLimiter.UploadExpiration
	if uploadExpiration <= 0 {
		uploadExpiration = cfg.RateLimiter.Expiration
	}
	// Ключ по пользователю, а не по IP: несколько админов за одним NAT
	// не должны делить бюджет, а IP легко меняется.
	uploadKey := func(c *fiber.Ctx) string {
		if id, ok := middleware.GetUserID(c); ok {
			return fmt.Sprintf("user:%d", id)
		}
		return clientKey(c)
	}
	uploadRateLimiter := limiter.New(limiter.Config{
		Max:          uploadMax,
		Expiration:   time.Duration(uploadExpiration) * time.Second,
		KeyGenerator: uploadKey,
		LimitReached: func(c *fiber.Ctx) error {
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error": "Rate limit exceeded, please try again later",
			})
		},
	})

	// Extract limiter — отдельный инстанс с тем же бюджетом: им закрыты
	// запуск ffmpeg (POST) и ручная отмена (DELETE). Статус опроса и
	// готовый трек (GET) идут через read-лимитер: поллинг раз в ~1.5с
	// съедал бы строгий бюджет запуска.
	extractRateLimiter := limiter.New(limiter.Config{
		Max:          cfg.RateLimiter.Max,
		Expiration:   time.Duration(cfg.RateLimiter.Expiration) * time.Second,
		KeyGenerator: clientKey,
		LimitReached: func(c *fiber.Ctx) error {
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error": "Rate limit exceeded, please try again later",
			})
		},
	})

	// Read limiter — отдельный щедрый инстанс для чтений/стримов: плеер
	// при сиках шлёт десятки range-запросов подряд, а списки/обложки/
	// сабы/прогресс опрашиваются постоянно — строгий бюджет 10/мин
	// (auth/upload/extract) их бы душил. Один токен без лимита даёт
	// неограниченный обход всей библиотеки, поэтому чтения лимитируем
	// отдельно, а не оставляем открытыми.
	readRateLimiter := limiter.New(limiter.Config{
		Max:          cfg.RateLimiter.ReadMax,
		Expiration:   time.Duration(cfg.RateLimiter.ReadExpiration) * time.Second,
		KeyGenerator: clientKey,
		LimitReached: func(c *fiber.Ctx) error {
			return c.Status(fiber.StatusTooManyRequests).JSON(fiber.Map{
				"error": "Rate limit exceeded, please try again later",
			})
		},
	})

	// Refresh/logout — отдельный bucket: автоматический refresh не должен
	// выжигать лимит OTP-входа при нескольких вкладках/NAT.
	refreshRateLimiter := limiter.New(limiter.Config{
		Max:          cfg.RateLimiter.Max,
		Expiration:   time.Duration(cfg.RateLimiter.Expiration) * time.Second,
		KeyGenerator: clientKey,
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
	auth.Post("/refresh", refreshRateLimiter, authHandler.Refresh)
	auth.Post("/logout-refresh", refreshRateLimiter, authHandler.LogoutByRefresh)
	auth.Post("/device/code", authRateLimiter, authHandler.DeviceCode)
	auth.Post("/device/token", deviceRateLimiter, authHandler.DeviceToken)

	// Protected routes
	api := fiberApp.Group("/api", middleware.AuthMiddleware(jwtService))

	api.Get("/auth/me", authHandler.Me)
	api.Post("/auth/logout", authHandler.Logout)
	api.Get("/auth/devices", authHandler.ListDevices)
	api.Delete("/auth/devices/:device_id", authHandler.RevokeDevice)
	api.Patch("/auth/devices/:device_id", authHandler.RenameDevice)
	api.Post("/auth/device/inspect", deviceApproveLimiter, authHandler.InspectDevice)
	api.Post("/auth/device/approve", deviceApproveLimiter, authHandler.ApproveDevice)

	// Admin-only middleware for destructive/administrative operations.
	requireAdmin := middleware.RequireAdmin(userRepo)

	// Админка хранилища: диск, карантин оригиналов, список и ретрай заданий.
	admin := api.Group("/admin", requireAdmin)
	admin.Get("/storage", readRateLimiter, adminHandler.StorageInfo)
	admin.Put("/storage/settings", adminHandler.UpdateStorageSettings)
	admin.Get("/originals", readRateLimiter, adminHandler.OriginalsList)
	admin.Get("/originals/:name/download", uploadRateLimiter, adminHandler.OriginalDownload)
	admin.Delete("/originals/:name", adminHandler.OriginalDelete)
	admin.Get("/transcodes", readRateLimiter, adminHandler.TranscodesList)
	admin.Post("/transcodes/:id/retry", adminHandler.TranscodeRetry)
	admin.Get("/users", readRateLimiter, adminHandler.UsersList)
	admin.Put("/users/:id", adminHandler.UserUpdateRole)
	admin.Delete("/users/:id", adminHandler.UserDelete)

	media := api.Group("/media")
	// /bulk регистрируем ДО /:id — статический путь имеет приоритет
	// в fiber, но явный порядок исключает сюрпризы при рефакторинге.
	media.Get("/bulk", readRateLimiter, mediaHandler.Bulk)
	media.Get("", readRateLimiter, mediaHandler.List)
	media.Get("/:id", readRateLimiter, mediaHandler.Get)
	media.Post(uploadRouteSuffix, requireAdmin, uploadRateLimiter, uploadHandler.Upload)
	media.Get("/uploads/:id", requireAdmin, uploadHandler.UploadStatus)
	media.Delete("/uploads/:id", requireAdmin, uploadHandler.CancelUpload)
	// Нормализации: статусы заданий карантина (та же форма, что у
	// загрузок, плюс прогресс). UploadStatus/CancelUpload тоже умеют
	// отдавать их как fallback по job_id.
	media.Get("/transcodes/:id", requireAdmin, transcodeHandler.TranscodeStatus)
	media.Delete("/transcodes/:id", requireAdmin, transcodeHandler.TranscodeCancel)
	// Субтитры: список дорожек и WebVTT-файлы (как превью — всем).
	media.Get("/:id/subs", readRateLimiter, subsHandler.ListSubs)
	media.Get("/:id/subs/:lang", readRateLimiter, subsHandler.ServeSub)
	// Извлечение аудио: POST ставит джоб (202) или сразу отдаёт готовый
	// трек (200); статусы — той же формы, что у загрузок. Тяжёлый лимитер
	// тот же, что у загрузок: ffmpeg жрёт CPU не меньше multipart-парсинга.
	media.Post("/:id/extract", requireAdmin, extractRateLimiter, extractHandler.Extract)
	// Статус и готовый трек — частые чтения (поллинг раз в 1.5с), им
	// нужен read-бюджет, а не строгий лимит запуска ffmpeg.
	media.Get("/extract/:id", requireAdmin, readRateLimiter, extractHandler.ExtractStatus)
	media.Delete("/extract/:id", requireAdmin, extractRateLimiter, extractHandler.CancelExtract)
	media.Get("/:id/extracted", requireAdmin, readRateLimiter, extractHandler.Extracted)
	media.Post("/check-hash", mediaHandler.CheckHash)
	media.Delete("/:id", requireAdmin, mediaHandler.Delete)
	media.Get("/:id/stream", readRateLimiter, mediaHandler.Stream)
	media.Get("/:id/thumb", readRateLimiter, thumbHandler.Get)
	media.Get("/:id/cover", readRateLimiter, thumbHandler.GetCover)
	media.Put("/:id"+coverRouteSuffix, requireAdmin, thumbHandler.UploadCover)

	progress := api.Group("/progress")
	progress.Get("", readRateLimiter, progressHandler.List)
	progress.Get("/:mediaId", readRateLimiter, progressHandler.GetOne)
	progress.Put("/:mediaId", progressHandler.Update)
	progress.Delete("/:mediaId", progressHandler.Delete)

	metadataGroup := api.Group("/metadata")
	metadataGroup.Get("/search", readRateLimiter, metadataHandler.Search)
	metadataGroup.Post("/:mediaId/refresh", requireAdmin, metadataHandler.Refresh)
	metadataGroup.Put("/:mediaId", requireAdmin, metadataHandler.Update)

	// Favorites
	api.Post("/media/:id/favorite", favoriteHandler.AddFavorite)
	api.Delete("/media/:id/favorite", favoriteHandler.RemoveFavorite)
	api.Get("/favorites", readRateLimiter, favoriteHandler.ListFavorites)
	api.Get("/favorites/artists", readRateLimiter, favoriteHandler.ListFavoriteArtistIDs)
	api.Post("/favorites/artist", favoriteHandler.AddArtistFavorite)
	api.Delete("/favorites/artist", favoriteHandler.RemoveArtistFavorite)

	// Artists
	artist := api.Group("/artists")
	artist.Get("", readRateLimiter, artistHandler.List)
	artist.Put("/:id", requireAdmin, artistHandler.Update)
	artist.Post("/:id/cover", requireAdmin, artistHandler.UploadCover)
	artist.Get("/:id/cover", readRateLimiter, artistHandler.GetCover)

	// Collections
	api.Post("/collections", collectionHandler.Create)
	api.Get("/collections", readRateLimiter, collectionHandler.List)
	api.Put("/collections/:id", collectionHandler.Update)
	api.Delete("/collections/:id", collectionHandler.Delete)
	api.Post("/collections/:id/items", collectionHandler.AddItem)
	api.Post("/collections/:id/items/move", collectionHandler.MoveItem)
	// Групповые операции: сезон раскладывается по коллекции одним
	// запросом, а не по файлу.
	api.Post("/collections/:id/items/bulk", collectionHandler.AddItemsBulk)
	api.Post("/collections/:id/items/move/bulk", collectionHandler.MoveItemsBulk)
	api.Delete("/collections/:id/items", collectionHandler.RemoveItemsBulk)
	api.Delete("/collections/:id/items/:mediaId", collectionHandler.RemoveItem)
	api.Get("/collections/:id/items", readRateLimiter, collectionHandler.ListItems)
	api.Get("/collections/:id/stats", readRateLimiter, trashHandler.Stats)

	// Trash — корзина: плоский список, восстановление, снос навсегда.
	// Медиа-ветки и Empty — под requireAdmin, как media.Delete/:id:
	// медиа глобальные, чужое сносить/возвращать нельзя.
	api.Get("/trash", readRateLimiter, trashHandler.List)
	api.Delete("/trash", requireAdmin, trashHandler.Empty)
	api.Post("/trash/media/:id/restore", requireAdmin, trashHandler.RestoreMedia)
	api.Delete("/trash/media/:id", requireAdmin, trashHandler.PurgeMedia)
	api.Post("/trash/collections/:id/restore", trashHandler.RestoreCollection)
	api.Delete("/trash/collections/:id", trashHandler.PurgeCollection)

	// Lyrics
	api.Get("/media/:id/lyrics", readRateLimiter, lyricsHandler.GetLyrics)
	api.Put("/media/:id/lyrics", requireAdmin, lyricsHandler.UpsertLyrics)

	// Веб-клиент: same-origin раздача web/dist (SPA) — последним
	// маршрутом, после всех /api. Пустой web_dist — API-only режим
	// (мобильные клиенты, разработка через Vite).
	// Docker-образ кладёт web в /app/web, а YAML может не задавать
	// web_dist: не оставляем контейнер API-only по умолчанию.
	if cfg.Server.WebDist == "" {
		if info, err := os.Stat("/app/web"); err == nil && info.IsDir() {
			cfg.Server.WebDist = "/app/web"
		}
	}
	if cfg.Server.WebDist != "" {
		webHandler, err := handlers.NewWebHandler(cfg.Server.WebDist)
		if err != nil {
			return nil, err
		}
		webHandler.RegisterRoutes(fiberApp)
		log.Printf("web client: serving %s", cfg.Server.WebDist)
	}

	// Start file watcher if enabled.
	opt := options{backgroundWorkers: true}
	for _, apply := range opts {
		apply(&opt)
	}
	if watcherService != nil && opt.backgroundWorkers {
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

	// Initial library scan at startup: fsnotify не знает о файлах,
	// существовавших до запуска. ScanAll в фоне (не блокирует старт);
	// контекст отменяется в Shutdown, чтобы скан не пережил сервер.
	// Shutdown дожидается скана через scanWG до закрытия БД.
	var scanCancelFn context.CancelFunc
	scanWG := new(sync.WaitGroup)
	if cfg.Scanner.Enabled && opt.backgroundWorkers {
		scanCtx, scanCancel := context.WithCancel(context.Background())
		scanCancelFn = scanCancel
		scanWG.Add(1)
		goSafe(func() {
			defer scanWG.Done()
			log.Printf("initial library scan started")
			if err := scanner.ScanAll(scanCtx); err != nil {
				log.Printf("initial library scan: %v", err)
			} else {
				log.Printf("initial library scan finished")
			}
			// scanner.interval больше не мёртвая настройка: периодический
			// скан ловит пропущенные fsnotify-события и отвалившиеся mount.
			if cfg.Scanner.Interval <= 0 {
				return
			}
			ticker := time.NewTicker(time.Duration(cfg.Scanner.Interval) * time.Second)
			defer ticker.Stop()
			for {
				select {
				case <-scanCtx.Done():
					return
				case <-ticker.C:
					if err := scanner.ScanAll(scanCtx); err != nil {
						log.Printf("periodic library scan: %v", err)
					}
				}
			}
		})
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

	// Разовая заливка размеров кадра для видео, записанных до появления
	// колонок width/height. Фоном: ffprobe по каждому файлу — процесс
	// должен принимать запросы, пока идёт проход. Отменяется вместе с
	// cleanupStop, чтобы не мешать завершению.
	dimensionsCtx, cancelDimensions := context.WithCancel(context.Background())
	backfillWG := new(sync.WaitGroup)
	backfillWG.Add(1)
	goSafe(func() {
		defer backfillWG.Done()
		updated := services.BackfillVideoDimensions(dimensionsCtx, mediaRepo)
		if updated > 0 {
			log.Printf("dimensions: залито размеров кадра для %d видео", updated)
		}
	})
	goSafe(func() {
		<-cleanupStop
		cancelDimensions()
	})

	ok = true
	return &App{
		Fiber:            fiberApp,
		Config:           cfg,
		OTPStore:         otpStore,
		Watcher:          watcherService,
		UploadQueue:      uploadQueue,
		ExtractQueue:     extractQueue,
		TranscodeQueue:   transcodeQueue,
		Version:          version,
		sqlDB:            sqlDB,
		cleanupStop:      cleanupStop,
		scanner:          scanner,
		scanCancelFn:     scanCancelFn,
		scanWG:           scanWG,
		backfillWG:       backfillWG,
		dimensionsCancel: cancelDimensions,
	}, nil
}

// Listen starts the HTTP server on the configured host and port.
func (a *App) Listen() error {
	host := a.Config.Server.Host
	port := a.Config.Server.Port
	log.Printf("Flux Media Server %s starting on %s:%d", a.Version, host, port)
	return a.Fiber.Listen(fmt.Sprintf("%s:%d", host, port))
}

// requestLogger — access-лог в формате middleware/logger Fiber, но IP берётся
// через getClientIP, то есть с учётом trusted_proxies. Пишем напрямую в
// stdout: log.Printf добавил бы свой префикс даты к уже готовой строке.
func requestLogger(out io.Writer, clientIP func(*fiber.Ctx) string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		start := time.Now()
		err := c.Next()
		stop := time.Now()

		msg := "-"
		if err != nil {
			msg = err.Error()
		}
		fmt.Fprintf(out, "%s | %d | %13v | %s | %s | %s | %s\n",
			stop.Format("15:04:05"),
			c.Response().StatusCode(),
			stop.Sub(start),
			clientIP(c),
			c.Method(),
			c.Path(),
			msg,
		)
		return err
	}
}

// getClientIP возвращает IP клиента для rate limiter и access-лога.
// X-Forwarded-For /
// X-Real-IP принимаются только если непосредственный peer входит в
// trusted_proxies: иначе клиент подделает IP и получит уникальный ключ
// на каждый запрос. Пустой список — заголовки игнорируются.
func getClientIP(c *fiber.Ctx, trusted []*net.IPNet) string {
	peer := net.ParseIP(c.IP())
	if len(trusted) == 0 || peer == nil || !ipTrusted(peer, trusted) {
		return c.IP()
	}
	// Идём по X-Forwarded-For справа налево: правый адрес добавил
	// ближайший доверенный прокси, левые мог подставить клиент.
	parts := strings.Split(c.Get("X-Forwarded-For"), ",")
	for i := len(parts) - 1; i >= 0; i-- {
		ip := net.ParseIP(strings.TrimSpace(parts[i]))
		if ip == nil {
			continue
		}
		if !ipTrusted(ip, trusted) {
			return ip.String()
		}
	}
	// X-Real-IP не используем: прокси не обязан его санитизировать,
	// а клиент получает произвольный ключ лимитера.
	return c.IP()
}

func parseTrustedProxies(raw string) []*net.IPNet {
	var result []*net.IPNet
	for _, part := range strings.Split(raw, ",") {
		value := strings.TrimSpace(part)
		if value == "" {
			continue
		}
		if !strings.Contains(value, "/") {
			if ip := net.ParseIP(value); ip != nil {
				bits := 32
				if ip.To4() == nil {
					bits = 128
				}
				value = fmt.Sprintf("%s/%d", ip.String(), bits)
			}
		}
		if _, network, err := net.ParseCIDR(value); err == nil {
			result = append(result, network)
			continue
		}
		log.Printf("trusted_proxies: ignoring invalid entry %q", value)
	}
	return result
}

func ipTrusted(ip net.IP, trusted []*net.IPNet) bool {
	for _, network := range trusted {
		if network.Contains(ip) {
			return true
		}
	}
	return false
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
	if a.scanCancelFn != nil {
		a.scanCancelFn()
	}
	if a.Watcher != nil {
		a.Watcher.Stop()
	}
	if a.UploadQueue != nil {
		a.UploadQueue.Stop()
	}
	if a.ExtractQueue != nil {
		a.ExtractQueue.Stop()
	}
	if a.TranscodeQueue != nil {
		a.TranscodeQueue.Stop()
	}
	a.OTPStore.Stop()

	err := a.Fiber.ShutdownWithContext(shutdownCtx)
	// Фоновый скан обязан завершиться до закрытия БД: его контекст уже
	// отменён выше (scanCancelFn), все операции сканера ctx-aware, так
	// что Wait завершается быстро. Патологический случай (застрявший
	// внешний процесс сверх его таймаута) не должен блокировать Shutdown
	// дольше бюджета shutdownCtx — ждём с дедлайном.
	if a.scanWG != nil {
		scanDone := make(chan struct{})
		go func() {
			a.scanWG.Wait()
			close(scanDone)
		}()
		select {
		case <-scanDone:
		case <-shutdownCtx.Done():
			log.Printf("shutdown: timed out waiting for background scan; closing database anyway")
		}
	}
	if a.backfillWG != nil {
		backfillDone := make(chan struct{})
		go func() {
			a.backfillWG.Wait()
			close(backfillDone)
		}()
		select {
		case <-backfillDone:
		case <-shutdownCtx.Done():
			log.Printf("shutdown: timed out waiting for dimensions backfill; closing database anyway")
		}
	}
	if a.sqlDB != nil {
		if dbErr := a.sqlDB.Close(); dbErr != nil && err == nil {
			err = dbErr
		}
	}
	return err
}
