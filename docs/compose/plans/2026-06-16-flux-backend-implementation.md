# Flux Media Server — Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use compose:subagent (recommended) or compose:execute to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a personal media server backend (like Jellyfin) for video content with Go, Fiber, GORM, and SQLite.

**Architecture:** Monolith with modules: config, models, handlers, services, repository, scanner, metadata, streamer, email, middleware. REST API with JWT authentication via email OTP.

**Tech Stack:** Go 1.26.4, Fiber v2, GORM, SQLite, FFmpeg, JWT, SMTP

---

## File Structure

```
backend/
├── cmd/server/main.go
├── internal/
│   ├── config/config.go
│   ├── models/
│   │   ├── media.go
│   │   ├── user.go
│   │   ├── progress.go
│   │   └── library.go
│   ├── handlers/
│   │   ├── auth.go
│   │   ├── media.go
│   │   ├── library.go
│   │   ├── progress.go
│   │   └── metadata.go
│   ├── services/
│   │   ├── auth.go
│   │   ├── media.go
│   │   ├── scanner.go
│   │   ├── metadata.go
│   │   └── streamer.go
│   ├── repository/
│   │   ├── media.go
│   │   ├── user.go
│   │   ├── progress.go
│   │   └── library.go
│   ├── scanner/scanner.go
│   ├── metadata/parser.go
│   ├── streamer/streamer.go
│   ├── email/smtp.go
│   └── middleware/auth.go
├── configs/config.example.yaml
├── go.mod
└── go.sum
```

---

## Task 1: Project Setup

**Covers:** [S1]

**Files:**
- Create: `backend/go.mod`
- Create: `backend/cmd/server/main.go`

- [ ] **Step 1: Initialize Go module**

Run: `cd backend && go mod init flux`

- [ ] **Step 2: Add dependencies**

Run: `cd backend && go get github.com/gofiber/fiber/v2 gorm.io/gorm gorm.io/driver/sqlite github.com/golang-jwt/jwt/v5 gopkg.in/yaml.v3 github.com/google/uuid github.com/stretchr/testify`

- [ ] **Step 3: Create main.go entry point**

```go
package main

import (
	"fmt"
	"log"
	"os"

	"github.com/gofiber/fiber/v2"
)

func main() {
	app := fiber.New()

	app.Get("/", func(c *fiber.Ctx) error {
		return c.SendString("Flux Media Server")
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Fatal(app.Listen(fmt.Sprintf(":%s", port)))
}
```

- [ ] **Step 4: Verify server starts**

Run: `cd backend && go run ./cmd/server`
Expected: Server starts on :8080

- [ ] **Step 5: Commit**

```bash
git add backend/
git commit -m "feat: initialize Go project with Fiber"
```

---

## Task 2: Configuration Loading

**Covers:** [S5]

**Files:**
- Create: `backend/internal/config/config.go`
- Create: `backend/configs/config.example.yaml`
- Create: `backend/internal/config/config_test.go`

- [ ] **Step 1: Write failing test for config loading**

```go
package config

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestLoadConfig(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.yaml")

	yamlContent := `
server:
  host: "127.0.0.1"
  port: 9090
  debug: true

database:
  path: "./test.db"

auth:
  jwt_secret: "test-secret"
  code_length: 6
  code_expiry: 300
  allowed_emails:
    - test@example.com
  allow_unknown_email: false
  smtp:
    host: "smtp.test.com"
    port: 587
    username: "test@test.com"
    password: "test-pass"
    from: "Test <test@test.com>"

scanner:
  enabled: true
  interval: 30

media:
  thumbnail_path: "./thumbnails"
  allowed_extensions:
    - .mp4
    - .mkv
`
	os.WriteFile(configPath, []byte(yamlContent), 0644)

	cfg, err := Load(configPath)
	assert.NoError(t, err)
	assert.Equal(t, "127.0.0.1", cfg.Server.Host)
	assert.Equal(t, 9090, cfg.Server.Port)
	assert.Equal(t, true, cfg.Server.Debug)
	assert.Equal(t, "./test.db", cfg.Database.Path)
	assert.Equal(t, "test-secret", cfg.Auth.JWTSecret)
	assert.Equal(t, []string{"test@example.com"}, cfg.Auth.AllowedEmails)
	assert.Equal(t, false, cfg.Auth.AllowUnknownEmail)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/config/ -v`
Expected: FAIL with "undefined: Load"

- [ ] **Step 3: Implement config loading**

```go
package config

import (
	"os"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server   ServerConfig   `yaml:"server"`
	Database DatabaseConfig `yaml:"database"`
	Auth     AuthConfig     `yaml:"auth"`
	Scanner  ScannerConfig  `yaml:"scanner"`
	Media    MediaConfig    `yaml:"media"`
}

type ServerConfig struct {
	Host  string `yaml:"host"`
	Port  int    `yaml:"port"`
	Debug bool   `yaml:"debug"`
}

type DatabaseConfig struct {
	Path string `yaml:"path"`
}

type AuthConfig struct {
	JWTSecret        string   `yaml:"jwt_secret"`
	CodeLength       int      `yaml:"code_length"`
	CodeExpiry       int      `yaml:"code_expiry"`
	AllowedEmails    []string `yaml:"allowed_emails"`
	AllowUnknownEmail bool    `yaml:"allow_unknown_email"`
	SMTP             SMTPConfig `yaml:"smtp"`
}

type SMTPConfig struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	Username string `yaml:"username"`
	Password string `yaml:"password"`
	From     string `yaml:"from"`
}

type ScannerConfig struct {
	Enabled  bool `yaml:"enabled"`
	Interval int  `yaml:"interval"`
}

type MediaConfig struct {
	ThumbnailPath    string   `yaml:"thumbnail_path"`
	AllowedExtensions []string `yaml:"allowed_extensions"`
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	cfg := &Config{}
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, err
	}

	// Set defaults
	if cfg.Server.Port == 0 {
		cfg.Server.Port = 8080
	}
	if cfg.Auth.CodeLength == 0 {
		cfg.Auth.CodeLength = 6
	}
	if cfg.Auth.CodeExpiry == 0 {
		cfg.Auth.CodeExpiry = 300
	}

	return cfg, nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/config/ -v`
