package repository

import (
	"context"

	"flux/internal/models"
)

// UserRepository defines data access methods for User entities.
type UserRepository interface {
	FindByEmail(ctx context.Context, email string) (*models.User, error)
	FindByID(ctx context.Context, id uint) (*models.User, error)
	Create(ctx context.Context, user *models.User) error
	Update(ctx context.Context, user *models.User) error
	Delete(ctx context.Context, id uint) error
}

// MediaRepository defines data access methods for Media entities.
type MediaRepository interface {
	FindAll(ctx context.Context, filters map[string]interface{}, limit, offset int) ([]models.Media, int64, error)
	FindByID(ctx context.Context, id uint) (*models.Media, error)
	FindByPath(ctx context.Context, path string) (*models.Media, error)
	FindByHash(ctx context.Context, hash string) (*models.Media, error)
	Create(ctx context.Context, media *models.Media) error
	Update(ctx context.Context, media *models.Media) error
	Delete(ctx context.Context, id uint) error
}

// LibraryRepository defines data access methods for MediaLibrary entities.
type LibraryRepository interface {
	FindAll(ctx context.Context) ([]models.MediaLibrary, error)
	FindByID(ctx context.Context, id uint) (*models.MediaLibrary, error)
	FindByPath(ctx context.Context, path string) (*models.MediaLibrary, error)
	Create(ctx context.Context, library *models.MediaLibrary) error
	Update(ctx context.Context, library *models.MediaLibrary) error
	Delete(ctx context.Context, id uint) error
}

// ProgressRepository defines data access methods for WatchProgress entities.
type ProgressRepository interface {
	FindByUser(ctx context.Context, userID uint) ([]models.WatchProgress, error)
	FindByUserAndMedia(ctx context.Context, userID, mediaID uint) (*models.WatchProgress, error)
	Upsert(ctx context.Context, progress *models.WatchProgress) error
	Delete(ctx context.Context, userID, mediaID uint) error
}
