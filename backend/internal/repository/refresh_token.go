package repository

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"time"

	"flux/internal/models"

	"gorm.io/gorm"
)

// RefreshTokenRepository stores refresh tokens. Only SHA-256 hashes of the
// tokens are persisted, so a database leak does not compromise live sessions.
type RefreshTokenRepository struct {
	db *gorm.DB
}

func NewRefreshTokenRepository(db *gorm.DB) *RefreshTokenRepository {
	return &RefreshTokenRepository{db: db}
}

// HashRefreshToken returns the SHA-256 hash of a raw refresh token.
func HashRefreshToken(rawToken string) string {
	sum := sha256.Sum256([]byte(rawToken))
	return hex.EncodeToString(sum[:])
}

// Create stores a new refresh token (as a hash) for the user.
func (r *RefreshTokenRepository) Create(ctx context.Context, userID uint, rawToken string, expiresAt time.Time) error {
	record := &models.RefreshToken{
		UserID:    userID,
		Token:     HashRefreshToken(rawToken),
		ExpiresAt: expiresAt,
	}
	return r.db.WithContext(ctx).Create(record).Error
}

func (r *RefreshTokenRepository) FindByToken(ctx context.Context, rawToken string) (*models.RefreshToken, error) {
	var rt models.RefreshToken
	err := r.db.WithContext(ctx).Where("token = ?", HashRefreshToken(rawToken)).First(&rt).Error
	if err != nil {
		return nil, err
	}
	return &rt, nil
}

func (r *RefreshTokenRepository) DeleteByToken(ctx context.Context, rawToken string) error {
	return r.db.WithContext(ctx).Where("token = ?", HashRefreshToken(rawToken)).Delete(&models.RefreshToken{}).Error
}

func (r *RefreshTokenRepository) DeleteByUserID(ctx context.Context, userID uint) error {
	return r.db.WithContext(ctx).Where("user_id = ?", userID).Delete(&models.RefreshToken{}).Error
}

// DeleteExpired removes all expired refresh tokens. Should be called
// periodically to keep the table from growing unboundedly.
func (r *RefreshTokenRepository) DeleteExpired(ctx context.Context) error {
	return r.db.WithContext(ctx).Where("expires_at < ?", time.Now()).Delete(&models.RefreshToken{}).Error
}