Expected: PASS

- [ ] **Step 5: Create example config file**

```yaml
server:
  host: "0.0.0.0"
  port: 8080
  debug: false

database:
  path: "./data/flux.db"

auth:
  jwt_secret: "change-me-in-production"
  code_length: 6
  code_expiry: 300
  allowed_emails:
    - user1@example.com
    - user2@example.com
  allow_unknown_email: false
  smtp:
    host: "smtp.gmail.com"
    port: 587
    username: "your-email@gmail.com"
    password: "your-app-password"
    from: "Flux <noreply@example.com>"

scanner:
  enabled: true
  interval: 30

media:
  thumbnail_path: "./data/thumbnails"
  allowed_extensions:
    - .mp4
    - .mkv
    - .avi
    - .mov
    - .wmv
```

- [ ] **Step 6: Commit**

```bash
git add backend/internal/config/ backend/configs/
git commit -m "feat: add YAML configuration loading"
```

---

## Task 3: Database Models

**Covers:** [S3]

**Files:**
- Create: `backend/internal/models/media.go`
- Create: `backend/internal/models/user.go`
- Create: `backend/internal/models/progress.go`
- Create: `backend/internal/models/library.go`

- [ ] **Step 1: Create Media model**

```go
package models

import (
	"time"
)

type Media struct {
	ID           uint      `gorm:"primaryKey"`
	Title        string    `gorm:"index"`
	Year         int
	Description  string
	Type         string    `gorm:"index"` // movie, episode
	Duration     int       // в секундах
	FilePath     string    `gorm:"uniqueIndex"`
	FileSize     int64
	ThumbnailURL string
	MetadataID   *uint
	Metadata     *Metadata
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

type Metadata struct {
	ID          uint   `gorm:"primaryKey"`
	ExternalID  string `gorm:"uniqueIndex"`
	Source      string // tmdb, tvdb
	Title       string
	Year        int
	Description string
	PosterURL   string
	BackdropURL string
	Rating      float64
	Genres      string // JSON array
	Cast        string // JSON array
	CreatedAt   time.Time
}
```

- [ ] **Step 2: Create User model**

```go
package models

import (
	"time"
)

type User struct {
	ID          uint      `gorm:"primaryKey"`
	Email       string    `gorm:"uniqueIndex"`
	DisplayName string
	AvatarURL   string
	CreatedAt   time.Time
	UpdatedAt   time.Time
}
```

- [ ] **Step 3: Create WatchProgress model**

```go
package models

import (
	"time"
)

type WatchProgress struct {
	ID        uint `gorm:"primaryKey"`
	UserID    uint `gorm:"index"`
	MediaID   uint `gorm:"index"`
	Position  int  // позиция в секундах
	Duration  int  // общая длительность
	Completed bool
	UpdatedAt time.Time
}
```

- [ ] **Step 4: Create MediaLibrary model**

```go
package models

import (
	"time"
)

type MediaLibrary struct {
	ID           uint   `gorm:"primaryKey"`
	Name         string
	Path         string `gorm:"uniqueIndex"`
	Type         string // movie, tv
	Enabled      bool
	ScanInterval int    // в минутах, 0 = отключено
	CreatedAt    time.Time
	UpdatedAt    time.Time
}
```

- [ ] **Step 5: Commit**

```bash
git add backend/internal/models/
git commit -m "feat: add GORM models for media, user, progress, library"
```

---

## Task 4: Database Repository

**Covers:** [S3]

**Files:**
- Create: `backend/internal/repository/db.go`
- Create: `backend/internal/repository/media.go`
- Create: `backend/internal/repository/user.go`
- Create: `backend/internal/repository/progress.go`
- Create: `backend/internal/repository/library.go`
- Create: `backend/internal/repository/db_test.go`

- [ ] **Step 1: Write failing test for database initialization**

```go
package repository

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func TestInitDB(t *testing.T) {
	db, err := InitDB(":memory:")
	assert.NoError(t, err)
	assert.NotNil(t, db)
}

func TestAutoMigrate(t *testing.T) {
	db, err := InitDB(":memory:")
	assert.NoError(t, err)

	err = AutoMigrate(db)
	assert.NoError(t, err)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/repository/ -v`
Expected: FAIL with "undefined: InitDB"

- [ ] **Step 3: Implement database initialization**

```go
package repository

import (
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"flux/internal/models"
)

func InitDB(path string) (*gorm.DB, error) {
	db, err := gorm.Open(sqlite.Open(path), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		return nil, err
	}

	return db, nil
}

func AutoMigrate(db *gorm.DB) error {
	return db.AutoMigrate(
		&models.Media{},
		&models.Metadata{},
		&models.User{},
		&models.WatchProgress{},
		&models.MediaLibrary{},
	)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/repository/ -v`
Expected: PASS

- [ ] **Step 5: Implement Media repository**

