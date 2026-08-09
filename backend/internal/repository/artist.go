package repository

import (
	"context"
	"errors"
	"strings"

	"flux/internal/models"

	"gorm.io/gorm"
)

type ArtistStore struct {
	db *gorm.DB
}

func NewArtistRepository(db *gorm.DB) *ArtistStore {
	return &ArtistStore{db: db}
}

// FindAll returns all artists ordered by name.
func (r *ArtistStore) FindAll(ctx context.Context) ([]models.Artist, error) {
	var artists []models.Artist
	err := r.db.WithContext(ctx).Order("name ASC").Find(&artists).Error
	return artists, err
}

// FindByID returns an artist by ID.
func (r *ArtistStore) FindByID(ctx context.Context, id uint) (*models.Artist, error) {
	var artist models.Artist
	err := r.db.WithContext(ctx).First(&artist, id).Error
	return &artist, err
}

// FindOrCreateByName finds an artist by name or creates a new one.
// Name is trimmed; empty names are rejected.
func (r *ArtistStore) FindOrCreateByName(ctx context.Context, name string) (*models.Artist, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil, errors.New("artist name is empty")
	}

	var artist models.Artist
	err := r.db.WithContext(ctx).Where("name = ?", name).First(&artist).Error
	if err == nil {
		return &artist, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}

	artist = models.Artist{Name: name}
	if err := r.db.WithContext(ctx).Create(&artist).Error; err != nil {
		// Race condition: another goroutine created it first.
		if err2 := r.db.WithContext(ctx).Where("name = ?", name).First(&artist).Error; err2 != nil {
			return nil, err
		}
	}
	return &artist, nil
}
