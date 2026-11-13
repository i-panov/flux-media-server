package services

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"sync"
	"time"

	"flux/internal/email"

	"github.com/golang-jwt/jwt/v5"
)

var (
	ErrOTPStoreFull       = errors.New("otp store is full")
	ErrOTPTooManyAttempts = errors.New("too many otp attempts")
)

// MaxOTPAttempts is the number of failed verification attempts after which
// the code is invalidated (anti brute-force).
const MaxOTPAttempts = 5

type OTPEntry struct {
	Code      string
	ExpiresAt time.Time
	Attempts  int
}

type OTPStore struct {
	mu            sync.RWMutex
	entries       map[string]*OTPEntry
	failures      map[string]int
	failureExpiry map[string]time.Time
	ttl           time.Duration
	codeLength    int
	maxEntries    int
	stopChan      chan struct{}
}

func NewOTPStore(ttl time.Duration, codeLength int, maxEntries int) *OTPStore {
	if maxEntries <= 0 {
		maxEntries = 10000
	}
	s := &OTPStore{
		entries:       make(map[string]*OTPEntry),
		failures:      make(map[string]int),
		failureExpiry: make(map[string]time.Time),
		ttl:           ttl,
		codeLength:    codeLength,
		maxEntries:    maxEntries,
		stopChan:      make(chan struct{}),
	}
	go s.cleanupLoop()
	return s
}

func (s *OTPStore) cleanupLoop() {
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			s.cleanup()
		case <-s.stopChan:
			return
		}
	}
}

func (s *OTPStore) cleanup() {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	for email, entry := range s.entries {
		if now.After(entry.ExpiresAt) {
			delete(s.entries, email)
		}
	}
	for email, until := range s.failureExpiry {
		if now.After(until) {
			delete(s.failures, email)
			delete(s.failureExpiry, email)
		}
	}
}

// Stop останавливает фоновую горутину очистки истёкших кодов.
// Generate/Verify после этого продолжают работать (блокировки живые),
// но истёкшие записи больше не чистятся фоном — они удаляются
// лениво при обращениях к Verify.
func (s *OTPStore) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()
	select {
	case <-s.stopChan:
		// already closed
	default:
		close(s.stopChan)
	}
}

func (s *OTPStore) Generate(addr string) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Счётчик неудач живёт на email, а не на конкретном коде:
	// перевыпуск кода не должен сбрасывать защиту от перебора.
	if s.failures[addr] >= MaxOTPAttempts {
		if until, ok := s.failureExpiry[addr]; ok && time.Now().Before(until) {
			return "", ErrOTPTooManyAttempts
		}
		delete(s.failures, addr)
		delete(s.failureExpiry, addr)
	}
	// Allow overwriting existing entry for the same address. Проверка
	// переполнения ДО генерации кода: не тратим crypto/rand впустую.
	if _, exists := s.entries[addr]; !exists && len(s.entries) >= s.maxEntries {
		return "", ErrOTPStoreFull
	}

	code, err := email.GenerateCode(s.codeLength)
	if err != nil {
		return "", err
	}

	s.entries[addr] = &OTPEntry{
		Code:      code,
		ExpiresAt: time.Now().Add(s.ttl),
	}

	return code, nil
}

// Remove удаляет код для адреса. Используется, когда отправка письма не
// удалась — несостоявшийся код не должен оставаться в сторе.
func (s *OTPStore) Remove(addr string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.entries, addr)
}

func (s *OTPStore) Verify(email, code string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	entry, exists := s.entries[email]
	if !exists {
		return false
	}

	// Double protection: empty codes bypass ConstantTimeCompare
	if entry.Code == "" || code == "" {
		delete(s.entries, email)
		return false
	}

	if time.Now().After(entry.ExpiresAt) {
		delete(s.entries, email)
		return false
	}

	// Constant-time comparison to avoid timing attacks.
	if subtle.ConstantTimeCompare([]byte(entry.Code), []byte(code)) != 1 {
		entry.Attempts++
		s.failures[email]++
		s.failureExpiry[email] = time.Now().Add(15 * time.Minute)
		if entry.Attempts >= MaxOTPAttempts || s.failures[email] >= MaxOTPAttempts {
			// Invalidate the code after too many failed attempts.
			delete(s.entries, email)
		}
		return false
	}

	delete(s.entries, email)
	delete(s.failures, email)
	delete(s.failureExpiry, email)
	return true
}

type JWTManager struct {
	secret        []byte
	expiry        time.Duration
	refreshExpiry time.Duration
}

// Token types stored in the "type" claim to distinguish access and refresh tokens.
const (
	TokenTypeAccess  = "access"
	TokenTypeRefresh = "refresh"
)

type Claims struct {
	UserID uint   `json:"user_id"`
	Email  string `json:"email"`
	Type   string `json:"type"`
	jwt.RegisteredClaims
}

type TokenPair struct {
	AccessToken  string
	RefreshToken string
}

func NewJWTService(secret string, expiry time.Duration, refreshExpiry time.Duration) *JWTManager {
	return &JWTManager{
		secret:        []byte(secret),
		expiry:        expiry,
		refreshExpiry: refreshExpiry,
	}
}

func (s *JWTManager) GenerateToken(userID uint, email string) (string, error) {
	return s.generateToken(userID, email, TokenTypeAccess, s.expiry)
}

func (s *JWTManager) GenerateRefreshToken(userID uint, email string) (string, error) {
	return s.generateToken(userID, email, TokenTypeRefresh, s.refreshExpiry)
}

func (s *JWTManager) generateToken(userID uint, email, tokenType string, expiry time.Duration) (string, error) {
	// jti обязателен: без него два логина одного пользователя в одну
	// секунду дают идентичный refresh JWT и UNIQUE-конфликт в БД.
	jtiBytes := make([]byte, 16)
	if _, err := rand.Read(jtiBytes); err != nil {
		return "", err
	}
	claims := Claims{
		UserID: userID,
		Email:  email,
		Type:   tokenType,
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        hex.EncodeToString(jtiBytes),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(expiry)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(s.secret)
}

func (s *JWTManager) GenerateTokenPair(userID uint, email string) (*TokenPair, error) {
	accessToken, err := s.GenerateToken(userID, email)
	if err != nil {
		return nil, err
	}

	refreshToken, err := s.GenerateRefreshToken(userID, email)
	if err != nil {
		return nil, err
	}

	return &TokenPair{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
	}, nil
}

// ValidateToken validates an access token. Refresh tokens are rejected.
func (s *JWTManager) ValidateToken(tokenString string) (*Claims, error) {
	return s.validateToken(tokenString, TokenTypeAccess)
}

// ValidateRefreshToken validates a refresh token. Access tokens are rejected.
func (s *JWTManager) ValidateRefreshToken(tokenString string) (*Claims, error) {
	return s.validateToken(tokenString, TokenTypeRefresh)
}

func (s *JWTManager) validateToken(tokenString, expectedType string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return s.secret, nil
	}, jwt.WithValidMethods([]string{"HS256"}))

	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token")
	}

	// Токены без type-claim (старый формат) больше не принимаются:
	// grace-период истёк, а пустой type позволял путать access и refresh.
	if claims.Type != expectedType {
		return nil, errors.New("invalid token type")
	}

	return claims, nil
}