```go
package repository

import (
	"flux/internal/models"
	"gorm.io/gorm"
)

type MediaRepository struct {
	db *gorm.DB
}

func NewMediaRepository(db *gorm.DB) *MediaRepository {
	return &MediaRepository{db: db}
}

func (r *MediaRepository) FindAll(filters map[string]interface{}) ([]models.Media, error) {
	var media []models.Media
	query := r.db.Preload("Metadata")

	if mediaType, ok := filters["type"]; ok {
		query = query.Where("type = ?", mediaType)
	}
	if year, ok := filters["year"]; ok {
		query = query.Where("year = ?", year)
	}

	err := query.Find(&media).Error
	return media, err
}

func (r *MediaRepository) FindByID(id uint) (*models.Media, error) {
	var media models.Media
	err := r.db.Preload("Metadata").First(&media, id).Error
	return &media, err
}

func (r *MediaRepository) FindByPath(path string) (*models.Media, error) {
	var media models.Media
	err := r.db.Where("file_path = ?", path).First(&media).Error
	return &media, err
}

func (r *MediaRepository) Create(media *models.Media) error {
	return r.db.Create(media).Error
}

func (r *MediaRepository) Update(media *models.Media) error {
	return r.db.Save(media).Error
}

func (r *MediaRepository) Delete(id uint) error {
	return r.db.Delete(&models.Media{}, id).Error
}
```

- [ ] **Step 6: Implement User repository**

```go
package repository

import (
	"flux/internal/models"
	"gorm.io/gorm"
)

type UserRepository struct {
	db *gorm.DB
}

func NewUserRepository(db *gorm.DB) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) FindByEmail(email string) (*models.User, error) {
	var user models.User
	err := r.db.Where("email = ?", email).First(&user).Error
	return &user, err
}

func (r *UserRepository) FindByID(id uint) (*models.User, error) {
	var user models.User
	err := r.db.First(&user, id).Error
	return &user, err
}

func (r *UserRepository) Create(user *models.User) error {
	return r.db.Create(user).Error
}

func (r *UserRepository) Update(user *models.User) error {
	return r.db.Save(user).Error
}

func (r *UserRepository) Delete(id uint) error {
	return r.db.Delete(&models.User{}, id).Error
}
```

- [ ] **Step 7: Implement WatchProgress repository**

```go
package repository

import (
	"flux/internal/models"
	"gorm.io/gorm"
)

type ProgressRepository struct {
	db *gorm.DB
}

func NewProgressRepository(db *gorm.DB) *ProgressRepository {
	return &ProgressRepository{db: db}
}

func (r *ProgressRepository) FindByUser(userID uint) ([]models.WatchProgress, error) {
	var progress []models.WatchProgress
	err := r.db.Where("user_id = ?", userID).Find(&progress).Error
	return progress, err
}

func (r *ProgressRepository) FindByUserAndMedia(userID, mediaID uint) (*models.WatchProgress, error) {
	var progress models.WatchProgress
	err := r.db.Where("user_id = ? AND media_id = ?", userID, mediaID).First(&progress).Error
	return &progress, err
}

func (r *ProgressRepository) Upsert(progress *models.WatchProgress) error {
	return r.db.Save(progress).Error
}

func (r *ProgressRepository) Delete(userID, mediaID uint) error {
	return r.db.Where("user_id = ? AND media_id = ?", userID, mediaID).Delete(&models.WatchProgress{}).Error
}
```

- [ ] **Step 8: Implement MediaLibrary repository**

```go
package repository

import (
	"flux/internal/models"
	"gorm.io/gorm"
)

type LibraryRepository struct {
	db *gorm.DB
}

func NewLibraryRepository(db *gorm.DB) *LibraryRepository {
	return &LibraryRepository{db: db}
}

func (r *LibraryRepository) FindAll() ([]models.MediaLibrary, error) {
	var libraries []models.MediaLibrary
	err := r.db.Find(&libraries).Error
	return libraries, err
}

func (r *LibraryRepository) FindByID(id uint) (*models.MediaLibrary, error) {
	var library models.MediaLibrary
	err := r.db.First(&library, id).Error
	return &library, err
}

func (r *LibraryRepository) FindByPath(path string) (*models.MediaLibrary, error) {
	var library models.MediaLibrary
	err := r.db.Where("path = ?", path).First(&library).Error
	return &library, err
}

func (r *LibraryRepository) Create(library *models.MediaLibrary) error {
	return r.db.Create(library).Error
}

func (r *LibraryRepository) Update(library *models.MediaLibrary) error {
	return r.db.Save(library).Error
}

func (r *LibraryRepository) Delete(id uint) error {
	return r.db.Delete(&models.MediaLibrary{}, id).Error
}
```

- [ ] **Step 9: Commit**

```bash
git add backend/internal/repository/
git commit -m "feat: add GORM repositories for all models"
```

---

## Task 5: Email Service

**Covers:** [S4]

**Files:**
- Create: `backend/internal/email/smtp.go`
- Create: `backend/internal/email/smtp_test.go`

- [ ] **Step 1: Write failing test for email sending**

```go
package email

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestGenerateCode(t *testing.T) {
	code := GenerateCode(6)
	assert.Len(t, code, 6)
	assert.Regexp(t, `^\d{6}$`, code)
}

func TestNewSMTPClient(t *testing.T) {
	client := NewSMTPClient(SMTPConfig{
		Host:     "smtp.test.com",
		Port:     587,
		Username: "test@test.com",
		Password: "password",
		From:     "Test <test@test.com>",
	})
	assert.NotNil(t, client)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/email/ -v`
Expected: FAIL with "undefined: GenerateCode"

- [ ] **Step 3: Implement email service**

