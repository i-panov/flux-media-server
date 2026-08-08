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

func (r *FavoriteStore) FindByUser(ctx context.Context, userID uint, limit, offset int) ([]models.Favorite, int64, error) {
	var favs []models.Favorite
	var total int64
	query := r.db.WithContext(ctx).Model(&models.Favorite{}).Where("user_id = ?", userID)
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	if limit > 0 {
		query = query.Limit(limit)
	}
	if offset > 0 {
		query = query.Offset(offset)
	}
	err := query.Find(&favs).Error
	return favs, total, err
}

func (r *FavoriteStore) FindByUserAndMedia(ctx context.Context, userID, mediaID uint) (*models.Favorite, error) {
	var fav models.Favorite
	err := r.db.WithContext(ctx).
		Where("user_id = ? AND media_id = ?", userID, mediaID).
		First(&fav).Error
	return &fav, err
}

func (r *FavoriteStore) FindByUserAndArtist(ctx context.Context, userID uint, artistName string) (*models.Favorite, error) {
	var fav models.Favorite
	err := r.db.WithContext(ctx).
		Where("user_id = ? AND artist_name = ?", userID, artistName).
		First(&fav).Error
	return &fav, err
}

func (r *FavoriteStore) IsFavorited(ctx context.Context, userID, mediaID uint) (bool, error) {
	var count int64
	err := r.db.WithContext(ctx).Model(&models.Favorite{}).
		Where("user_id = ? AND media_id = ?", userID, mediaID).
		Count(&count).Error
	return count > 0, err
}

func (r *FavoriteStore) IsArtistFavorited(ctx context.Context, userID uint, artistName string) (bool, error) {
	var count int64
	err := r.db.WithContext(ctx).Model(&models.Favorite{}).
		Where("user_id = ? AND artist_name = ?", userID, artistName).
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
		return errors.New("favorite not found")
	}
	return result.Error
}

func (r *FavoriteStore) DeleteArtist(ctx context.Context, userID uint, artistName string) error {
	result := r.db.WithContext(ctx).
		Where("user_id = ? AND artist_name = ?", userID, artistName).
		Delete(&models.Favorite{})
	if result.RowsAffected == 0 {
		return errors.New("artist favorite not found")
	}
	return result.Error
}
