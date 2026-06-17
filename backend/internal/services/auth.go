package services

import (
	"errors"
	"sync"
	"time"

	"flux/internal/email"

	"github.com/golang-jwt/jwt/v5"
)

type OTPEntry struct {
	Code      string
	ExpiresAt time.Time
}

type OTPStore struct {
	mu         sync.RWMutex
	entries    map[string]*OTPEntry
	ttl        time.Duration
	codeLength int
	stopChan   chan struct{}
}

func NewOTPStore(ttl time.Duration, codeLength int) *OTPStore {
	s := &OTPStore{
		entries:    make(map[string]*OTPEntry),
		ttl:        ttl,
		codeLength: codeLength,
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

func (s *OTPStore) Generate(addr string) string {
	code := email.GenerateCode(s.codeLength)

	s.mu.Lock()
	defer s.mu.Unlock()

	s.entries[addr] = &OTPEntry{
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

type JWTService struct {
	secret []byte
	expiry time.Duration
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
