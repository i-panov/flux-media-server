package repository

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"time"

	"flux/internal/models"

	"gorm.io/gorm"
)

// RefreshTokenStore stores refresh tokens. Only SHA-256 hashes of the
// tokens are persisted, so a database leak does not compromise live sessions.
type RefreshTokenStore struct {
	db *gorm.DB
}

func NewRefreshTokenRepository(db *gorm.DB) *RefreshTokenStore {
	return &RefreshTokenStore{db: db}
}

// HashRefreshToken returns the SHA-256 hash of a raw refresh token.
func HashRefreshToken(rawToken string) string {
	sum := sha256.Sum256([]byte(rawToken))
	return hex.EncodeToString(sum[:])
}

// Create stores a new refresh token (as a hash) for the user.
func (r *RefreshTokenStore) Create(ctx context.Context, userID uint, rawToken string, expiresAt time.Time) error {
	record := &models.RefreshToken{
		UserID:    userID,
		Token:     HashRefreshToken(rawToken),
		ExpiresAt: expiresAt,
	}
	return r.db.WithContext(ctx).Create(record).Error
}

// RotateToken atomically finds a token by oldRawToken, deletes it, and
// creates a new one — prevents TOCTOU races during refresh rotation.
//
// Replay protection: the Delete result's RowsAffected is checked. If two
// parallel requests try to rotate the same token, only one can delete the
// row (RowsAffected == 1) and create the new token. The loser either finds
// no row (ErrRecordNotFound) or deletes 0 rows and the transaction fails —
// in both cases no second valid token is created.
func (r *RefreshTokenStore) RotateToken(ctx context.Context, oldRawToken string, userID uint, newRawToken string, expiresAt time.Time) (*models.RefreshToken, error) {
	var rt models.RefreshToken
	oldHash := HashRefreshToken(oldRawToken)
	newHash := HashRefreshToken(newRawToken)
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("token = ? AND user_id = ?", oldHash, userID).First(&rt).Error; err != nil {
			return err
		}
		result := tx.Where("token = ?", oldHash).Delete(&models.RefreshToken{})
		if result.Error != nil {
			return result.Error
		}
		// RowsAffected == 0 means the token was already consumed by a
		// parallel request — reject the replay.
		if result.RowsAffected == 0 {
			return gorm.ErrRecordNotFound
		}
		return tx.Create(&models.RefreshToken{
			UserID:    userID,
			Token:     newHash,
			ExpiresAt: expiresAt,
		}).Error
	})
	return &rt, err
}

func (r *RefreshTokenStore) FindByToken(ctx context.Context, rawToken string) (*models.RefreshToken, error) {
	var rt models.RefreshToken
	err := r.db.WithContext(ctx).Where("token = ?", HashRefreshToken(rawToken)).First(&rt).Error
	if err != nil {
		return nil, err
	}
	return &rt, nil
}

func (r *RefreshTokenStore) DeleteByToken(ctx context.Context, rawToken string) error {
	return r.db.WithContext(ctx).Where("token = ?", HashRefreshToken(rawToken)).Delete(&models.RefreshToken{}).Error
}

// DeleteByID deletes a refresh token by ID, scoped to the given userID to
// prevent IDOR (revoking another user's token).
func (r *RefreshTokenStore) DeleteByID(ctx context.Context, id, userID uint) error {
	return r.db.WithContext(ctx).Where("id = ? AND user_id = ?", id, userID).Delete(&models.RefreshToken{}).Error
}

func (r *RefreshTokenStore) DeleteByUserID(ctx context.Context, userID uint) error {
	return r.db.WithContext(ctx).Where("user_id = ?", userID).Delete(&models.RefreshToken{}).Error
}

// DeleteExpired removes all expired refresh tokens. Should be called
// periodically to keep the table from growing unboundedly.
func (r *RefreshTokenStore) DeleteExpired(ctx context.Context) error {
	return r.db.WithContext(ctx).Where("expires_at < ?", time.Now()).Delete(&models.RefreshToken{}).Error
}
