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
