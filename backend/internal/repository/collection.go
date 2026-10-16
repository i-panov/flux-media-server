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

// ErrNotMember — элемента нет в исходной коллекции (переносить нечего).
var ErrNotMember = errors.New("media is not a member of the source collection")

// isPositionViolation отличает коллизию позиций (конкурентное
// добавление — можно повторить с новым MAX) от дубликата
// (collection_id, media_id). Текст SQLite стабилен годами:
// "UNIQUE constraint failed: collection_items.collection_id,
// collection_items.position" — матчим точную колонку, а не слово
// "position" (имени индекса в тексте нет, только колонки).
func isPositionViolation(err error) bool {
	return strings.Contains(err.Error(), "collection_items.position")
}

// ErrSameCollection — источник и цель совпадают (перенос в себя).
var ErrSameCollection = errors.New("source and target collections are the same")

// maxPositionRetries — попыток пересчёта MAX(position)+1 при коллизии
// позиций от конкурентных добавлений (единая для AddItemAtomic
// и MoveItemAtomic).
const maxPositionRetries = 4

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

// FindChildren возвращает непосредственных детей коллекции.
func (r *CollectionStore) FindChildren(ctx context.Context, id uint) ([]models.Collection, error) {
	var cols []models.Collection
	err := r.db.WithContext(ctx).Where("parent_id = ?", id).Find(&cols).Error
	return cols, err
}

// TrashedCollections — плоский список корзины пользователя (вложенности
// внутри корзины нет, как в Windows: всё одним списком).
func (r *CollectionStore) TrashedCollections(ctx context.Context, userID uint, limit, offset int) ([]models.Collection, error) {
	q := r.db.WithContext(ctx).Unscoped().
		Where("user_id = ? AND deleted_at IS NOT NULL", userID).
		Order("deleted_at DESC")
	if limit > 0 {
		q = q.Limit(limit)
	}
	if offset > 0 {
		q = q.Offset(offset)
	}
	var cols []models.Collection
	err := q.Find(&cols).Error
	return cols, err
}

// FindTrashedCollection грузит trashed-строку своего пользователя.
// Живая, чужая или отсутствующая — ErrNotInTrash (везде 404).
func (r *CollectionStore) FindTrashedCollection(ctx context.Context, userID, id uint) (*models.Collection, error) {
	var col models.Collection
	if err := r.db.WithContext(ctx).Unscoped().First(&col, id).Error; err != nil {
		return nil, err
	}
	if col.UserID != userID || !col.DeletedAt.Valid {
		return nil, ErrNotInTrash
	}
	return &col, nil
}

// ErrNotInTrash — строка не в корзине (живая или чужая): везде 404,
// чтобы не раскрывать чужие данные.
var ErrNotInTrash = errors.New("not found in trash")

// ErrCycle — перенос коллекции под саму себя или своего потомка.
var ErrCycle = errors.New("collection move would create a cycle")

// ErrCrossUser — родитель из чужого неймспейса.
var ErrCrossUser = errors.New("parent collection belongs to another user")

// ErrCrossType — родитель другого типа (сезоны сериала — тот же тип).
var ErrCrossType = errors.New("parent collection has different type")

// subtreeIDs возвращает id всей ветки под ancestorID (без него самого)
// одним рекурсивным запросом — без лимита глубины. UNION (не ALL):
// дедупликация завершает запрос даже при цикле в битых данных.
// includeTrashed — для операций корзины; живые операции видят только
// неудалённые (сырой SQL GORM-фильтр soft delete не применяет).
func subtreeIDs(db *gorm.DB, ancestorID uint, includeTrashed bool) ([]uint, error) {
	var ids []uint
	var err error
	if includeTrashed {
		err = db.Raw(`
			WITH RECURSIVE subtree(id) AS (
				SELECT id FROM collections WHERE parent_id = ?
				UNION
				SELECT c.id FROM collections c JOIN subtree s ON c.parent_id = s.id
			) SELECT id FROM subtree`, ancestorID).Scan(&ids).Error
	} else {
		err = db.Raw(`
			WITH RECURSIVE subtree(id) AS (
				SELECT id FROM collections WHERE parent_id = ? AND deleted_at IS NULL
				UNION
				SELECT c.id FROM collections c JOIN subtree s
					ON c.parent_id = s.id WHERE c.deleted_at IS NULL
			) SELECT id FROM subtree`, ancestorID).Scan(&ids).Error
	}
	return ids, err
}

