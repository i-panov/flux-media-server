package repository

import (
	"context"
	"errors"

	"flux/internal/models"

	"gorm.io/gorm"
)

type FavoriteStore struct {
	db *gorm.DB
}

func NewFavoriteRepository(db *gorm.DB) *FavoriteStore {
	return &FavoriteStore{db: db}
}

func (r *FavoriteStore) FindByUser(ctx context.Context, userID uint, mediaType string, limit, offset int) ([]models.Favorite, int64, error) {
	var favs []models.Favorite
	var total int64
	query := r.db.WithContext(ctx).Model(&models.Favorite{}).Where("user_id = ?", userID)
	if mediaType != "" {
		// Filter media favorites by the media's type (video/audio).
		query = query.Joins("JOIN media ON media.id = favorites.media_id").
			Where("media.type = ? AND favorites.media_id IS NOT NULL", mediaType)
	}
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	if limit > 0 {
		query = query.Limit(limit)
	}
	if offset > 0 {
		query = query.Offset(offset)
	}
	// Stable pagination order.
	query = query.Order("favorites.id ASC")
	// Preload the media object so the client does not need an N+1 request
	// per favorite row.
	err := query.Preload("Media").Find(&favs).Error
	return favs, total, err
}

func (r *FavoriteStore) FindByUserAndMedia(ctx context.Context, userID, mediaID uint) (*models.Favorite, error) {
	var fav models.Favorite
	err := r.db.WithContext(ctx).
		Where("user_id = ? AND media_id = ?", userID, mediaID).
		First(&fav).Error
	return &fav, err
}

func (r *FavoriteStore) FindByUserAndArtist(ctx context.Context, userID, artistID uint) (*models.Favorite, error) {
	var fav models.Favorite
	err := r.db.WithContext(ctx).
		Where("user_id = ? AND artist_id = ?", userID, artistID).
		First(&fav).Error
	return &fav, err
}

// IsFavorited сообщает, есть ли у пользователя медиа-фavorite на запись.
// Общая логика с FindByUserAndMedia — тот же WHERE (user_id, media_id).
func (r *FavoriteStore) IsFavorited(ctx context.Context, userID, mediaID uint) (bool, error) {
	_, err := r.FindByUserAndMedia(ctx, userID, mediaID)
	if err == nil {
		return true, nil
	}
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return false, nil
	}
	return false, err
}

func (r *FavoriteStore) IsArtistFavorited(ctx context.Context, userID, artistID uint) (bool, error) {
	var count int64
	err := r.db.WithContext(ctx).Model(&models.Favorite{}).
		Where("user_id = ? AND artist_id = ?", userID, artistID).
		Count(&count).Error
	return count > 0, err
}

func (r *FavoriteStore) Create(ctx context.Context, favorite *models.Favorite) error {
	return r.db.WithContext(ctx).Create(favorite).Error
}

func (r *FavoriteStore) Delete(ctx context.Context, userID, mediaID uint) error {
	result := r.db.WithContext(ctx).
		Where("user_id = ? AND media_id = ?", userID, mediaID).
		Delete(&models.Favorite{})
	if result.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return result.Error
}

func (r *FavoriteStore) DeleteArtist(ctx context.Context, userID, artistID uint) error {
	result := r.db.WithContext(ctx).
		Where("user_id = ? AND artist_id = ?", userID, artistID).
		Delete(&models.Favorite{})
	if result.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return result.Error
}