```go
package email

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"net/smtp"
)

type SMTPConfig struct {
	Host     string
	Port     int
	Username string
	Password string
	From     string
}

type SMTPClient struct {
	config SMTPConfig
}

func NewSMTPClient(config SMTPConfig) *SMTPClient {
	return &SMTPClient{config: config}
}

func GenerateCode(length int) string {
	code := ""
	for i := 0; i < length; i++ {
		n, _ := rand.Int(rand.Reader, big.NewInt(10))
		code += fmt.Sprintf("%d", n.Int64())
	}
	return code
}

func (c *SMTPClient) SendCode(to string, code string) error {
	subject := "Flux Media Server - Login Code"
	body := fmt.Sprintf("Your login code is: %s\n\nThis code will expire in 5 minutes.", code)
	msg := fmt.Sprintf("From: %s\nTo: %s\nSubject: %s\n\n%s", c.config.From, to, subject, body)

	addr := fmt.Sprintf("%s:%d", c.config.Host, c.config.Port)
	auth := smtp.PlainAuth("", c.config.Username, c.config.Password, c.config.Host)

	return smtp.SendMail(addr, auth, c.config.Username, []string{to}, []byte(msg))
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/email/ -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/email/
git commit -m "feat: add SMTP email service for OTP codes"
```

---

## Task 6: Auth Service

**Covers:** [S4]

**Files:**
- Create: `backend/internal/services/auth.go`
- Create: `backend/internal/services/auth_test.go`

- [ ] **Step 1: Write failing test for OTP generation and verification**

```go
package services

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestGenerateOTP(t *testing.T) {
	store := NewOTPStore(5 * time.Minute)
	code := store.Generate("test@example.com")
	assert.Len(t, code, 6)
}

func TestVerifyOTP(t *testing.T) {
	store := NewOTPStore(5 * time.Minute)
	code := store.Generate("test@example.com")

	valid := store.Verify("test@example.com", code)
	assert.True(t, valid)

	// Verify code is consumed after use
	valid = store.Verify("test@example.com", code)
	assert.False(t, valid)
}

func TestVerifyOTPExpired(t *testing.T) {
	store := NewOTPStore(0 * time.Millisecond)
	code := store.Generate("test@example.com")

	time.Sleep(10 * time.Millisecond)

	valid := store.Verify("test@example.com", code)
	assert.False(t, valid)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/services/ -v -run TestGenerateOTP`
Expected: FAIL with "undefined: NewOTPStore"

- [ ] **Step 3: Implement OTP store**

```go
package services

import (
	"sync"
	"time"

	"flux/internal/email"
)

type OTPEntry struct {
	Code      string
	ExpiresAt time.Time
}

type OTPStore struct {
	mu      sync.RWMutex
	entries map[string]*OTPEntry
	ttl     time.Duration
}

func NewOTPStore(ttl time.Duration) *OTPStore {
	return &OTPStore{
		entries: make(map[string]*OTPEntry),
		ttl:     ttl,
	}
}

func (s *OTPStore) Generate(email string) string {
	code := email.GenerateCode(6)

	s.mu.Lock()
	defer s.mu.Unlock()

	s.entries[email] = &OTPEntry{
		Code:      code,
		ExpiresAt: time.Now().Add(s.ttl),
	}

	return code
}

func (s *OTPStore) Verify(email, code string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	entry, exists := s.entries[email]
	if !exists {
		return false
	}

	if time.Now().After(entry.ExpiresAt) {
		delete(s.entries, email)
		return false
	}

	if entry.Code != code {
		return false
	}

	delete(s.entries, email)
	return true
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/services/ -v -run TestGenerateOTP`
Expected: PASS

- [ ] **Step 5: Implement JWT service**

```go
package services

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type JWTService struct {
	secret     []byte
	expiry     time.Duration
}

type Claims struct {
	UserID uint   `json:"user_id"`
	Email  string `json:"email"`
	jwt.RegisteredClaims
}

func NewJWTService(secret string, expiry time.Duration) *JWTService {
	return &JWTService{
		secret: []byte(secret),
		expiry: expiry,
	}
}

func (s *JWTService) GenerateToken(userID uint, email string) (string, error) {
	claims := Claims{
		UserID: userID,
		Email:  email,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(s.expiry)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(s.secret)
}

func (s *JWTService) ValidateToken(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		return s.secret, nil
	})

	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token")
	}

	return claims, nil
}
```

- [ ] **Step 6: Commit**

```bash
git add backend/internal/services/auth.go
git commit -m "feat: add OTP store and JWT service"
```

---

## Task 7: Auth Handler

**Covers:** [S4]

**Files:**
- Create: `backend/internal/handlers/auth.go`

- [ ] **Step 1: Implement auth handler**

