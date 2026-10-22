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

// MediaFilters — типизированный набор фильтров списка медиа. Нулевые
// значения полей (пустой Type, Year=0, пустой Q) означают «без фильтра».
type MediaFilters struct {
	Type models.MediaType
	Year int
	Q    string
}

// MediaRepository defines data access methods for Media entities.
type MediaRepository interface {
	FindAll(ctx context.Context, filters MediaFilters, limit, offset int) ([]models.Media, int64, error)
	// FindByIDs возвращает медиа по списку ID с Metadata и Artists.
	FindByIDs(ctx context.Context, ids []uint) ([]models.Media, error)
	FindByID(ctx context.Context, id uint) (*models.Media, error)
	FindByPath(ctx context.Context, path string) (*models.Media, error)
	// FindByPathBasic ищет по пути одним SELECT без Preload — для горячих
	// путей, где Metadata/Artists не нужны (сканирование больших библиотек).
	FindByPathBasic(ctx context.Context, path string) (*models.Media, error)
	FindByHash(ctx context.Context, hash string) (*models.Media, error)
	// FindBySourceMediaID возвращает аудиотрек, извлечённый из видео
	// mediaID (связка POST /extract). Отсутствие — gorm.ErrRecordNotFound
	// (как у FindByHash), а не nil-пара: вызывающий различает через errors.Is.
	FindBySourceMediaID(ctx context.Context, mediaID uint) (*models.Media, error)
	FindByPathPrefix(ctx context.Context, prefix string, limit, offset int) ([]models.Media, int64, error)
	// FindVideosMissingDimensions — живые видео без записанных размеров
	// кадра. Разовая заливка размеров при старте сервера: у записей,
	// созданных до появления колонок width/height, файлы не менялись,
	// поэтому обычный скан их больше не трогает.
	FindVideosMissingDimensions(ctx context.Context, limit int) ([]models.Media, error)
	// UpdateDimensions записывает ТОЛЬКО размеры кадра, ничего не
	// трогая в остальных полях и связях.
	//
	// Отдельный метод, а не Update: Update работает с ассоциациями
	// (Artists), и вызов на записи, прочитанной без Preload, стирал
	// связи видео с артистами. Для технических полей, которые ставит
	// фоновая задача, рисковать ассоциациями незачем.
	UpdateDimensions(ctx context.Context, id uint, width, height int) error
	Create(ctx context.Context, media *models.Media) error
	// Update обновляет только непустые поля; ассоциации Artists заменяются
	// целиком, Metadata сохраняется upsert'ом при наличии.
	Update(ctx context.Context, media *models.Media) error
	// UpdateWithSourceURL — то же, что Update, плюс безусловная запись
	// ссылки на источник в той же транзакции (включая пустую строку =
	// очистка). Отдельный метод, а не флаг в Update: общий Update
	// пропускает пустые значения, чтобы сканер и очередь не затирали
	// ручные правки. nil = ссылку не трогать.
	UpdateWithSourceURL(ctx context.Context, media *models.Media, sourceURL *string) error
	// Delete — корзина: только флаг, связи/файлы целы, восстановление
	// мгновенное. Навсегда — PurgeMedia.
	Delete(ctx context.Context, id uint) error
	// RestoreMedia возвращает из корзины; путь занят живым — ErrPathConflict.
	RestoreMedia(ctx context.Context, id uint) error
	// PurgeMedia сносит навсегда: связи каскадом, строка — hard.
	PurgeMedia(ctx context.Context, id uint) error
	// FindTrashedMedia грузит trashed-строку (живая — ErrNotInTrash).
	FindTrashedMedia(ctx context.Context, id uint) (*models.Media, error)
	// TrashedMedia — плоский список корзины.
	TrashedMedia(ctx context.Context, limit, offset int) ([]models.Media, error)
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
	// Update переименовывает артиста. ErrArtistNameTaken — имя занято,
	// gorm.ErrRecordNotFound — артист не найден.
	Update(ctx context.Context, id uint, name string) (*models.Artist, error)
	// Touch обновляет updated_at (cache-buster обложки).
	Touch(ctx context.Context, id uint) error
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
	// FindChildren возвращает непосредственных детей коллекции.
	FindChildren(ctx context.Context, id uint) ([]models.Collection, error)
	Create(ctx context.Context, collection *models.Collection) error
	// CreateWithParent создаёт коллекцию сразу под родителем в одной
	// транзакции (без сироты при отказе проверок).
	CreateWithParent(ctx context.Context, collection *models.Collection, parentID uint) error
	// Patch применяет переименование, смену типа и перенос в одной
	// транзакции и возвращает свежую строку для ответа. Единственная
	// точка обновления (legacy-Update удалён, обхода запретов нет).
	Patch(ctx context.Context, id uint, p CollectionPatch) (*models.Collection, error)
	// Delete — корзина: помечает поддерево, связи и элементы на месте.
	Delete(ctx context.Context, id uint) error
	// RestoreCollection возвращает поддерево из корзины; при недоступном
	// родителе коллекция встаёт в корень.
	RestoreCollection(ctx context.Context, id uint) error
	// PurgeCollection сносит поддерево навсегда (элементы + строки).
	PurgeCollection(ctx context.Context, id uint) error
	// TrashedCollections — плоский список корзины пользователя.
	TrashedCollections(ctx context.Context, userID uint, limit, offset int) ([]models.Collection, error)
	// FindTrashedCollection — trashed-строка своего пользователя.
	FindTrashedCollection(ctx context.Context, userID, id uint) (*models.Collection, error)
	// SubtreeStats — живые счётчики поддерева для confirm-диалога.
	SubtreeStats(ctx context.Context, id uint) (collections int64, items int64, err error)
	// SetParent переносит коллекцию под нового родителя (nil = в корень)
	// с проверкой циклов и владения внутри одной транзакции.
	SetParent(ctx context.Context, id uint, parentID *uint) error
	// IsDescendant проверяет, лежит ли descendantID в поддереве ancestorID
	// (защита от циклов при переносе).
	IsDescendant(ctx context.Context, ancestorID, descendantID uint) (bool, error)
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
	// MoveItemAtomic переносит элемент между коллекциями в одной
	// транзакции: удаляет из source и добавляет в target через ту же
	// логику позиций, что AddItemAtomic. Дубликат в target —
	// ErrDuplicateItem, сам элемент из source при этом уже удалён? Нет:
	// порядок обратный — сначала INSERT в target, затем DELETE из source,
	// чтобы дубль не приводил к потере элемента.
	MoveItemAtomic(ctx context.Context, sourceID, targetID, mediaID uint) (models.CollectionItem, error)
	// Remove удаляет элемент из коллекции и возвращает число затронутых
	// строк: 0 — элемента в коллекции не было.
	Remove(ctx context.Context, collectionID, mediaID uint) (int64, error)
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
