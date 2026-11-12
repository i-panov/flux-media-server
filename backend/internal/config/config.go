package config

import (
	"bytes"
	"errors"
	"fmt"
	"net/url"
	"os"
	"strings"

	"flux/internal/models"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server      ServerConfig      `yaml:"server"`
	Database    DatabaseConfig    `yaml:"database"`
	Auth        AuthConfig        `yaml:"auth"`
	Scanner     ScannerConfig     `yaml:"scanner"`
	RateLimiter RateLimiterConfig `yaml:"rate_limiter"`
	Media       MediaConfig       `yaml:"media"`
	Storage     StorageConfig     `yaml:"storage"`
	Transcode   TranscodeConfig   `yaml:"transcode"`
}

type ServerConfig struct {
	Host        string `yaml:"host"`
	Port        int    `yaml:"port"`
	Debug       bool   `yaml:"debug"`
	Env         string `yaml:"env"` // "dev" | "production" (default)
	CORSOrigins string `yaml:"cors_origins"`
	// TrustedProxies — CIDR/IP прокси, от которых принимаем X-Forwarded-For.
	// Пусто — заголовок игнорируется (клиент = c.IP()).
	TrustedProxies string `yaml:"trusted_proxies"`
	CookieSecure   bool   `yaml:"cookie_secure"` // Secure-флаг сессионных кук, нужен HTTPS
	MaxUploadSize  int64  `yaml:"max_upload_size"`
	WebDist        string `yaml:"web_dist"` // каталог собранного веба (web/dist); пусто — API-only
	// PublicURL — внешний адрес веб-клиента для QR/device-code. Если пуст,
	// берётся scheme+Host текущего запроса (нормально для LAN/dev).
	PublicURL string `yaml:"public_url"`
}

type DatabaseConfig struct {
	Path string `yaml:"path"`
}

type AuthConfig struct {
	JWTSecret         string     `yaml:"jwt_secret"`
	JWTExpiry         int        `yaml:"jwt_expiry"`     // in hours
	RefreshExpiry     int        `yaml:"refresh_expiry"` // in hours
	CodeLength        int        `yaml:"code_length"`
	CodeExpiry        int        `yaml:"code_expiry"`
	MaxOTPEntries     int        `yaml:"max_otp_entries"`
	AllowedEmails     []string   `yaml:"allowed_emails"`
	AllowUnknownEmail bool       `yaml:"allow_unknown_email"`
	SMTP              SMTPConfig `yaml:"smtp"`
}

type SMTPConfig struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	Username string `yaml:"username"`
	Password string `yaml:"password"`
	From     string `yaml:"from"`
	// RequireTLS — *bool, чтобы отличать «не задано» от явного false:
	// по умолчанию (nil) TLS обязателен, require_tls: false отключает.
	RequireTLS  *bool `yaml:"require_tls"`
	ImplicitTLS bool  `yaml:"implicit_tls"`
}

type ScannerConfig struct {
	Enabled      bool `yaml:"enabled"`
	Interval     int  `yaml:"interval"`
	WatchEnabled bool `yaml:"watch_enabled"`
}

type RateLimiterConfig struct {
	Max            int   `yaml:"max"`
	Expiration     int64 `yaml:"expiration"` // in seconds
	ReadMax        int   `yaml:"read_max"`
	ReadExpiration int64 `yaml:"read_expiration"` // in seconds
	// UploadMax/UploadExpiration — отдельный бюджет массовых загрузок:
	// 10/мин на пачку мемов не хватает, при этом auth/extract остаются
	// строгими. 0 — взять Max × 30.
	UploadMax        int   `yaml:"upload_max"`
	UploadExpiration int64 `yaml:"upload_expiration"` // in seconds
}

// Дефолты read-бюджета: используются в Load и в app.New (тесты обходят
// Load, поэтому дефолты продублированы там же — через эти константы).
const (
	DefaultReadMax        = 600
	DefaultReadExpiration = 60
)

type MediaConfig struct {
	ThumbnailPath string `yaml:"thumbnail_path"`
	VideoPath     string `yaml:"video_path"`
	AudioPath     string `yaml:"audio_path"`
	ImagePath     string `yaml:"image_path"` // мемы: jpg/jpeg/png/gif/webp/bmp
}

// StorageConfig — пути нового конвейера приёма: карантин оригиналов
// и временные файлы транскода. Библиотекой остаются video_path/audio_path.
type StorageConfig struct {
	OriginalsDir string `yaml:"originals_dir"`
	TempDir      string `yaml:"temp_dir"`
	// AutoCleanupOriginals — опциональная авточистка карантина при
	// нехватке места под заливку (по умолчанию выключена: удаление
	// только руками админа).
	AutoCleanupOriginals bool `yaml:"auto_cleanup_originals"`
}

