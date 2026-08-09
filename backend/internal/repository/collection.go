package repository

import (
	"context"

	"flux/internal/models"

	"gorm.io/gorm"
)

type CollectionStore struct {
	db *gorm.DB
}

func NewCollectionRepository(db *gorm.DB) *CollectionStore {
	return &CollectionStore{db: db}
}

func (r *CollectionStore) FindByUser(ctx context.Context, userID uint) ([]models.Collection, error) {
	var cols []models.Collection
	err := r.db.WithContext(ctx).Where("user_id = ?", userID).Find(&cols).Error
	return cols, err
}

func (r *CollectionStore) FindByID(ctx context.Context, id uint) (*models.Collection, error) {
	var col models.Collection
	err := r.db.WithContext(ctx).First(&col, id).Error
	return &col, err
}

func (r *CollectionStore) Create(ctx context.Context, collection *models.Collection) error {
	return r.db.WithContext(ctx).Create(collection).Error
}

func (r *CollectionStore) Update(ctx context.Context, collection *models.Collection) error {
	return r.db.WithContext(ctx).Save(collection).Error
}

func (r *CollectionStore) Delete(ctx context.Context, id uint) error {
	// Delete items and the collection atomically to avoid orphaned items.
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("collection_id = ?", id).Delete(&models.CollectionItem{}).Error; err != nil {
			return err
		}
		return tx.Delete(&models.Collection{}, id).Error
	})
}

type CollectionItemStore struct {
	db *gorm.DB
}

func NewCollectionItemRepository(db *gorm.DB) *CollectionItemStore {
	return &CollectionItemStore{db: db}
}

func (r *CollectionItemStore) FindByCollection(ctx context.Context, collectionID uint) ([]models.CollectionItem, error) {
	var items []models.CollectionItem
	err := r.db.WithContext(ctx).Where("collection_id = ?", collectionID).Find(&items).Error
	return items, err
}

// FindMediaByCollection returns the full media objects of a collection in
// insertion order, preloading Metadata and Artists (no N+1 on the client).
func (r *CollectionItemStore) FindMediaByCollection(ctx context.Context, collectionID uint) ([]models.Media, error) {
	var media []models.Media
	err := r.db.WithContext(ctx).
		Model(&models.Media{}).
		Joins("JOIN collection_items ON collection_items.media_id = media.id").
		Where("collection_items.collection_id = ?", collectionID).
		Order("collection_items.position ASC, collection_items.id ASC").
		Preload("Metadata").
		Preload("Artists", func(db *gorm.DB) *gorm.DB {
			return db.Joins("JOIN media_artists ON media_artists.artist_id = artists.id").Order("media_artists.position ASC")
		}).
		Find(&media).Error
	return media, err
}

func (r *CollectionItemStore) Add(ctx context.Context, item *models.CollectionItem) error {
	// Auto-assign next position inside a transaction: MAX(position)+1 must
	// be computed atomically, otherwise two parallel AddItem calls can
	// produce the same position and violate the unique index.
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if item.Position == 0 {
			var maxPos *int
			if err := tx.
				Model(&models.CollectionItem{}).
				Where("collection_id = ?", item.CollectionID).
				Select("MAX(position)").
				Scan(&maxPos).Error; err != nil {
				return err
			}
			if maxPos != nil {
				item.Position = *maxPos + 1
			}
		}
		return tx.Create(item).Error
	})
}

func (r *CollectionItemStore) Remove(ctx context.Context, collectionID, mediaID uint) error {
	return r.db.WithContext(ctx).
		Where("collection_id = ? AND media_id = ?", collectionID, mediaID).
		Delete(&models.CollectionItem{}).Error
}