// IsDescendant проверяет, лежит ли descendantID строго в поддереве
// ancestorID. Глубина любая: один CTE вместо подъёма с лимитом
// (лимит молча разрешал цикл на цепочках длиннее него).
func (r *CollectionStore) IsDescendant(ctx context.Context, ancestorID, descendantID uint) (bool, error) {
	return isDescendant(r.db.WithContext(ctx), ancestorID, descendantID)
}

// isDescendant — та же проверка на произвольном *gorm.DB (в т.ч. внутри
// транзакции): единый код вместо дубля IsDescendant/isDescendantTx.
func isDescendant(db *gorm.DB, ancestorID, descendantID uint) (bool, error) {
	ids, err := subtreeIDs(db, ancestorID, false)
	if err != nil {
		return false, err
	}
	for _, id := range ids {
		if id == descendantID {
			return true, nil
		}
	}
	return false, nil
}

// SetParent переносит коллекцию под нового родителя (nil = в корень).
// Проверки: сама на себя — нет, потомок — нет (цикл), чужой юзер — нет,
// другой тип — нет. Всё в одной транзакции с чтением свежих строк.
func (r *CollectionStore) SetParent(ctx context.Context, id uint, parentID *uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var col models.Collection
		if err := tx.First(&col, id).Error; err != nil {
			return err
		}
		if parentID == nil {
			return tx.Model(&col).Update("parent_id", nil).Error
		}
		return applyParentTx(tx, &col, *parentID)
	})
}

// ErrTypeChangeBlocked — смена типа при связанных записях.
// Тип родителя и детей обязан совпадать (см. ErrCrossType): смена типа
// корня с детьми навсегда ломает будущие переносы, поэтому запрещена,
// пока есть дети или элементы.
var ErrTypeChangeBlocked = errors.New("cannot change type while collection has children or items")

// CollectionPatch — атомарное обновление коллекции: переименование,
// смена типа и перенос применяются в одной транзакции. ParentID == nil
// без MoveToRoot — родителя не трогаем (иначе каждое переименование
// сбрасывало бы в корень).
type CollectionPatch struct {
	Name       *string
	Type       *models.MediaType
	ParentID   *uint
	MoveToRoot bool
}

// Patch применяет патч целиком в одной транзакции: переезд и
// переименование больше не разъезжаются на два коммита.
func (r *CollectionStore) Patch(ctx context.Context, id uint, p CollectionPatch) (*models.Collection, error) {
	var result *models.Collection
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var col models.Collection
		if err := tx.First(&col, id).Error; err != nil {
			return err
		}
		if p.Type != nil && *p.Type != col.Type {
			// Тип обязан совпадать у родителя и детей (ErrCrossType):
			// блокируем при своих детях/элементах И при наличии
			// родителя (иначе ломаем инвариант сверху).
			blocked, err := hasRelationsTx(tx, id)
			if err != nil {
				return err
			}
			if blocked || col.ParentID != nil {
				return ErrTypeChangeBlocked
			}
			col.Type = *p.Type
		}
		if p.Name != nil {
			col.Name = *p.Name
		}
		if err := tx.Model(&col).Select("name", "type").Updates(&col).Error; err != nil {
			return err
		}
		if p.MoveToRoot {
			if err := tx.Model(&col).Update("parent_id", nil).Error; err != nil {
				return err
			}
			col.ParentID = nil
		} else if p.ParentID != nil {
			if err := applyParentTx(tx, &col, *p.ParentID); err != nil {
				return err
			}
			col.ParentID = p.ParentID
		}
		result = &col
		return nil
	})
	if err != nil {
		return nil, err
	}
	return result, nil
}