// TranscodeConfig — параметры нормализации видео в домашний формат
// (MP4 + H.264, потолок — MaxHeight).
type TranscodeConfig struct {
	// CRF — указатель, чтобы отличать «не задано» (nil → 20) от
	// явного 0: lossless-CRF 0 противоречит задаче (огромные файлы,
	// браузеры не играют) и потому запрещён валидацией.
	CRF            *int    `yaml:"crf"`
	Preset         string  `yaml:"preset"`
	MaxHeight      int     `yaml:"max_height"`
	EstimateFactor float64 `yaml:"estimate_factor"`
	MaxAttempts    int     `yaml:"max_attempts"`
}

// MediaPath represents a scan path with its media type.
type MediaPath struct {
	Path string
	Type models.MediaType // "video" or "audio"
}

// MediaPaths returns all configured media paths with their types.
func (m MediaConfig) MediaPaths() []MediaPath {
	return []MediaPath{
		{Path: m.VideoPath, Type: models.MediaTypeVideo},
		{Path: m.AudioPath, Type: models.MediaTypeAudio},
		{Path: m.ImagePath, Type: models.MediaTypeImage},
	}
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	// KnownFields(true) отклоняет неизвестные поля конфига — опечатка в
	// ключе YAML не останется незамеченной (молча игнорируемой).
	cfg := &Config{}
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	if err := dec.Decode(cfg); err != nil {
		return nil, err
	}

	// Чувствительные поля можно задать через окружение: env имеет
	// приоритет над YAML, чтобы секреты не лежали в открытом конфиге.
	if v := os.Getenv("FLUX_JWT_SECRET"); v != "" {
		cfg.Auth.JWTSecret = v
	}
	if v := os.Getenv("FLUX_SMTP_PASSWORD"); v != "" {
		cfg.Auth.SMTP.Password = v
	}

	// Set defaults
	if cfg.Server.Port == 0 {
		cfg.Server.Port = 8080
	}
	if cfg.Server.Env == "" {
		cfg.Server.Env = "production"
	}
	// Нормализуем регистр и пробелы: "Production" не должен молча ломать
	// проверку whitelist ниже. Опечатки («prod») отсекает whitelist.
	cfg.Server.Env = strings.ToLower(strings.TrimSpace(cfg.Server.Env))
	// Whitelist вместо свободной строки: опечатка («prod») молча
	// превращала бы конфиг в production и ломала проверку debug ниже.
	switch cfg.Server.Env {
	case "dev", "production":
	default:
		return nil, fmt.Errorf("server.env must be \"dev\" or \"production\", got %q", cfg.Server.Env)
	}
	if cfg.Server.MaxUploadSize == 0 {
		cfg.Server.MaxUploadSize = 100 * 1024 * 1024 // 100MB
	}
	if cfg.Auth.CodeLength == 0 {
		cfg.Auth.CodeLength = 6
	}
	if cfg.Auth.CodeExpiry == 0 {
		cfg.Auth.CodeExpiry = 300
	}
	if cfg.Auth.JWTExpiry == 0 {
		cfg.Auth.JWTExpiry = 1
	}
	if cfg.Auth.RefreshExpiry == 0 {
		cfg.Auth.RefreshExpiry = 720 // 30 days
	}
	if cfg.Auth.MaxOTPEntries == 0 {
		cfg.Auth.MaxOTPEntries = 10000
	}
	if cfg.RateLimiter.Max == 0 {
		cfg.RateLimiter.Max = 10
	}
	if cfg.RateLimiter.Expiration == 0 {
		cfg.RateLimiter.Expiration = 60
	}
	if cfg.RateLimiter.ReadMax == 0 {
		cfg.RateLimiter.ReadMax = DefaultReadMax
	}
	if cfg.RateLimiter.ReadExpiration == 0 {
		cfg.RateLimiter.ReadExpiration = DefaultReadExpiration
	}
	if cfg.Storage.OriginalsDir == "" {
		cfg.Storage.OriginalsDir = "./data/originals"
	}
	if cfg.Storage.TempDir == "" {
		cfg.Storage.TempDir = "./data/tmp"
	}
	if cfg.Media.ImagePath == "" {
		cfg.Media.ImagePath = "./data/images"
	}
	if cfg.Transcode.CRF == nil {
		defCRF := 20
		cfg.Transcode.CRF = &defCRF
	}
	if cfg.Transcode.Preset == "" {
		cfg.Transcode.Preset = "fast"
	}
	if cfg.Transcode.MaxHeight == 0 {
		cfg.Transcode.MaxHeight = 1080
	}
	if cfg.Transcode.EstimateFactor == 0 {
		cfg.Transcode.EstimateFactor = 1.5
	}
	if cfg.Transcode.MaxAttempts == 0 {
		cfg.Transcode.MaxAttempts = 3
	}
	// По умолчанию TLS обязателен: без явного require_tls:false OTP-письма
	// не должны уходить по plaintext (см. smtp.go — при отсутствии STARTTLS
	// и ImplicitTLS отправка блокируется ошибкой).
	if cfg.Auth.SMTP.RequireTLS == nil {
		def := !cfg.Auth.SMTP.ImplicitTLS
		cfg.Auth.SMTP.RequireTLS = &def
	}

	// Validation
	if cfg.Database.Path == "" {
		return nil, errors.New("database.path must not be empty (use ':memory:' only for tests)")
	}
	if cfg.Server.Port < 1 || cfg.Server.Port > 65535 {
		return nil, fmt.Errorf("server.port must be between 1 and 65535, got %d", cfg.Server.Port)
	}
	if cfg.Server.MaxUploadSize <= 0 {
		return nil, fmt.Errorf("server.max_upload_size must be > 0, got %d", cfg.Server.MaxUploadSize)
	}
	cfg.Server.PublicURL = strings.TrimRight(strings.TrimSpace(cfg.Server.PublicURL), "/")
	if cfg.Server.PublicURL != "" {
		u, err := url.Parse(cfg.Server.PublicURL)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
			return nil, fmt.Errorf("server.public_url must be an absolute http(s) URL, got %q", cfg.Server.PublicURL)
		}
	}
	if cfg.Auth.CodeLength < 4 || cfg.Auth.CodeLength > 12 {
		return nil, fmt.Errorf("auth.code_length must be between 4 and 12, got %d", cfg.Auth.CodeLength)
	}
	if cfg.Auth.JWTExpiry <= 0 {
		return nil, fmt.Errorf("auth.jwt_expiry must be > 0, got %d", cfg.Auth.JWTExpiry)
	}
	if cfg.RateLimiter.Max <= 0 {
		return nil, fmt.Errorf("rate_limiter.max must be > 0, got %d", cfg.RateLimiter.Max)
	}
	if cfg.RateLimiter.ReadMax <= 0 {
		return nil, fmt.Errorf("rate_limiter.read_max must be > 0, got %d", cfg.RateLimiter.ReadMax)
	}
	if cfg.RateLimiter.ReadExpiration <= 0 {
		return nil, fmt.Errorf("rate_limiter.read_expiration must be > 0, got %d", cfg.RateLimiter.ReadExpiration)
	}
	crf := 0
	if cfg.Transcode.CRF != nil {
		crf = *cfg.Transcode.CRF
	}
	if crf < 1 || crf > 51 {
		return nil, fmt.Errorf("transcode.crf must be between 1 and 51 (lossless 0 is not supported), got %d", crf)
	}
	switch cfg.Transcode.Preset {
	case "ultrafast", "superfast", "veryfast", "faster", "fast",
		"medium", "slow", "slower", "veryslow", "placebo":
	default:
		return nil, fmt.Errorf("transcode.preset must be a valid x264 preset, got %q", cfg.Transcode.Preset)
	}
	if cfg.Transcode.MaxHeight <= 0 {
		return nil, fmt.Errorf("transcode.max_height must be > 0, got %d", cfg.Transcode.MaxHeight)
	}
	if cfg.Transcode.EstimateFactor <= 0 {
		return nil, fmt.Errorf("transcode.estimate_factor must be > 0, got %v", cfg.Transcode.EstimateFactor)
	}
	if cfg.Transcode.MaxAttempts < 1 {
		return nil, fmt.Errorf("transcode.max_attempts must be >= 1, got %d", cfg.Transcode.MaxAttempts)
	}
	// "*" нельзя комбинировать с конкретными origins: браузеры в этом
	// случае игнорируют Access-Control-Allow-Origin, а Allow-Credentials
	// с wildcard запрещён спецификацией.
	if err := validateCORS(cfg.Server.CORSOrigins); err != nil {
		return nil, err
	}

	// Debug-режим возвращает OTP-коды в ответах API и пишет SQL с
	// секретами — запускать его вне локальной разработки нельзя.
	if cfg.Server.Debug && cfg.Server.Env != "dev" {
		return nil, errors.New("server.debug is enabled but server.env is not \"dev\": debug mode is only allowed in development")
	}

	// Validate JWT secret
	if len(cfg.Auth.JWTSecret) < 32 {
		return nil, errors.New("jwt_secret must be at least 32 characters")
	}

	// Refuse to run in production mode with the well-known default secret.
	if !cfg.Server.Debug && strings.HasPrefix(cfg.Auth.JWTSecret, "change-me") {
		return nil, errors.New("jwt_secret must be changed from the default value (generate one with: openssl rand -base64 48)")
	}

	return cfg, nil
}

func validateCORS(origins string) error {
	if origins == "" || origins == "*" {
		return nil
	}
	for _, o := range strings.Split(origins, ",") {
		if strings.TrimSpace(o) == "*" {
			return errors.New("server.cors_origins cannot combine \"*\" with specific origins")
		}
	}
	return nil
}
