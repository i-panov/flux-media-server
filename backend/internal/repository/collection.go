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
	// Delete items first, then collection
	r.db.WithContext(ctx).Where("collection_id = ?", id).Delete(&models.CollectionItem{})
	return r.db.WithContext(ctx).Delete(&models.Collection{}, id).Error
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

func (r *CollectionItemStore) Add(ctx context.Context, item *models.CollectionItem) error {
	return r.db.WithContext(ctx).Create(item).Error
}

func (r *CollectionItemStore) Remove(ctx context.Context, collectionID, mediaID uint) error {
	return r.db.WithContext(ctx).
		Where("collection_id = ? AND media_id = ?", collectionID, mediaID).
		Delete(&models.CollectionItem{}).Error
}
