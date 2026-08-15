package services

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- OTPStore security tests ---

func TestOTPVerifyInvalidatesAfterMaxAttempts(t *testing.T) {
	s := newTestOTPStore(t, 5*time.Minute, 6, 100)

	code, err := s.Generate("a@b.c")
	require.NoError(t, err)

	// Exhaust all attempts with a wrong code.
	for i := 0; i < MaxOTPAttempts; i++ {
		assert.False(t, s.Verify("a@b.c", "000000"), "attempt %d should fail", i)
	}

	// Even the correct code must now be rejected.
	assert.False(t, s.Verify("a@b.c", code), "code must be invalidated after max attempts")
}

func TestOTPVerifySuccessOnFirstTry(t *testing.T) {
	s := newTestOTPStore(t, 5*time.Minute, 6, 100)

	code, err := s.Generate("a@b.c")
	require.NoError(t, err)
	assert.True(t, s.Verify("a@b.c", code))

	// One-time use: second verification fails.
	assert.False(t, s.Verify("a@b.c", code))
}

func TestOTPVerifyExpired(t *testing.T) {
	// Отрицательный TTL — код истёк сразу после генерации; детерминированно
	// и без time.Sleep.
	s := newTestOTPStore(t, -time.Minute, 6, 100)

	code, err := s.Generate("a@b.c")
	require.NoError(t, err)

	assert.False(t, s.Verify("a@b.c", code))
}

// --- JWT token type tests ---

func newTestJWT() *JWTManager {
	return NewJWTService("test-secret-key-that-is-long-enough-32chars", time.Hour, 720*time.Hour)
}

func TestJWTRefreshTokenRejectedAsAccessToken(t *testing.T) {
	j := newTestJWT()

	refresh, err := j.GenerateRefreshToken(1, "a@b.c")
	require.NoError(t, err)

	// A refresh token must NOT pass access-token validation (middleware).
	_, err = j.ValidateToken(refresh)
	assert.Error(t, err, "refresh token must not be usable as access token")

	// But it passes refresh validation.
	claims, err := j.ValidateRefreshToken(refresh)
	require.NoError(t, err)
	assert.Equal(t, uint(1), claims.UserID)
	assert.Equal(t, TokenTypeRefresh, claims.Type)
}

func TestJWTAccessTokenRejectedAsRefreshToken(t *testing.T) {
	j := newTestJWT()

	access, err := j.GenerateToken(1, "a@b.c")
	require.NoError(t, err)

	_, err = j.ValidateRefreshToken(access)
	assert.Error(t, err, "access token must not be usable as refresh token")

	claims, err := j.ValidateToken(access)
	require.NoError(t, err)
	assert.Equal(t, TokenTypeAccess, claims.Type)
}

func TestJWTRejectsWrongSecret(t *testing.T) {
	j := newTestJWT()
	token, err := j.GenerateToken(1, "a@b.c")
	require.NoError(t, err)

	other := NewJWTService("another-secret-key-that-is-long-enough-32", time.Hour, time.Hour)
	_, err = other.ValidateToken(token)
	assert.Error(t, err)
}

func TestJWTExpiredToken(t *testing.T) {
	j := NewJWTService("test-secret-key-that-is-long-enough-32chars", -time.Hour, time.Hour)
	token, err := j.GenerateToken(1, "a@b.c")
	require.NoError(t, err)

	_, err = j.ValidateToken(token)
	assert.Error(t, err)
}

// issueLegacyToken создаёт токен БЕЗ type-claim (как выпускались до
// введения разделения access/refresh), с заданным IssuedAt и истекающий
// через час от текущего момента — иначе валидация упадёт на expiry
// раньше, чем на проверке type.
func issueLegacyToken(t *testing.T, issuedAt time.Time) string {
	t.Helper()
	claims := Claims{
		UserID: 1,
		Email:  "a@b.c",
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(issuedAt),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
		},
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	s, err := tok.SignedString([]byte("test-secret-key-that-is-long-enough-32chars"))
	require.NoError(t, err)
	return s
}

func TestJWTRejectsLegacyTokenOutsideGracePeriod(t *testing.T) {
	j := newTestJWT()

	// Внутри grace-периода legacy-токен ещё принимается как access
	// (обратная совместимость для токенов, выпущенных до перехода).
	claims, err := j.ValidateToken(issueLegacyToken(t, legacyTokenGraceUntil.Add(-time.Hour)))
	require.NoError(t, err)
	assert.Equal(t, uint(1), claims.UserID)

	// После границы grace-периода токены без type жёстко отвергаются.
	_, err = j.ValidateToken(issueLegacyToken(t, legacyTokenGraceUntil.Add(time.Hour)))
	assert.Error(t, err, "legacy-токен после grace-периода не должен быть access-токеном")

	// Токен без IssuedAt не может подтвердить возраст — отвергается.
	noIat := Claims{
		UserID: 1,
		Email:  "a@b.c",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
		},
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, noIat)
	raw, err := tok.SignedString([]byte("test-secret-key-that-is-long-enough-32chars"))
	require.NoError(t, err)
	_, err = j.ValidateToken(raw)
	assert.Error(t, err, "legacy-токен без IssuedAt должен отвергаться")
}

func TestJWTRejectsLegacyTokenAsRefresh(t *testing.T) {
	j := newTestJWT()

	// Даже в grace-периоде legacy-токен без type не может быть refresh:
	// иначе украденный старый refresh остался бы валидным на месяц.
	_, err := j.ValidateRefreshToken(issueLegacyToken(t, legacyTokenGraceUntil.Add(-time.Hour)))
	assert.Error(t, err)
}

// --- Path sanitization tests ---

func TestSanitizeFilename(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{"normal", "movie.mp4", false},
		{"with spaces", "my movie.mp4", false},
		{"traversal", "../../etc/passwd", true},
		{"traversal windows", `..\..\windows\system32`, true},
		{"subdirectory", "sub/dir/file.mp4", true},
		{"dotdot only", "..", true},
		{"dot only", ".", true},
		{"empty", "", true},
		{"nul byte", "file\x00.mp4", true},
		{"hidden file ok", ".hidden.mp4", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := SanitizeFilename(tt.input)
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.input, got)
			}
		})
	}
}

func TestIsSubPath(t *testing.T) {
	assert.True(t, IsSubPath("/data/video", "/data/video/a.mp4"))
	assert.True(t, IsSubPath("/data/video", "/data/video"))
	assert.False(t, IsSubPath("/data/video", "/data/video2/a.mp4"))
	assert.False(t, IsSubPath("/data/video", "/etc/passwd"))
	assert.False(t, IsSubPath("/data/video", "/data/video/../audio/a.mp3"))
}
