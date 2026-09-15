package services

import (
	"context"
	"time"
)

// JWTService defines the interface for JWT token operations.
type JWTService interface {
	GenerateToken(userID uint, email string) (string, error)
	GenerateRefreshToken(userID uint, email string) (string, error)
	GenerateTokenPair(userID uint, email string) (*TokenPair, error)
	ValidateToken(tokenString string) (*Claims, error)
	ValidateRefreshToken(tokenString string) (*Claims, error)
}

// OTPStoreInterface defines the interface for OTP code operations.
type OTPStoreInterface interface {
	Generate(addr string) (string, error)
	Verify(email, code string) bool
	Remove(addr string)
	Stop()
}

// ScannerInterface defines the interface for scanning operations.
type ScannerInterface interface {
	ScanPath(ctx context.Context, path string) error
	ScanAll(ctx context.Context) error
	// HandleFSEvents обрабатывает пачку событий файловой системы
	// (инкрементальная обработка: создание/изменение/удаление отдельных
	// файлов без полного прохода по библиотеке).
	HandleFSEvents(ctx context.Context, events []FSEvent)
	GetScanStatus(key string) *ScanStatus
}

// ScanStatus represents the current state of a scan.
type ScanStatus struct {
	Running   bool       `json:"running"`
	StartedAt *time.Time `json:"started_at,omitempty"`
	Error     string     `json:"last_error,omitempty"`
}

// StreamerInterface defines the interface for file streaming operations.
// Сервис не знает про HTTP: ResolveStreamPath возвращает разрешённый путь,
// отдачу файла и маппинг ошибок делает хендлер.
type StreamerInterface interface {
	IsPathAllowed(ctx context.Context, filePath string) (bool, error)
	ResolveStreamPath(ctx context.Context, filePath string) (allowed bool, resolvedPath string, err error)
}
