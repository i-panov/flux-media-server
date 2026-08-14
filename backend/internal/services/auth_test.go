package services

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

// newTestOTPStore создаёт OTPStore с автоматической остановкой фоновой
// горутины cleanupLoop — тесты не должны утекать горутинами.
func newTestOTPStore(t *testing.T, ttl time.Duration, codeLength, maxEntries int) *OTPStore {
	t.Helper()
	store := NewOTPStore(ttl, codeLength, maxEntries)
	t.Cleanup(store.Stop)
	return store
}

func TestGenerateOTP(t *testing.T) {
	store := newTestOTPStore(t, 5*time.Minute, 6, 10000)
	code, err := store.Generate("test@example.com")
	assert.NoError(t, err)
	assert.Len(t, code, 6)
}

func TestVerifyOTP(t *testing.T) {
	store := newTestOTPStore(t, 5*time.Minute, 6, 10000)
	code, err := store.Generate("test@example.com")
	assert.NoError(t, err)

	valid := store.Verify("test@example.com", code)
	assert.True(t, valid)

	// Verify code is consumed after use
	valid = store.Verify("test@example.com", code)
	assert.False(t, valid)
}

func TestVerifyOTPExpired(t *testing.T) {
	// TTL отрицательный — код истекает сразу после генерации.
	// Детерминированно, без time.Sleep.
	store := newTestOTPStore(t, -time.Minute, 6, 10000)
	code, err := store.Generate("test@example.com")
	assert.NoError(t, err)

	valid := store.Verify("test@example.com", code)
	assert.False(t, valid)
}

func TestVerifyOTPWrongCode(t *testing.T) {
	store := newTestOTPStore(t, 5*time.Minute, 6, 10000)
	_, err := store.Generate("test@example.com")
	assert.NoError(t, err)

	valid := store.Verify("test@example.com", "000000")
	assert.False(t, valid)
}

func TestVerifyOTPWrongEmail(t *testing.T) {
	store := newTestOTPStore(t, 5*time.Minute, 6, 10000)
	code, err := store.Generate("test@example.com")
	assert.NoError(t, err)

	valid := store.Verify("other@example.com", code)
	assert.False(t, valid)
}

func TestOTPStoreFull(t *testing.T) {
	store := newTestOTPStore(t, 5*time.Minute, 6, 2)

	_, err := store.Generate("user1@example.com")
	assert.NoError(t, err)
	_, err = store.Generate("user2@example.com")
	assert.NoError(t, err)

	// Third unique address should fail
	_, err = store.Generate("user3@example.com")
	assert.ErrorIs(t, err, ErrOTPStoreFull)
}

func TestOTPStoreOverwriteSameAddress(t *testing.T) {
	store := newTestOTPStore(t, 5*time.Minute, 6, 2)

	_, err := store.Generate("user1@example.com")
	assert.NoError(t, err)
	_, err = store.Generate("user2@example.com")
	assert.NoError(t, err)

	// Overwriting existing address should work even when full
	code, err := store.Generate("user1@example.com")
	assert.NoError(t, err)
	assert.Len(t, code, 6)
}

func TestOTPStoreRemove(t *testing.T) {
	store := newTestOTPStore(t, 5*time.Minute, 6, 10000)
	code, err := store.Generate("test@example.com")
	assert.NoError(t, err)

	// После Remove код должен перестать действовать.
	store.Remove("test@example.com")
	assert.False(t, store.Verify("test@example.com", code))
}
