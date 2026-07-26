package services

import (
	"errors"
	"sync"
	"time"

	"flux/internal/email"

	"github.com/golang-jwt/jwt/v5"
)

var ErrOTPStoreFull = errors.New("otp store is full")

type OTPEntry struct {
	Code      string
	ExpiresAt time.Time
}

type OTPStore struct {
	mu         sync.RWMutex
	entries    map[string]*OTPEntry
	ttl        time.Duration
	codeLength int
	maxEntries int
	stopChan   chan struct{}
}

func NewOTPStore(ttl time.Duration, codeLength int, maxEntries int) *OTPStore {
	if maxEntries <= 0 {
		maxEntries = 10000
	}
	s := &OTPStore{
		entries:    make(map[string]*OTPEntry),
		ttl:        ttl,
		codeLength: codeLength,
		maxEntries: maxEntries,
		stopChan:   make(chan struct{}),
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
}

func (s *OTPStore) Stop() {
	close(s.stopChan)
}

func (s *OTPStore) Generate(addr string) (string, error) {
	code := email.GenerateCode(s.codeLength)

	s.mu.Lock()
	defer s.mu.Unlock()

	// Allow overwriting existing entry for the same address
	if _, exists := s.entries[addr]; !exists && len(s.entries) >= s.maxEntries {
		return "", ErrOTPStoreFull
	}

	s.entries[addr] = &OTPEntry{
		Code:      code,
		ExpiresAt: time.Now().Add(s.ttl),
	}

	return code, nil
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

type JWTManager struct {
	secret        []byte
	expiry        time.Duration
	refreshExpiry time.Duration
}

type Claims struct {
	UserID uint   `json:"user_id"`
	Email  string `json:"email"`
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

func (s *JWTManager) GenerateRefreshToken(userID uint, email string) (string, error) {
	claims := Claims{
		UserID: userID,
		Email:  email,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(s.refreshExpiry)),
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

func (s *JWTManager) ValidateToken(tokenString string) (*Claims, error) {
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

func (s *JWTManager) ValidateRefreshToken(tokenString string) (*Claims, error) {
	return s.ValidateToken(tokenString)
}