```go
package handlers

import (
	"github.com/gofiber/fiber/v2"

	"flux/internal/config"
	"flux/internal/email"
	"flux/internal/repository"
	"flux/internal/services"
)

type AuthHandler struct {
	userRepo    *repository.UserRepository
	otpStore    *services.OTPStore
	jwtService  *services.JWTService
	smtpClient  *email.SMTPClient
	config      *config.Config
}

func NewAuthHandler(
	userRepo *repository.UserRepository,
	otpStore *services.OTPStore,
	jwtService *services.JWTService,
	smtpClient *email.SMTPClient,
	config *config.Config,
) *AuthHandler {
	return &AuthHandler{
		userRepo:   userRepo,
		otpStore:   otpStore,
		jwtService: jwtService,
		smtpClient: smtpClient,
		config:     config,
	}
}

type RequestCodeRequest struct {
	Email string `json:"email"`
}

type VerifyCodeRequest struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

func (h *AuthHandler) RequestCode(c *fiber.Ctx) error {
	var req RequestCodeRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	// Check if email is allowed
	allowed := false
	for _, email := range h.config.Auth.AllowedEmails {
		if email == req.Email {
			allowed = true
			break
		}
	}

	if !allowed && !h.config.Auth.AllowUnknownEmail {
		return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
			"error": "Email not allowed",
		})
	}

	// Generate and send OTP code
	code := h.otpStore.Generate(req.Email)
	if err := h.smtpClient.SendCode(req.Email, code); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to send code",
		})
	}

	return c.JSON(fiber.Map{
		"message": "Code sent successfully",
	})
}

func (h *AuthHandler) VerifyCode(c *fiber.Ctx) error {
	var req VerifyCodeRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	// Verify OTP code
	if !h.otpStore.Verify(req.Email, req.Code) {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Invalid or expired code",
		})
	}

	// Find or create user
	user, err := h.userRepo.FindByEmail(req.Email)
	if err != nil {
		user = &models.User{
			Email:       req.Email,
			DisplayName: req.Email,
		}
		if err := h.userRepo.Create(user); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to create user",
			})
		}
	}

	// Generate JWT token
	token, err := h.jwtService.GenerateToken(user.ID, user.Email)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to generate token",
		})
	}

	return c.JSON(fiber.Map{
		"token": token,
		"user": fiber.Map{
			"id":           user.ID,
			"email":        user.Email,
			"display_name": user.DisplayName,
		},
	})
}

func (h *AuthHandler) Me(c *fiber.Ctx) error {
	userID := c.Locals("user_id").(uint)

	user, err := h.userRepo.FindByID(userID)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "User not found",
		})
	}

	return c.JSON(fiber.Map{
		"id":           user.ID,
		"email":        user.Email,
		"display_name": user.DisplayName,
		"avatar_url":   user.AvatarURL,
	})
}
```

- [ ] **Step 2: Commit**

```bash
git add backend/internal/handlers/auth.go
git commit -m "feat: add auth handler with request-code and verify-code endpoints"
```

---

## Task 8: Auth Middleware

**Covers:** [S4]

**Files:**
- Create: `backend/internal/middleware/auth.go`

- [ ] **Step 1: Implement JWT middleware**

```go
package middleware

import (
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/services"
)

func AuthMiddleware(jwtService *services.JWTService) fiber.Handler {
	return func(c *fiber.Ctx) error {
		authHeader := c.Get("Authorization")
		if authHeader == "" {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Missing authorization header",
			})
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Invalid authorization header format",
			})
		}

		claims, err := jwtService.ValidateToken(parts[1])
		if err != nil {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Invalid or expired token",
			})
		}

		c.Locals("user_id", claims.UserID)
		c.Locals("user_email", claims.Email)

		return c.Next()
	}
}
```

- [ ] **Step 2: Commit**

```bash
git add backend/internal/middleware/
git commit -m "feat: add JWT authentication middleware"
```

---

## Task 9: Media Handler

**Covers:** [S2, S3]

**Files:**
- Create: `backend/internal/handlers/media.go`

- [ ] **Step 1: Implement media handler**

```go
package handlers

import (
	"github.com/gofiber/fiber/v2"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

type MediaHandler struct {
	mediaRepo *repository.MediaRepository
	streamer  *services.StreamerService
}

func NewMediaHandler(mediaRepo *repository.MediaRepository, streamer *services.StreamerService) *MediaHandler {
	return &MediaHandler{
		mediaRepo: mediaRepo,
		streamer:  streamer,
	}
}

type CreateMediaRequest struct {
	Title       string `json:"title"`
	Year        int    `json:"year"`
	Description string `json:"description"`
	Type        string `json:"type"`
	FilePath    string `json:"file_path"`
}

func (h *MediaHandler) List(c *fiber.Ctx) error {
	filters := make(map[string]interface{})

	if mediaType := c.Query("type"); mediaType != "" {
		filters["type"] = mediaType
	}
	if year := c.Query("year"); year != "" {
		filters["year"] = year
	}

	media, err := h.mediaRepo.FindAll(filters)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch media",
		})
	}

	return c.JSON(media)
}

func (h *MediaHandler) Get(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid media ID",
		})
	}

	media, err := h.mediaRepo.FindByID(uint(id))
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Media not found",
		})
	}

	return c.JSON(media)
}

func (h *MediaHandler) Create(c *fiber.Ctx) error {
	var req CreateMediaRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	media := &models.Media{
		Title:       req.Title,
		Year:        req.Year,
		Description: req.Description,
		Type:        req.Type,
		FilePath:    req.FilePath,
	}

	if err := h.mediaRepo.Create(media); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to create media",
		})
	}

	return c.Status(fiber.StatusCreated).JSON(media)
}

func (h *MediaHandler) Update(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid media ID",
		})
	}

	media, err := h.mediaRepo.FindByID(uint(id))
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Media not found",
		})
	}

	var req CreateMediaRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	media.Title = req.Title
	media.Year = req.Year
	media.Description = req.Description
	media.Type = req.Type
	media.FilePath = req.FilePath

	if err := h.mediaRepo.Update(media); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to update media",
		})
	}

	return c.JSON(media)
}

func (h *MediaHandler) Delete(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid media ID",
		})
	}

	if err := h.mediaRepo.Delete(uint(id)); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to delete media",
		})
	}

	return c.JSON(fiber.Map{
		"message": "Media deleted successfully",
	})
}

func (h *MediaHandler) Stream(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid media ID",
		})
	}

	media, err := h.mediaRepo.FindByID(uint(id))
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Media not found",
		})
	}

	return h.streamer.Stream(c, media.FilePath)
}
```

- [ ] **Step 2: Commit**

```bash
git add backend/internal/handlers/media.go
git commit -m "feat: add media handler with CRUD and streaming"
```