// CreateWithParent создаёт коллекцию сразу под родителем в одной
// транзакции: при отказе проверок (чужой юзер/тип/нет родителя)
// сироты-корня в БД не остаётся. Цикл невозможен — у новой
// коллекции нет детей, поэтому только проверки юзера и типа.
func (r *CollectionStore) CreateWithParent(ctx context.Context, col *models.Collection, parentID uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(col).Error; err != nil {
			return err
		}
		return applyParentTx(tx, col, parentID)
	})
}

// hasRelationsTx проверяет связи коллекции: дети или элементы.
func hasRelationsTx(tx *gorm.DB, id uint) (bool, error) {
	var childCount, itemCount int64
	if err := tx.Model(&models.Collection{}).Where("parent_id = ?", id).Count(&childCount).Error; err != nil {
		return false, err
	}
	if childCount > 0 {
		return true, nil
	}
	if err := tx.Model(&models.CollectionItem{}).Where("collection_id = ?", id).Count(&itemCount).Error; err != nil {
		return false, err
	}
	return itemCount > 0, nil
}

// applyParentTx привязывает col к parentID внутри транзакции:
// самоперенос и потомок — ErrCycle, чужой юзер — ErrCrossUser,
// другой тип — ErrCrossType.
func applyParentTx(tx *gorm.DB, col *models.Collection, parentID uint) error {
	if parentID == col.ID {
		return ErrCycle
	}
	var parent models.Collection
	if err := tx.First(&parent, parentID).Error; err != nil {
		return err
	}
	if parent.UserID != col.UserID {
		return ErrCrossUser
	}
	if parent.Type != col.Type {
		return ErrCrossType
	}
	desc, err := isDescendant(tx, col.ID, parentID)
	if err != nil {
		return err
	}
	if desc {
		return ErrCycle
	}
	return tx.Model(col).Update("parent_id", parentID).Error
}

func (r *CollectionStore) Delete(ctx context.Context, id uint) error {
	// Корзина: помечаем всё поддерево, связи и элементы не трогаем —
	// восстановление мгновенное. Владение проверяет вызывающий хендлер
	// (getOwnedCollection до Delete): репозиторий user_id не скоупит
	// осознанно — тот же подход, что у Remove/FindByCollection
	// (решение, а не упущение).
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		ids, err := subtreeIDs(tx, id, false)
		if err != nil {
			return err
		}
		ids = append(ids, id)
		return tx.Model(&models.Collection{}).
			Where("id IN ?", ids).
			Update("deleted_at", time.Now().UTC()).Error
	})
}

// RestoreCollection возвращает коллекцию из корзины вместе с
// поддеревом, удалённым вместе с ней. Родитель недоступен (тоже
// в корзине или снесён) — коллекция встаёт в корень, а не в никуда.
func (r *CollectionStore) RestoreCollection(ctx context.Context, id uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var col models.Collection
		if err := tx.Unscoped().First(&col, id).Error; err != nil {
			return err
		}
		ids, err := subtreeIDs(tx.Unscoped(), id, true)
		if err != nil {
			return err
		}
		ids = append(ids, id)
		if err := tx.Unscoped().Model(&models.Collection{}).
			Where("id IN ? AND deleted_at IS NOT NULL", ids).
			Update("deleted_at", nil).Error; err != nil {
			return err
		}
		if col.ParentID != nil {
			var parent models.Collection
			if err := tx.First(&parent, *col.ParentID).Error; err != nil {
				if !errors.Is(err, gorm.ErrRecordNotFound) {
					return err
				}
				// Родителя нет среди живых — в корень.
				return tx.Unscoped().Model(&models.Collection{}).
					Where("id = ?", id).
					Update("parent_id", nil).Error
			}
			// Сохранившийся родитель обязан совпадать по владельцу
			// и типу (инвариант SetParent): битые/легаси-данные иначе
			// воскресят невозможную конфигурацию — тоже в корень.
			if parent.UserID != col.UserID || parent.Type != col.Type {
				return tx.Unscoped().Model(&models.Collection{}).
					Where("id = ?", id).
					Update("parent_id", nil).Error
			}
		}
		return nil
	})
}

