package repository

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"flux/internal/models"

	"gorm.io/gorm"
)

// ErrDuplicateItem — элемент коллекции уже существует
// (уникальный индекс (collection_id, media_id)).
var ErrDuplicateItem = errors.New("collection item already exists")

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

// Update обновляет только переданные непустые поля (name, type).
func (r *CollectionStore) Update(ctx context.Context, collection *models.Collection) error {
	if collection.ID == 0 {
		return errors.New("repository: collection ID required for Update")
	}
	updates := make(map[string]interface{})
	if collection.Name != "" {
		updates["name"] = collection.Name
	}
	if collection.Type != "" {
		updates["type"] = collection.Type
	}
	if len(updates) == 0 {
		return nil
	}
	return r.db.WithContext(ctx).Model(collection).Updates(updates).Error
}

func (r *CollectionStore) Delete(ctx context.Context, id uint) error {
	// Delete items and the collection atomically to avoid orphaned items.
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := cascadeDelete(tx, "collection_id", id, &models.CollectionItem{}); err != nil {
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
		Find(&media).Error
	if err != nil {
		return nil, err
	}

	if loadErr := LoadArtistsForMedia(r.db.WithContext(ctx), media); loadErr != nil {
		return nil, loadErr
	}

	return media, nil
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

// AddItemAtomic добавляет элемент в коллекцию и присваивает следующую
// позицию (MAX(position)+1) атомарно — в одной транзакции с INSERT
// (без этого параллельные AddItem получают одинаковую позицию и падают
// на уникальном индексе idx_collection_position). При коллизии позиции
// (конкурентное добавление) транзакция повторяется с актуальным MAX.
// Дубликат (collection_id, media_id) возвращается как ErrDuplicateItem.
func (r *CollectionItemStore) AddItemAtomic(ctx context.Context, collectionID, mediaID uint) (models.CollectionItem, error) {
	for attempt := 0; ; attempt++ {
		var item models.CollectionItem
		err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
			var maxPos *int
			if err := tx.
				Model(&models.CollectionItem{}).
				Where("collection_id = ?", collectionID).
				Select("MAX(position)").
				Scan(&maxPos).Error; err != nil {
				return err
			}
			item = models.CollectionItem{
				CollectionID: collectionID,
				MediaID:      mediaID,
				AddedAt:      time.Now().UTC(),
			}
			// 1-базированная нумерация — контракт хендлера (MaxPosition+1).
			item.Position = 1
			if maxPos != nil {
				item.Position = *maxPos + 1
			}
			return tx.Create(&item).Error
		})
		if err == nil {
			return item, nil
		}
		if !isUniqueViolation(err) {
			return models.CollectionItem{}, err
		}
		// UNIQUE на позиции — конкурентное добавление: повторяем с новым MAX.
		if strings.Contains(err.Error(), "position") && attempt < 4 {
			continue
		}
		return models.CollectionItem{}, fmt.Errorf("%w: %v", ErrDuplicateItem, err)
	}
}

func (r *CollectionItemStore) Remove(ctx context.Context, collectionID, mediaID uint) error {
	return r.db.WithContext(ctx).
		Where("collection_id = ? AND media_id = ?", collectionID, mediaID).
		Delete(&models.CollectionItem{}).Error
}

func (r *CollectionItemStore) FindByCollectionAndMedia(ctx context.Context, collectionID, mediaID uint) (*models.CollectionItem, error) {
	var item models.CollectionItem
	err := r.db.WithContext(ctx).Where("collection_id = ? AND media_id = ?", collectionID, mediaID).First(&item).Error
	return &item, err
}

func (r *CollectionItemStore) MaxPosition(ctx context.Context, collectionID uint) (int, error) {
	var maxPos *int
	err := r.db.WithContext(ctx).
		Model(&models.CollectionItem{}).
		Where("collection_id = ?", collectionID).
		Select("MAX(position)").
		Scan(&maxPos).Error
	if err != nil {
		return 0, err
	}
	if maxPos == nil {
		return 0, nil
	}
	return *maxPos, nil
}