---

## Task 10: Filename Parser

**Covers:** [S7]

**Files:**
- Create: `backend/internal/metadata/parser.go`
- Create: `backend/internal/metadata/parser_test.go`

- [ ] **Step 1: Write failing test for filename parsing**

```go
package metadata

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestParseFilename(t *testing.T) {
	tests := []struct {
		filename string
		title    string
		year     int
	}{
		{"The.Matrix.1999.mkv", "The Matrix", 1999},
		{"Inception (2010).mp4", "Inception", 2010},
		{"Breaking.Bad.S01E01.Pilot.mkv", "Breaking Bad", 0},
		{"Movie Name (2024).avi", "Movie Name", 2024},
	}

	for _, tt := range tests {
		t.Run(tt.filename, func(t *testing.T) {
			title, year := ParseFilename(tt.filename)
			assert.Equal(t, tt.title, title)
			assert.Equal(t, tt.year, year)
		})
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/metadata/ -v`
Expected: FAIL with "undefined: ParseFilename"

- [ ] **Step 3: Implement filename parser**

```go
package metadata

import (
	"regexp"
	"strconv"
	"strings"
)

var (
	// Pattern: Title.Year.Extension
	dotPattern = regexp.MustCompile(`^(.+)\.(\d{4})\.[^.]+$`)
	// Pattern: Title (Year).Extension
	parenPattern = regexp.MustCompile(`^(.+)\s*\((\d{4})\)\.[^.]+$`)
	// Pattern: Series.S01E05.Episode.mkv
	episodePattern = regexp.MustCompile(`^(.+)\.S(\d{2})E(\d{2})\..+$`)
)

func ParseFilename(filename string) (string, int) {
	// Try dot pattern: Title.Year.Extension
	if matches := dotPattern.FindStringSubmatch(filename); matches != nil {
		title := strings.ReplaceAll(matches[1], ".", " ")
		year, _ := strconv.Atoi(matches[2])
		return title, year
	}

	// Try paren pattern: Title (Year).Extension
	if matches := parenPattern.FindStringSubmatch(filename); matches != nil {
		title := strings.TrimSpace(matches[1])
		year, _ := strconv.Atoi(matches[2])
		return title, year
	}

	// Try episode pattern: Series.S01E05.Episode
	if matches := episodePattern.FindStringSubmatch(filename); matches != nil {
		title := strings.ReplaceAll(matches[1], ".", " ")
		return title, 0
	}

	// Fallback: use filename without extension
	parts := strings.Split(filename, ".")
	if len(parts) > 1 {
		parts = parts[:len(parts)-1]
	}
	return strings.Join(parts, " "), 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/metadata/ -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/metadata/
git commit -m "feat: add filename parser for media metadata"
```

---

## Task 11: Scanner Service

**Covers:** [S7]

**Files:**
- Create: `backend/internal/services/scanner.go`

- [ ] **Step 1: Implement scanner service**

```go
package services

import (
	"log"
	"os"
	"path/filepath"
	"strings"

	"flux/internal/config"
	"flux/internal/metadata"
	"flux/internal/models"
	"flux/internal/repository"
)

type ScannerService struct {
	libraryRepo *repository.LibraryRepository
	mediaRepo   *repository.MediaRepository
	config      *config.Config
}

func NewScannerService(
	libraryRepo *repository.LibraryRepository,
	mediaRepo *repository.MediaRepository,
	config *config.Config,
) *ScannerService {
	return &ScannerService{
		libraryRepo: libraryRepo,
		mediaRepo:   mediaRepo,
		config:      config,
	}
}

func (s *ScannerService) ScanAll() error {
	libraries, err := s.libraryRepo.FindAll()
	if err != nil {
		return err
	}

	for _, lib := range libraries {
		if lib.Enabled {
			if err := s.ScanLibrary(&lib); err != nil {
				log.Printf("Error scanning library %s: %v", lib.Name, err)
			}
		}
	}

	return nil
}

func (s *ScannerService) ScanLibrary(library *models.MediaLibrary) error {
	return filepath.Walk(library.Path, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if info.IsDir() {
			return nil
		}

		// Check file extension
		ext := strings.ToLower(filepath.Ext(path))
		allowed := false
		for _, e := range s.config.Media.AllowedExtensions {
			if ext == e {
				allowed = true
				break
			}
		}

		if !allowed {
			return nil
		}

		// Check if file already exists in database
		existing, _ := s.mediaRepo.FindByPath(path)
		if existing != nil {
			return nil
		}

		// Parse filename for metadata
		title, year := metadata.ParseFilename(filepath.Base(path))

		// Determine media type
		mediaType := "movie"
		if library.Type == "tv" {
			mediaType = "episode"
		}

		// Get file info
		fileInfo, err := os.Stat(path)
		if err != nil {
			return err
		}

		// Create media record
		media := &models.Media{
			Title:    title,
			Year:     year,
			Type:     mediaType,
			FilePath: path,
			FileSize: fileInfo.Size(),
		}

		if err := s.mediaRepo.Create(media); err != nil {
			log.Printf("Error creating media record for %s: %v", path, err)
		}

		return nil
	})
}
```

- [ ] **Step 2: Commit**

```bash
git add backend/internal/services/scanner.go
git commit -m "feat: add scanner service for automatic media discovery"
```

---

## Task 12: Library Handler

**Covers:** [S2, S7]

**Files:**
- Create: `backend/internal/handlers/library.go`

- [ ] **Step 1: Implement library handler**