// PurgeCollection сносит поддерево навсегда: элементы, затем строки.
// Файлов у коллекций нет — стирать с диска нечего.
func (r *CollectionStore) PurgeCollection(ctx context.Context, id uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		ids, err := subtreeIDs(tx.Unscoped(), id, true)
		if err != nil {
			return err
		}
		ids = append(ids, id)
		if err := tx.Unscoped().Where("collection_id IN ?", ids).Delete(&models.CollectionItem{}).Error; err != nil {
			return err
		}
		return tx.Unscoped().Where("id IN ?", ids).Delete(&models.Collection{}).Error
	})
}

// SubtreeStats считает живые подколлекции и элементы поддерева
// рекурсивно — для confirm-диалога («2 подколлекции и 24 файла»).
func (r *CollectionStore) SubtreeStats(ctx context.Context, id uint) (collections int64, items int64, err error) {
	db := r.db.WithContext(ctx)
	ids, err := subtreeIDs(db, id, false)
	if err != nil {
		return 0, 0, err
	}
	// Рекурсивно: все уровни, а не только прямые дети. Элементы
	// самой коллекции тоже считаются — иначе confirm занижает,
	// а purge сносит больше показанного.
	collections = int64(len(ids))
	withSelf := make([]uint, 0, len(ids)+1)
	withSelf = append(withSelf, ids...)
	withSelf = append(withSelf, id)
	if err := db.Model(&models.CollectionItem{}).
		Where("collection_id IN ?", withSelf).
		Count(&items).Error; err != nil {
		return 0, 0, err
	}
	return collections, items, nil
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
		if isPositionViolation(err) && attempt < maxPositionRetries {
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

// MoveItemAtomic переносит элемент между коллекциями в одной транзакции.
// Порядок важен: сначала INSERT в target, затем DELETE из source —
// дубликат в target (ErrDuplicateItem) не приводит к потере элемента:
// исходная запись остаётся на месте.
// Членство в source проверяется SELECT-ом: перенос несуществующего
// элемента — ErrNotMember (404), а не молчаливое создание (иначе это
// Add, а не Move). source == target — ErrSameCollection (400).
func (r *CollectionItemStore) MoveItemAtomic(ctx context.Context, sourceID, targetID, mediaID uint) (models.CollectionItem, error) {
	if sourceID == targetID {
		return models.CollectionItem{}, ErrSameCollection
	}
	for attempt := 0; ; attempt++ {
		var item models.CollectionItem
		err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
			var existing models.CollectionItem
			if err := tx.
				Where("collection_id = ? AND media_id = ?", sourceID, mediaID).
				First(&existing).Error; err != nil {
				if errors.Is(err, gorm.ErrRecordNotFound) {
					return ErrNotMember
				}
				return err
			}
			var maxPos *int
			if err := tx.
				Model(&models.CollectionItem{}).
				Where("collection_id = ?", targetID).
				Select("MAX(position)").
				Scan(&maxPos).Error; err != nil {
				return err
			}
			item = models.CollectionItem{
				CollectionID: targetID,
				MediaID:      mediaID,
				AddedAt:      time.Now().UTC(),
				Position:     1,
			}
			if maxPos != nil {
				item.Position = *maxPos + 1
			}
			if err := tx.Create(&item).Error; err != nil {
				return err
			}
			return tx.
				Where("collection_id = ? AND media_id = ?", sourceID, mediaID).
				Delete(&models.CollectionItem{}).Error
		})
		if err == nil {
			return item, nil
		}
		if !isUniqueViolation(err) {
			return models.CollectionItem{}, err
		}
		// UNIQUE на позиции в target — конкурентное добавление:
		// повторяем с новым MAX, как в AddItemAtomic.
		if isPositionViolation(err) && attempt < maxPositionRetries {
			continue
		}
		return models.CollectionItem{}, fmt.Errorf("%w: %v", ErrDuplicateItem, err)
	}
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
