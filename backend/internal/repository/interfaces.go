package repository

import (
	"context"
	"time"

	"flux/internal/models"
)

// UserRepository defines data access methods for User entities.
type UserRepository interface {
	FindByEmail(ctx context.Context, email string) (*models.User, error)
	FindByID(ctx context.Context, id uint) (*models.User, error)
	Create(ctx context.Context, user *models.User) error
	Update(ctx context.Context, user *models.User) error
	Delete(ctx context.Context, id uint) error
	Count(ctx context.Context) (int64, error)
}

// MediaRepository defines data access methods for Media entities.
type MediaRepository interface {
	FindAll(ctx context.Context, filters map[string]interface{}, limit, offset int) ([]models.Media, int64, error)
	FindByID(ctx context.Context, id uint) (*models.Media, error)
	FindByPath(ctx context.Context, path string) (*models.Media, error)
	// FindByPathBasic ищет по пути одним SELECT без Preload — для горячих
	// путей, где Metadata/Artists не нужны (сканирование больших библиотек).
	FindByPathBasic(ctx context.Context, path string) (*models.Media, error)
	FindByHash(ctx context.Context, hash string) (*models.Media, error)
	FindByPathPrefix(ctx context.Context, prefix string, limit, offset int) ([]models.Media, int64, error)
	Create(ctx context.Context, media *models.Media) error
	// Update обновляет только непустые поля; ассоциации Artists заменяются
	// целиком, Metadata сохраняется upsert'ом при наличии.
	Update(ctx context.Context, media *models.Media) error
	Delete(ctx context.Context, id uint) error
}

// ProgressRepository defines data access methods for WatchProgress entities.
type ProgressRepository interface {
	FindByUser(ctx context.Context, userID uint, limit, offset int) ([]models.WatchProgress, int64, error)
	FindByUserAndMedia(ctx context.Context, userID, mediaID uint) (*models.WatchProgress, error)
	Upsert(ctx context.Context, progress *models.WatchProgress) error
	Delete(ctx context.Context, userID, mediaID uint) error
}

// ArtistRepository defines data access methods for Artist entities.
type ArtistRepository interface {
	FindAll(ctx context.Context) ([]models.Artist, error)
	FindByID(ctx context.Context, id uint) (*models.Artist, error)
	FindOrCreateByName(ctx context.Context, name string) (*models.Artist, error)
}

// FavoriteRepository defines data access methods for Favorite entities.
type FavoriteRepository interface {
	FindByUser(ctx context.Context, userID uint, mediaType string, limit, offset int) ([]models.Favorite, int64, error)
	FindByUserAndMedia(ctx context.Context, userID, mediaID uint) (*models.Favorite, error)
	FindByUserAndArtist(ctx context.Context, userID, artistID uint) (*models.Favorite, error)
	IsFavorited(ctx context.Context, userID, mediaID uint) (bool, error)
	IsArtistFavorited(ctx context.Context, userID, artistID uint) (bool, error)
	Create(ctx context.Context, favorite *models.Favorite) error
	Delete(ctx context.Context, userID, mediaID uint) error
	DeleteArtist(ctx context.Context, userID, artistID uint) error
}

// CollectionRepository defines data access methods for Collection entities.
type CollectionRepository interface {
	FindByUser(ctx context.Context, userID uint) ([]models.Collection, error)
	FindByID(ctx context.Context, id uint) (*models.Collection, error)
	Create(ctx context.Context, collection *models.Collection) error
	Update(ctx context.Context, collection *models.Collection) error
	Delete(ctx context.Context, id uint) error
}

// CollectionItemRepository defines data access methods for CollectionItem entities.
type CollectionItemRepository interface {
	FindByCollection(ctx context.Context, collectionID uint) ([]models.CollectionItem, error)
	FindByCollectionAndMedia(ctx context.Context, collectionID, mediaID uint) (*models.CollectionItem, error)
	FindMediaByCollection(ctx context.Context, collectionID uint) ([]models.Media, error)
	Add(ctx context.Context, item *models.CollectionItem) error
	// AddItemAtomic добавляет элемент и присваивает позицию MAX(position)+1
	// в одной транзакции. Дубликат (collection_id, media_id) возвращается
	// как ErrDuplicateItem.
	AddItemAtomic(ctx context.Context, collectionID, mediaID uint) (models.CollectionItem, error)
	Remove(ctx context.Context, collectionID, mediaID uint) error
	MaxPosition(ctx context.Context, collectionID uint) (int, error)
}

// LyricsRepository defines data access methods for Lyrics entities.
type LyricsRepository interface {
	FindByMediaID(ctx context.Context, mediaID uint) (*models.Lyrics, error)
	Upsert(ctx context.Context, lyrics *models.Lyrics) error
	Delete(ctx context.Context, mediaID uint) error
}

// RefreshTokenRepository defines data access methods for RefreshToken entities.
type RefreshTokenRepository interface {
	Create(ctx context.Context, userID uint, rawToken string, expiresAt time.Time) error
	RotateToken(ctx context.Context, oldRawToken string, userID uint, newRawToken string, expiresAt time.Time) (*models.RefreshToken, error)
	FindByToken(ctx context.Context, rawToken string) (*models.RefreshToken, error)
	DeleteByToken(ctx context.Context, rawToken string) error
	DeleteByID(ctx context.Context, id, userID uint) error
	DeleteByUserID(ctx context.Context, userID uint) error
	DeleteExpired(ctx context.Context) error
}