```go
package handlers

import (
	"github.com/gofiber/fiber/v2"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

type LibraryHandler struct {
	libraryRepo *repository.LibraryRepository
	scanner     *services.ScannerService
}

func NewLibraryHandler(libraryRepo *repository.LibraryRepository, scanner *services.ScannerService) *LibraryHandler {
	return &LibraryHandler{
		libraryRepo: libraryRepo,
		scanner:     scanner,
	}
}

type CreateLibraryRequest struct {
	Name         string `json:"name"`
	Path         string `json:"path"`
	Type         string `json:"type"`
	ScanInterval int    `json:"scan_interval"`
}

func (h *LibraryHandler) List(c *fiber.Ctx) error {
	libraries, err := h.libraryRepo.FindAll()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch libraries",
		})
	}

	return c.JSON(libraries)
}

func (h *LibraryHandler) Create(c *fiber.Ctx) error {
	var req CreateLibraryRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	library := &models.MediaLibrary{
		Name:         req.Name,
		Path:         req.Path,
		Type:         req.Type,
		Enabled:      true,
		ScanInterval: req.ScanInterval,
	}

	if err := h.libraryRepo.Create(library); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to create library",
		})
	}

	return c.Status(fiber.StatusCreated).JSON(library)
}

func (h *LibraryHandler) Update(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid library ID",
		})
	}

	library, err := h.libraryRepo.FindByID(uint(id))
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Library not found",
		})
	}

	var req CreateLibraryRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	library.Name = req.Name
	library.Path = req.Path
	library.Type = req.Type
	library.ScanInterval = req.ScanInterval

	if err := h.libraryRepo.Update(library); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to update library",
		})
	}

	return c.JSON(library)
}

func (h *LibraryHandler) Delete(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid library ID",
		})
	}

	if err := h.libraryRepo.Delete(uint(id)); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to delete library",
		})
	}

	return c.JSON(fiber.Map{
		"message": "Library deleted successfully",
	})
}

func (h *LibraryHandler) Scan(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid library ID",
		})
	}

	library, err := h.libraryRepo.FindByID(uint(id))
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Library not found",
		})
	}

	go func() {
		if err := h.scanner.ScanLibrary(library); err != nil {
			log.Printf("Error scanning library %s: %v", library.Name, err)
		}
	}()

	return c.JSON(fiber.Map{
		"message": "Scan started",
	})
}
```

- [ ] **Step 2: Commit**

```bash
git add backend/internal/handlers/library.go
git commit -m "feat: add library handler with CRUD and scan trigger"
```

---

## Task 13: Progress Handler

**Covers:** [S3]

**Files:**
- Create: `backend/internal/handlers/progress.go`

- [ ] **Step 1: Implement progress handler**

```go
package handlers

import (
	"github.com/gofiber/fiber/v2"

	"flux/internal/models"
	"flux/internal/repository"
)

type ProgressHandler struct {
	progressRepo *repository.ProgressRepository
}

func NewProgressHandler(progressRepo *repository.ProgressRepository) *ProgressHandler {
	return &ProgressHandler{
		progressRepo: progressRepo,
	}
}

type UpdateProgressRequest struct {
	Position  int  `json:"position"`
	Duration  int  `json:"duration"`
	Completed bool `json:"completed"`
}

func (h *ProgressHandler) List(c *fiber.Ctx) error {
	userID := c.Locals("user_id").(uint)

	progress, err := h.progressRepo.FindByUser(userID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch progress",
		})
	}

	return c.JSON(progress)
}

func (h *ProgressHandler) Update(c *fiber.Ctx) error {
	userID := c.Locals("user_id").(uint)
	mediaID, err := c.ParamsInt("mediaId")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid media ID",
		})
	}

	var req UpdateProgressRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	progress, err := h.progressRepo.FindByUserAndMedia(userID, uint(mediaID))
	if err != nil {
		progress = &models.WatchProgress{
			UserID:  userID,
			MediaID: uint(mediaID),
		}
	}

	progress.Position = req.Position
	progress.Duration = req.Duration
	progress.Completed = req.Completed

	if err := h.progressRepo.Upsert(progress); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to update progress",
		})
	}

	return c.JSON(progress)
}

func (h *ProgressHandler) Delete(c *fiber.Ctx) error {
	userID := c.Locals("user_id").(uint)
	mediaID, err := c.ParamsInt("mediaId")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid media ID",
		})
	}

	if err := h.progressRepo.Delete(userID, uint(mediaID)); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to delete progress",
		})
	}

	return c.JSON(fiber.Map{
		"message": "Progress deleted successfully",
	})
}
```

- [ ] **Step 2: Commit**

```bash
git add backend/internal/handlers/progress.go
git commit -m "feat: add progress handler for watch history"
```

---

## Task 14: Streamer Service

**Covers:** [S6]

**Files:**
- Create: `backend/internal/services/streamer.go`

- [ ] **Step 1: Implement streamer service**

```go
package services

import (
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type StreamerService struct{}

func NewStreamerService() *StreamerService {
	return &StreamerService{}
}

func (s *StreamerService) Stream(c *fiber.Ctx, filePath string) error {
	file, err := os.Open(filePath)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to open file",
		})
	}
	defer file.Close()

	// Get file size
	stat, err := file.Stat()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to get file info",
		})
	}

	fileSize := stat.Size()

	// Set content type based on extension
	ext := strings.ToLower(filePath[strings.LastIndex(filePath, "."):])
	contentType := "application/octet-stream"
	switch ext {
	case ".mp4":
		contentType = "video/mp4"
	case ".mkv":
		contentType = "video/x-matroska"
	case ".avi":
		contentType = "video/x-msvideo"
	case ".mov":
		contentType = "video/quicktime"
	}

	// Handle Range request
	rangeHeader := c.Get("Range")
	if rangeHeader != "" {
		ranges := strings.Replace(rangeHeader, "bytes=", "", 1)
		parts := strings.Split(ranges, "-")

		start, _ := strconv.ParseInt(parts[0], 10, 64)
		end := fileSize - 1
		if len(parts) > 1 && parts[1] != "" {
			end, _ = strconv.ParseInt(parts[1], 10, 64)
		}

		contentLength := end - start + 1

		c.Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, fileSize))
		c.Set("Content-Length", strconv.FormatInt(contentLength, 10))
		c.Set("Accept-Ranges", "bytes")
		c.Status(fiber.StatusPartialContent)

		file.Seek(start, io.SeekStart)
		io.CopyN(c.Response().BodyWriter(), file, contentLength)
	} else {
		c.Set("Content-Length", strconv.FormatInt(fileSize, 10))
		c.Set("Accept-Ranges", "bytes")
		io.Copy(c.Response().BodyWriter(), file)
	}

	c.Set("Content-Type", contentType)
	return nil
}
```

- [ ] **Step 2: Commit**

```bash
git add backend/internal/services/streamer.go
git commit -m "feat: add streamer service with Range header support"
```

---

## Task 15: Main Server Setup

**Covers:** [S1, S2]

**Files:**
- Modify: `backend/cmd/server/main.go`

- [ ] **Step 1: Update main.go with all handlers and routes**

```go
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
	// Load config
	configPath := os.Getenv("CONFIG_PATH")
	if configPath == "" {
		configPath = "configs/config.yaml"
	}

	cfg, err := config.Load(configPath)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Initialize database
	db, err := repository.InitDB(cfg.Database.Path)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	// Auto migrate
	if err := repository.AutoMigrate(db); err != nil {
		log.Fatalf("Failed to migrate database: %v", err)
	}

	// Initialize repositories
	userRepo := repository.NewUserRepository(db)
	mediaRepo := repository.NewMediaRepository(db)
	progressRepo := repository.NewProgressRepository(db)
	libraryRepo := repository.NewLibraryRepository(db)

	// Initialize services
	otpStore := services.NewOTPStore(time.Duration(cfg.Auth.CodeExpiry) * time.Second)
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

	// Initialize handlers
	authHandler := handlers.NewAuthHandler(userRepo, otpStore, jwtService, smtpClient, cfg)
	mediaHandler := handlers.NewMediaHandler(mediaRepo, streamer)
	libraryHandler := handlers.NewLibraryHandler(libraryRepo, scanner)
	progressHandler := handlers.NewProgressHandler(progressRepo)

	// Create Fiber app
	app := fiber.New()

	// Auth routes
	auth := app.Group("/api/auth")
	auth.Post("/request-code", authHandler.RequestCode)
	auth.Post("/verify-code", authHandler.VerifyCode)

	// Protected routes
	api := app.Group("/api", middleware.AuthMiddleware(jwtService))

	// Auth routes
	api.Get("/auth/me", authHandler.Me)

	// Media routes
	media := api.Group("/media")
	media.Get("", mediaHandler.List)
	media.Get("/:id", mediaHandler.Get)
	media.Post("", mediaHandler.Create)
	media.Put("/:id", mediaHandler.Update)
	media.Delete("/:id", mediaHandler.Delete)
	media.Get("/:id/stream", mediaHandler.Stream)

	// Library routes
	library := api.Group("/libraries")
	library.Get("", libraryHandler.List)
	library.Post("", libraryHandler.Create)
	library.Put("/:id", libraryHandler.Update)
	library.Delete("/:id", libraryHandler.Delete)
	library.Post("/:id/scan", libraryHandler.Scan)

	// Progress routes
	progress := api.Group("/progress")
	progress.Get("", progressHandler.List)
	progress.Put("/:mediaId", progressHandler.Update)
	progress.Delete("/:mediaId", progressHandler.Delete)

	// Start server
	port := cfg.Server.Port
	if port == 0 {
		port = 8080
	}

	log.Printf("Flux Media Server starting on port %d", port)
	log.Fatal(app.Listen(fmt.Sprintf(":%d", port)))
}
```

- [ ] **Step 2: Commit**

```bash
git add backend/cmd/server/main.go
git commit -m "feat: complete server setup with all routes and handlers"
```

---

## Task 16: Run All Tests

**Covers:** [S1-S7]

**Files:**
- None (verification step)

- [ ] **Step 1: Run all tests**

Run: `cd backend && go test ./... -v`
Expected: All tests PASS

- [ ] **Step 2: Build the server**

Run: `cd backend && go build -o flux-server ./cmd/server`
Expected: Build succeeds

- [ ] **Step 3: Verify server starts**

Run: `cd backend && ./flux-server`
Expected: Server starts on :8080

- [ ] **Step 4: Final commit**

```bash
git add .
git commit -m "feat: Flux Media Server MVP complete"
```

---

## Summary

This plan implements the Flux Media Server backend with:

1. **Configuration** - YAML-based config loading
2. **Database** - SQLite with GORM, auto-migration
3. **Authentication** - Email OTP + JWT tokens
4. **Media CRUD** - Create, read, update, delete media items
5. **File Scanning** - Automatic discovery of media files
6. **Filename Parsing** - Extract metadata from filenames
7. **Streaming** - Direct Play with Range header support
8. **Progress Tracking** - Watch history per user
9. **Library Management** - Organize media into libraries

**Future phases (not in this plan):**
- External API integration (TMDB, TVDB, MusicBrainz)
- Audio support (music)
- Book support (EPUB, PDF)
- Transcoding with FFmpeg
- Subtitles support
- DLNA/UPnP server
