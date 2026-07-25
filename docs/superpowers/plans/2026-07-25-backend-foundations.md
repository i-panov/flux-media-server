# Backend Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add backend models, repositories, handlers, and API endpoints for favorites, collections, and lyrics — the foundation for the UI redesign.

**Architecture:** Follows existing patterns: GORM models in `internal/models/`, repository interfaces in `internal/repository/interfaces.go` with implementations in separate files, handlers in `internal/handlers/` using `response.Error()` helper, routes wired in `internal/app/app.go`. SQLite with GORM AutoMigrate.

**Tech Stack:** Go 1.23, Fiber v2, GORM, SQLite, testify/assert

---

## File Structure

### New files

| File | Responsibility |
|------|----------------|
| `backend/internal/models/favorite.go` | Favorite GORM model |
| `backend/internal/models/collection.go` | Collection + CollectionItem GORM models |
| `backend/internal/models/lyrics.go` | Lyrics GORM model |
| `backend/internal/repository/favorite.go` | FavoriteStore repository implementation |
| `backend/internal/repository/collection.go` | CollectionStore + CollectionItemStore implementations |
| `backend/internal/repository/lyrics.go` | LyricsStore repository implementation |
| `backend/internal/handlers/favorite.go` | Favorite HTTP handlers |
| `backend/internal/handlers/collection.go` | Collection HTTP handlers |
| `backend/internal/handlers/lyrics.go` | Lyrics HTTP handlers |
| `backend/internal/repository/favorite_test.go` | Favorite repository tests |
| `backend/internal/repository/collection_test.go` | Collection repository tests |
| `backend/internal/repository/lyrics_test.go` | Lyrics repository tests |
| `backend/internal/handlers/favorite_test.go` | Favorite handler tests |
| `backend/internal/handlers/collection_test.go` | Collection handler tests |
| `backend/internal/handlers/lyrics_test.go` | Lyrics handler tests |

### Modified files

| File | Changes |
|------|---------|
| `backend/internal/repository/interfaces.go` | Add FavoriteRepository, CollectionRepository, CollectionItemRepository, LyricsRepository interfaces |
| `backend/internal/repository/db.go` | Add new models to AutoMigrate |
| `backend/internal/repository/db_test.go` | Add assertions for new tables |
| `backend/internal/app/app.go` | Wire new repositories, handlers, and routes |

---

## Task 1: Favorite Model

**Files:**
- Create: `backend/internal/models/favorite.go`
- Modify: `backend/internal/models/models_test.go`

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/models/models_test.go`:

```go
func TestFavoriteFields(t *testing.T) {
	f := Favorite{
		ID:         1,
		UserID:     1,
		Type:       "video",
		MediaID:    func() *uint { v := uint(5); return &v }(),
		ArtistName: "",
		CreatedAt:  time.Now(),
	}
	if f.ID != 1 || f.Type != "video" || *f.MediaID != 5 {
		t.Errorf("Favorite fields not properly set: %+v", f)
	}

	f2 := Favorite{
		ID:         2,
		UserID:     1,
		Type:       "artist",
		MediaID:    nil,
		ArtistName: "Pink Floyd",
		CreatedAt:  time.Now(),
	}
	if f2.ArtistName != "Pink Floyd" || f2.MediaID != nil {
		t.Errorf("Artist favorite fields not properly set: %+v", f2)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/models/ -run TestFavoriteFields -v`
Expected: FAIL — `undefined: Favorite`

- [ ] **Step 3: Write minimal implementation**

Create `backend/internal/models/favorite.go`:

```go
package models

import "time"

// Favorite represents a user's liked media item or artist.
// For video/audio favorites, MediaID is set and ArtistName is empty.
// For artist favorites, ArtistName is set and MediaID is nil.
type Favorite struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	UserID     uint      `gorm:"index;idx_user_type,unique;idx_user_media_type,unique" json:"user_id"`
	Type       string    `gorm:"index;idx_user_type,unique" json:"type"` // video, audio, artist
	MediaID    *uint     `gorm:"index;idx_user_media_type,unique" json:"media_id,omitempty"`
	ArtistName string    `gorm:"index" json:"artist_name,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
}
```

The composite unique index `idx_user_type` on (UserID, Type) is NOT what we want — we need uniqueness per (UserID, MediaID) for media favorites and per (UserID, ArtistName) for artist favorites. Let me fix the model:

```go
package models

import "time"

// Favorite represents a user's liked media item or artist.
// For video/audio favorites, MediaID is set and ArtistName is empty.
// For artist favorites, ArtistName is set and MediaID is nil.
type Favorite struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	UserID     uint      `gorm:"uniqueIndex:idx_user_media" json:"user_id"`
	Type       string    `gorm:"index" json:"type"` // video, audio, artist
	MediaID    *uint     `gorm:"uniqueIndex:idx_user_media" json:"media_id,omitempty"`
	ArtistName string    `gorm:"uniqueIndex:idx_user_artist" json:"artist_name,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
}
```

Note: The `idx_user_media` unique index on (UserID, MediaID) prevents duplicate media favorites. The `idx_user_artist` unique index on (UserID, ArtistName) prevents duplicate artist favorites. Since MediaID is nullable for artist favorites and ArtistName is empty for media favorites, the two indexes won't conflict.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/models/ -run TestFavoriteFields -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/models/favorite.go backend/internal/models/models_test.go
git commit -m "feat: add Favorite model"
```

---

## Task 2: Collection + CollectionItem Models

**Files:**
- Create: `backend/internal/models/collection.go`
- Modify: `backend/internal/models/models_test.go`

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/models/models_test.go`:

```go
func TestCollectionFields(t *testing.T) {
	c := Collection{
		ID:        1,
		UserID:    1,
		Name:      "Want to Watch",
		Type:      "video",
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	if c.Name != "Want to Watch" || c.Type != "video" {
		t.Errorf("Collection fields not properly set: %+v", c)
	}
}

func TestCollectionItemFields(t *testing.T) {
	ci := CollectionItem{
		ID:           1,
		CollectionID: 1,
		MediaID:      5,
		AddedAt:      time.Now(),
	}
	if ci.CollectionID != 1 || ci.MediaID != 5 {
		t.Errorf("CollectionItem fields not properly set: %+v", ci)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/models/ -run "TestCollection" -v`
Expected: FAIL — `undefined: Collection`

- [ ] **Step 3: Write minimal implementation**

Create `backend/internal/models/collection.go`:

```go
package models

import "time"

// Collection is a user-created playlist of media items (e.g. "Want to Watch").
type Collection struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	UserID    uint      `gorm:"index" json:"user_id"`
	Name      string    `json:"name"`
	Type      string    `gorm:"index" json:"type"` // video
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// CollectionItem links a media item to a collection.
type CollectionItem struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	CollectionID uint      `gorm:"index;idx_collection_media,unique" json:"collection_id"`
	MediaID      uint      `gorm:"index;idx_collection_media,unique" json:"media_id"`
	AddedAt      time.Time `json:"added_at"`
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/models/ -run "TestCollection" -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/models/collection.go backend/internal/models/models_test.go
git commit -m "feat: add Collection and CollectionItem models"
```

---

## Task 3: Lyrics Model

**Files:**
- Create: `backend/internal/models/lyrics.go`
- Modify: `backend/internal/models/models_test.go`

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/models/models_test.go`:

```go
func TestLyricsFields(t *testing.T) {
	l := Lyrics{
		ID:          1,
		MediaID:     1,
		LyricsText:  "La la la",
		Translation: "Ля ля ля",
		SyncData:    `[{"t":0,"text":"La la la"}]`,
		Source:      "id3",
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
	}
	if l.MediaID != 1 || l.LyricsText != "La la la" || l.Translation != "Ля ля ля" {
		t.Errorf("Lyrics fields not properly set: %+v", l)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/models/ -run TestLyricsFields -v`
Expected: FAIL — `undefined: Lyrics`

- [ ] **Step 3: Write minimal implementation**

Create `backend/internal/models/lyrics.go`:

```go
package models

import "time"

// Lyrics holds optional lyrics text, translation, and sync timestamps for a media item.
type Lyrics struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	MediaID     uint      `gorm:"uniqueIndex" json:"media_id"`
	LyricsText  string    `gorm:"type:text" json:"lyrics_text"`
	Translation string    `gorm:"type:text" json:"translation"`
	SyncData    string    `gorm:"type:text" json:"sync_data"` // JSON array of {timestamp, text} pairs
	Source      string    `json:"source"`                      // id3, manual, external
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/models/ -run TestLyricsFields -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/models/lyrics.go backend/internal/models/models_test.go
git commit -m "feat: add Lyrics model"
```

---

## Task 4: Repository Interfaces

**Files:**
- Modify: `backend/internal/repository/interfaces.go`

- [ ] **Step 1: Write the new interfaces**

Append to `backend/internal/repository/interfaces.go`, before the closing of the file (after ProgressRepository):

```go
// FavoriteRepository defines data access methods for Favorite entities.
type FavoriteRepository interface {
	FindByUser(ctx context.Context, userID uint, favType string) ([]models.Favorite, error)
	FindByUserAndMedia(ctx context.Context, userID, mediaID uint) (*models.Favorite, error)
	FindByUserAndArtist(ctx context.Context, userID uint, artistName string) (*models.Favorite, error)
	IsFavorited(ctx context.Context, userID, mediaID uint) (bool, error)
	IsArtistFavorited(ctx context.Context, userID uint, artistName string) (bool, error)
	Create(ctx context.Context, favorite *models.Favorite) error
	Delete(ctx context.Context, userID, mediaID uint) error
	DeleteArtist(ctx context.Context, userID uint, artistName string) error
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
	Add(ctx context.Context, item *models.CollectionItem) error
	Remove(ctx context.Context, collectionID, mediaID uint) error
}

// LyricsRepository defines data access methods for Lyrics entities.
type LyricsRepository interface {
	FindByMediaID(ctx context.Context, mediaID uint) (*models.Lyrics, error)
	Upsert(ctx context.Context, lyrics *models.Lyrics) error
	Delete(ctx context.Context, mediaID uint) error
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd backend && go build ./internal/repository/`
Expected: Build fails — interfaces defined but no implementations yet. This is expected; we'll add implementations in subsequent tasks. The interfaces themselves are valid Go.

Actually, since the interfaces reference methods that don't have implementations yet, the package won't compile until we add the implementations. Let's proceed to the implementations in the next tasks. The interfaces are correct as written.

- [ ] **Step 3: Commit (interfaces only, will compile after Task 5-8)**

We'll commit interfaces together with the first implementation to keep the build green.

---

## Task 5: Favorite Repository Implementation

**Files:**
- Create: `backend/internal/repository/favorite.go`
- Create: `backend/internal/repository/favorite_test.go`

- [ ] **Step 1: Write the failing test**

Create `backend/internal/repository/favorite_test.go`:

```go
package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

func TestFavoriteStore_CreateAndFindByUser(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	mediaID := uint(10)
	fav := &models.Favorite{
		UserID:  1,
		Type:    "video",
		MediaID: &mediaID,
	}
	require.NoError(t, store.Create(ctx, fav))

	favs, err := store.FindByUser(ctx, 1, "video")
	assert.NoError(t, err)
	assert.Len(t, favs, 1)
	assert.Equal(t, "video", favs[0].Type)
}

func TestFavoriteStore_FindByUserAndMedia(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	mediaID := uint(10)
	require.NoError(t, store.Create(ctx, &models.Favorite{
		UserID:  1,
		Type:    "video",
		MediaID: &mediaID,
	}))

	found, err := store.FindByUserAndMedia(ctx, 1, 10)
	assert.NoError(t, err)
	assert.NotNil(t, found)
	assert.Equal(t, uint(1), found.UserID)
}

func TestFavoriteStore_IsFavorited(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	mediaID := uint(10)
	require.NoError(t, store.Create(ctx, &models.Favorite{
		UserID:  1,
		Type:    "video",
		MediaID: &mediaID,
	}))

	isFav, err := store.IsFavorited(ctx, 1, 10)
	assert.NoError(t, err)
	assert.True(t, isFav)

	isFav, err = store.IsFavorited(ctx, 1, 99)
	assert.NoError(t, err)
	assert.False(t, isFav)
}

func TestFavoriteStore_Delete(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	mediaID := uint(10)
	require.NoError(t, store.Create(ctx, &models.Favorite{
		UserID:  1,
		Type:    "video",
		MediaID: &mediaID,
	}))

	require.NoError(t, store.Delete(ctx, 1, 10))

	isFav, err := store.IsFavorited(ctx, 1, 10)
	assert.NoError(t, err)
	assert.False(t, isFav)
}

func TestFavoriteStore_ArtistFavorite(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Create(ctx, &models.Favorite{
		UserID:     1,
		Type:       "artist",
		ArtistName: "Pink Floyd",
	}))

	found, err := store.FindByUserAndArtist(ctx, 1, "Pink Floyd")
	assert.NoError(t, err)
	assert.NotNil(t, found)

	isFav, err := store.IsArtistFavorited(ctx, 1, "Pink Floyd")
	assert.NoError(t, err)
	assert.True(t, isFav)

	require.NoError(t, store.DeleteArtist(ctx, 1, "Pink Floyd"))

	isFav, err = store.IsArtistFavorited(ctx, 1, "Pink Floyd")
	assert.NoError(t, err)
	assert.False(t, isFav)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/repository/ -run TestFavoriteStore -v`
Expected: FAIL — `undefined: NewFavoriteRepository`

- [ ] **Step 3: Write minimal implementation**

Create `backend/internal/repository/favorite.go`:

```go
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

func (r *FavoriteStore) FindByUser(ctx context.Context, userID uint, favType string) ([]models.Favorite, error) {
	var favs []models.Favorite
	query := r.db.WithContext(ctx).Where("user_id = ?", userID)
	if favType != "" {
		query = query.Where("type = ?", favType)
	}
	err := query.Find(&favs).Error
	return favs, err
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
		Where("user_id = ? AND artist_name = ? AND type = ?", userID, artistName, "artist").
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
		Where("user_id = ? AND artist_name = ? AND type = ?", userID, artistName, "artist").
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
		Where("user_id = ? AND artist_name = ? AND type = ?", userID, artistName, "artist").
		Delete(&models.Favorite{})
	if result.RowsAffected == 0 {
		return errors.New("artist favorite not found")
	}
	return result.Error
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/repository/ -run TestFavoriteStore -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/repository/favorite.go backend/internal/repository/favorite_test.go backend/internal/repository/interfaces.go
git commit -m "feat: add Favorite repository with interfaces"
```

---

## Task 6: Collection Repository Implementation

**Files:**
- Create: `backend/internal/repository/collection.go`
- Create: `backend/internal/repository/collection_test.go`

- [ ] **Step 1: Write the failing test**

Create `backend/internal/repository/collection_test.go`:

```go
package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

func TestCollectionStore_CreateAndFindByUser(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewCollectionRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Create(ctx, &models.Collection{
		UserID: 1,
		Name:   "Want to Watch",
		Type:   "video",
	}))

	cols, err := store.FindByUser(ctx, 1)
	assert.NoError(t, err)
	assert.Len(t, cols, 1)
	assert.Equal(t, "Want to Watch", cols[0].Name)
}

func TestCollectionStore_FindByID(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewCollectionRepository(db)
	ctx := context.Background()

	col := &models.Collection{UserID: 1, Name: "Horror", Type: "video"}
	require.NoError(t, store.Create(ctx, col))

	found, err := store.FindByID(ctx, col.ID)
	assert.NoError(t, err)
	assert.Equal(t, "Horror", found.Name)
}

func TestCollectionStore_Update(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewCollectionRepository(db)
	ctx := context.Background()

	col := &models.Collection{UserID: 1, Name: "Old", Type: "video"}
	require.NoError(t, store.Create(ctx, col))

	col.Name = "New Name"
	require.NoError(t, store.Update(ctx, col))

	found, err := store.FindByID(ctx, col.ID)
	assert.NoError(t, err)
	assert.Equal(t, "New Name", found.Name)
}

func TestCollectionStore_Delete(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewCollectionRepository(db)
	ctx := context.Background()

	col := &models.Collection{UserID: 1, Name: "ToDelete", Type: "video"}
	require.NoError(t, store.Create(ctx, col))

	require.NoError(t, store.Delete(ctx, col.ID))

	_, err = store.FindByID(ctx, col.ID)
	assert.Error(t, err)
}

func TestCollectionItemStore_AddAndFindByCollection(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	itemStore := NewCollectionItemRepository(db)
	ctx := context.Background()

	require.NoError(t, itemStore.Add(ctx, &models.CollectionItem{
		CollectionID: 1,
		MediaID:      10,
	}))
	require.NoError(t, itemStore.Add(ctx, &models.CollectionItem{
		CollectionID: 1,
		MediaID:      20,
	}))

	items, err := itemStore.FindByCollection(ctx, 1)
	assert.NoError(t, err)
	assert.Len(t, items, 2)
}

func TestCollectionItemStore_Remove(t *testing.T) {
	db, err := InitDB(":memory:)
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	itemStore := NewCollectionItemRepository(db)
	ctx := context.Background()

	require.NoError(t, itemStore.Add(ctx, &models.CollectionItem{
		CollectionID: 1,
		MediaID:      10,
	}))

	require.NoError(t, itemStore.Remove(ctx, 1, 10))

	items, err := itemStore.FindByCollection(ctx, 1)
	assert.NoError(t, err)
	assert.Len(t, items, 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/repository/ -run TestCollection -v`
Expected: FAIL — `undefined: NewCollectionRepository`

- [ ] **Step 3: Write minimal implementation**

Create `backend/internal/repository/collection.go`:

```go
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/repository/ -run TestCollection -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/repository/collection.go backend/internal/repository/collection_test.go
git commit -m "feat: add Collection and CollectionItem repositories"
```

---

## Task 7: Lyrics Repository Implementation

**Files:**
- Create: `backend/internal/repository/lyrics.go`
- Create: `backend/internal/repository/lyrics_test.go`

- [ ] **Step 1: Write the failing test**

Create `backend/internal/repository/lyrics_test.go`:

```go
package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

func TestLyricsStore_UpsertAndFind(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewLyricsRepository(db)
	ctx := context.Background()

	lyrics := &models.Lyrics{
		MediaID:     1,
		LyricsText:  "La la la",
		Translation: "Ля ля ля",
		SyncData:    `[{"t":0,"text":"La la la"}]`,
		Source:      "id3",
	}
	require.NoError(t, store.Upsert(ctx, lyrics))

	found, err := store.FindByMediaID(ctx, 1)
	assert.NoError(t, err)
	assert.NotNil(t, found)
	assert.Equal(t, "La la la", found.LyricsText)
	assert.Equal(t, "Ля ля ля", found.Translation)
}

func TestLyricsStore_UpsertReplaces(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewLyricsRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Upsert(ctx, &models.Lyrics{
		MediaID:    1,
		LyricsText: "Original",
		Source:     "id3",
	}))
	require.NoError(t, store.Upsert(ctx, &models.Lyrics{
		MediaID:    1,
		LyricsText: "Updated",
		Source:     "manual",
	}))

	found, err := store.FindByMediaID(ctx, 1)
	assert.NoError(t, err)
	assert.Equal(t, "Updated", found.LyricsText)
}

func TestLyricsStore_Delete(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewLyricsRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Upsert(ctx, &models.Lyrics{
		MediaID:    1,
		LyricsText: "La la la",
	}))

	require.NoError(t, store.Delete(ctx, 1))

	_, err = store.FindByMediaID(ctx, 1)
	assert.Error(t, err)
}

func TestLyricsStore_FindNotFound(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewLyricsRepository(db)
	ctx := context.Background()

	_, err = store.FindByMediaID(ctx, 999)
	assert.Error(t, err)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/repository/ -run TestLyricsStore -v`
Expected: FAIL — `undefined: NewLyricsRepository`

- [ ] **Step 3: Write minimal implementation**

Create `backend/internal/repository/lyrics.go`:

```go
package repository

import (
	"context"

	"flux/internal/models"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type LyricsStore struct {
	db *gorm.DB
}

func NewLyricsRepository(db *gorm.DB) *LyricsStore {
	return &LyricsStore{db: db}
}

func (r *LyricsStore) FindByMediaID(ctx context.Context, mediaID uint) (*models.Lyrics, error) {
	var lyrics models.Lyrics
	err := r.db.WithContext(ctx).Where("media_id = ?", mediaID).First(&lyrics).Error
	return &lyrics, err
}

func (r *LyricsStore) Upsert(ctx context.Context, lyrics *models.Lyrics) error {
	return r.db.WithContext(ctx).Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "media_id"}},
		DoUpdates: clause.AssignmentColumns([]string{"lyrics_text", "translation", "sync_data", "source", "updated_at"}),
	}).Create(lyrics).Error
}

func (r *LyricsStore) Delete(ctx context.Context, mediaID uint) error {
	return r.db.WithContext(ctx).Where("media_id = ?", mediaID).Delete(&models.Lyrics{}).Error
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/repository/ -run TestLyricsStore -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/repository/lyrics.go backend/internal/repository/lyrics_test.go
git commit -m "feat: add Lyrics repository"
```

---

## Task 8: Update AutoMigrate and DB Tests

**Files:**
- Modify: `backend/internal/repository/db.go`
- Modify: `backend/internal/repository/db_test.go`

- [ ] **Step 1: Update the failing test**

In `backend/internal/repository/db_test.go`, add assertions for new tables to `TestAutoMigrate`:

```go
func TestAutoMigrate(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)

	err = AutoMigrate(db)
	assert.NoError(t, err)

	// Verify tables were created
	var tables []string
	err = db.Raw("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").Scan(&tables).Error
	assert.NoError(t, err)

	tableSet := make(map[string]bool)
	for _, t := range tables {
		tableSet[t] = true
	}

	assert.True(t, tableSet["media"])
	assert.True(t, tableSet["metadata"])
	assert.True(t, tableSet["users"])
	assert.True(t, tableSet["watch_progresses"])
	assert.True(t, tableSet["media_libraries"])
	assert.True(t, tableSet["favorites"])
	assert.True(t, tableSet["collections"])
	assert.True(t, tableSet["collection_items"])
	assert.True(t, tableSet["lyrics"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/repository/ -run TestAutoMigrate -v`
Expected: FAIL — `favorites`, `collections`, `collection_items`, `lyrics` tables don't exist yet

- [ ] **Step 3: Update AutoMigrate**

In `backend/internal/repository/db.go`, add new models to `AutoMigrate`:

```go
func AutoMigrate(db *gorm.DB) error {
	return db.AutoMigrate(
		&models.Media{},
		&models.Metadata{},
		&models.User{},
		&models.WatchProgress{},
		&models.MediaLibrary{},
		&models.Favorite{},
		&models.Collection{},
		&models.CollectionItem{},
		&models.Lyrics{},
	)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/repository/ -run TestAutoMigrate -v`
Expected: PASS

- [ ] **Step 5: Run all repository tests**

Run: `cd backend && go test ./internal/repository/ -v`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add backend/internal/repository/db.go backend/internal/repository/db_test.go
git commit -m "feat: add new models to AutoMigrate"
```

---

## Task 9: Favorite Handler

**Files:**
- Create: `backend/internal/handlers/favorite.go`
- Create: `backend/internal/handlers/favorite_test.go`

- [ ] **Step 1: Write the failing test**

Create `backend/internal/handlers/favorite_test.go`:

```go
package handlers

import (
	"bytes"
	"encoding/json"
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)

func setupFavoriteTestApp(t *testing.T) (*fiber.App, *FavoriteHandler) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	favRepo := repository.NewFavoriteRepository(db)
	mediaRepo := repository.NewMediaRepository(db)

	// Create a test media item
	require.NoError(t, mediaRepo.Create(nil, &models.Media{
		Title:    "Test Movie",
		Type:     "video",
		FilePath: "/test.mkv",
	}))

	handler := NewFavoriteHandler(favRepo, mediaRepo)
	app := fiber.New()

	// Simulate authenticated user
	app.Use(func(c *fiber.Ctx) error {
		c.Locals("user_id", uint(1))
		return c.Next()
	})

	app.Post("/api/media/:id/favorite", handler.AddFavorite)
	app.Delete("/api/media/:id/favorite", handler.RemoveFavorite)
	app.Get("/api/favorites", handler.ListFavorites)

	return app, handler
}

func TestFavoriteHandler_AddFavorite(t *testing.T) {
	app, _ := setupFavoriteTestApp(t)

	req := httptest.NewRequest("POST", "/api/media/1/favorite", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)
}

func TestFavoriteHandler_RemoveFavorite(t *testing.T) {
	app, _ := setupFavoriteTestApp(t)

	// Add first
	req := httptest.NewRequest("POST", "/api/media/1/favorite", nil)
	_, err := app.Test(req)
	require.NoError(t, err)

	// Remove
	req = httptest.NewRequest("DELETE", "/api/media/1/favorite", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}

func TestFavoriteHandler_ListFavorites(t *testing.T) {
	app, _ := setupFavoriteTestApp(t)

	// Add a favorite
	req := httptest.NewRequest("POST", "/api/media/1/favorite", nil)
	_, err := app.Test(req)
	require.NoError(t, err)

	// List
	req = httptest.NewRequest("GET", "/api/favorites?type=video", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var favs []models.Favorite
	body := bytes.Buffer{}
	body.ReadFrom(resp.Body)
	json.Unmarshal(body.Bytes(), &favs)
	assert.Len(t, favs, 1)
}

func TestFavoriteHandler_AddArtistFavorite(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	favRepo := repository.NewFavoriteRepository(db)
	mediaRepo := repository.NewMediaRepository(db)
	handler := NewFavoriteHandler(favRepo, mediaRepo)

	app := fiber.New()
	app.Use(func(c *fiber.Ctx) error {
		c.Locals("user_id", uint(1))
		return c.Next()
	})
	app.Post("/api/favorites/artist", handler.AddArtistFavorite)

	body, _ := json.Marshal(map[string]string{"artist": "Pink Floyd"})
	req := httptest.NewRequest("POST", "/api/favorites/artist", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/handlers/ -run TestFavoriteHandler -v`
Expected: FAIL — `undefined: NewFavoriteHandler`

- [ ] **Step 3: Write minimal implementation**

Create `backend/internal/handlers/favorite.go`:

```go
package handlers

import (
	"errors"
	"log"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
)

type FavoriteHandler struct {
	favRepo   repository.FavoriteRepository
	mediaRepo repository.MediaRepository
}

func NewFavoriteHandler(favRepo repository.FavoriteRepository, mediaRepo repository.MediaRepository) *FavoriteHandler {
	return &FavoriteHandler{favRepo: favRepo, mediaRepo: mediaRepo}
}

// AddFavorite adds a media item to the user's favorites.
func (h *FavoriteHandler) AddFavorite(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	mediaID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()

	// Verify media exists and determine type
	media, err := h.mediaRepo.FindByID(ctx, uint(mediaID))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Media not found")
	}

	mediaIDUint := uint(mediaID)
	fav := &models.Favorite{
		UserID:  userID,
		Type:    media.Type,
		MediaID: &mediaIDUint,
	}

	if err := h.favRepo.Create(ctx, fav); err != nil {
		log.Printf("Create favorite: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to add favorite")
	}

	return c.Status(fiber.StatusCreated).JSON(fav)
}

// RemoveFavorite removes a media item from the user's favorites.
func (h *FavoriteHandler) RemoveFavorite(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	mediaID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()

	if err := h.favRepo.Delete(ctx, userID, uint(mediaID)); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return response.Error(c, fiber.StatusNotFound, "Favorite not found")
		}
		log.Printf("Delete favorite: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to remove favorite")
	}

	return c.JSON(fiber.Map{"message": "Favorite removed"})
}

// ListFavorites returns the user's favorites, optionally filtered by type.
func (h *FavoriteHandler) ListFavorites(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	favType := c.Query("type")

	ctx := c.UserContext()
	favs, err := h.favRepo.FindByUser(ctx, userID, favType)
	if err != nil {
		log.Printf("FindByUser favorites: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch favorites")
	}

	return c.JSON(favs)
}

// AddArtistFavorite adds an artist to the user's favorites.
func (h *FavoriteHandler) AddArtistFavorite(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	var req struct {
		Artist string `json:"artist"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.Artist == "" {
		return response.Error(c, fiber.StatusBadRequest, "Artist name is required")
	}

	ctx := c.UserContext()

	fav := &models.Favorite{
		UserID:     userID,
		Type:       "artist",
		ArtistName: req.Artist,
	}

	if err := h.favRepo.Create(ctx, fav); err != nil {
		log.Printf("Create artist favorite: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to add artist favorite")
	}

	return c.Status(fiber.StatusCreated).JSON(fav)
}

// RemoveArtistFavorite removes an artist from the user's favorites.
func (h *FavoriteHandler) RemoveArtistFavorite(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	artist := c.Query("artist")
	if artist == "" {
		return response.Error(c, fiber.StatusBadRequest, "Artist query parameter is required")
	}

	ctx := c.UserContext()

	if err := h.favRepo.DeleteArtist(ctx, userID, artist); err != nil {
		log.Printf("DeleteArtist favorite: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to remove artist favorite")
	}

	return c.JSON(fiber.Map{"message": "Artist favorite removed"})
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/handlers/ -run TestFavoriteHandler -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/handlers/favorite.go backend/internal/handlers/favorite_test.go
git commit -m "feat: add Favorite HTTP handlers"
```

---

## Task 10: Collection Handler

**Files:**
- Create: `backend/internal/handlers/collection.go`
- Create: `backend/internal/handlers/collection_test.go`

- [ ] **Step 1: Write the failing test**

Create `backend/internal/handlers/collection_test.go`:

```go
package handlers

import (
	"bytes"
	"encoding/json"
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)

func setupCollectionTestApp(t *testing.T) *fiber.App {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	colRepo := repository.NewCollectionRepository(db)
	itemRepo := repository.NewCollectionItemRepository(db)
	mediaRepo := repository.NewMediaRepository(db)

	// Create test media
	require.NoError(t, mediaRepo.Create(nil, &models.Media{
		Title:    "Test Movie",
		Type:     "video",
		FilePath: "/test.mkv",
	}))

	handler := NewCollectionHandler(colRepo, itemRepo, mediaRepo)
	app := fiber.New()

	app.Use(func(c *fiber.Ctx) error {
		c.Locals("user_id", uint(1))
		return c.Next()
	})

	app.Post("/api/collections", handler.Create)
	app.Get("/api/collections", handler.List)
	app.Put("/api/collections/:id", handler.Update)
	app.Delete("/api/collections/:id", handler.Delete)
	app.Post("/api/collections/:id/items", handler.AddItem)
	app.Delete("/api/collections/:id/items/:mediaId", handler.RemoveItem)
	app.Get("/api/collections/:id/items", handler.ListItems)

	return app
}

func TestCollectionHandler_Create(t *testing.T) {
	app := setupCollectionTestApp(t)

	body, _ := json.Marshal(map[string]string{"name": "Want to Watch", "type": "video"})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)
}

func TestCollectionHandler_List(t *testing.T) {
	app := setupCollectionTestApp(t)

	// Create one
	body, _ := json.Marshal(map[string]string{"name": "Horror", "type": "video"})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	_, err := app.Test(req)
	require.NoError(t, err)

	// List
	req = httptest.NewRequest("GET", "/api/collections", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var cols []models.Collection
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	json.Unmarshal(buf.Bytes(), &cols)
	assert.Len(t, cols, 1)
}

func TestCollectionHandler_Update(t *testing.T) {
	app := setupCollectionTestApp(t)

	// Create
	body, _ := json.Marshal(map[string]string{"name": "Old Name", "type": "video"})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)

	var col models.Collection
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	json.Unmarshal(buf.Bytes(), &col)

	// Update
	body, _ = json.Marshal(map[string]string{"name": "New Name"})
	req = httptest.NewRequest("PUT", "/api/collections/"+strconv.Itoa(int(col.ID)), bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}

func TestCollectionHandler_AddAndRemoveItem(t *testing.T) {
	app := setupCollectionTestApp(t)

	// Create collection
	body, _ := json.Marshal(map[string]string{"name": "My List", "type": "video"})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)

	var col models.Collection
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	json.Unmarshal(buf.Bytes(), &col)

	// Add item
	body, _ = json.Marshal(map[string]int{"media_id": 1})
	req = httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(col.ID))+"/items", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)

	// List items
	req = httptest.NewRequest("GET", "/api/collections/"+strconv.Itoa(int(col.ID))+"/items", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	// Remove item
	req = httptest.NewRequest("DELETE", "/api/collections/"+strconv.Itoa(int(col.ID))+"/items/1", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}
```

Note: The test file needs `strconv` import. Add it to the import block.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/handlers/ -run TestCollectionHandler -v`
Expected: FAIL — `undefined: NewCollectionHandler`

- [ ] **Step 3: Write minimal implementation**

Create `backend/internal/handlers/collection.go`:

```go
package handlers

import (
	"log"
	"strconv"

	"github.com/gofiber/fiber/v2"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
)

type CollectionHandler struct {
	colRepo   repository.CollectionRepository
	itemRepo  repository.CollectionItemRepository
	mediaRepo repository.MediaRepository
}

func NewCollectionHandler(
	colRepo repository.CollectionRepository,
	itemRepo repository.CollectionItemRepository,
	mediaRepo repository.MediaRepository,
) *CollectionHandler {
	return &CollectionHandler{colRepo: colRepo, itemRepo: itemRepo, mediaRepo: mediaRepo}
}

type CreateCollectionRequest struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

func (h *CollectionHandler) Create(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	var req CreateCollectionRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.Name == "" {
		return response.Error(c, fiber.StatusBadRequest, "Name is required")
	}
	if req.Type == "" {
		req.Type = "video"
	}

	ctx := c.UserContext()
	col := &models.Collection{
		UserID: userID,
		Name:   req.Name,
		Type:   req.Type,
	}

	if err := h.colRepo.Create(ctx, col); err != nil {
		log.Printf("Create collection: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create collection")
	}

	return c.Status(fiber.StatusCreated).JSON(col)
}

func (h *CollectionHandler) List(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	ctx := c.UserContext()
	cols, err := h.colRepo.FindByUser(ctx, userID)
	if err != nil {
		log.Printf("List collections: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch collections")
	}

	return c.JSON(cols)
}

func (h *CollectionHandler) Update(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	id, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	ctx := c.UserContext()
	col, err := h.colRepo.FindByID(ctx, uint(id))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Collection not found")
	}

	if col.UserID != userID {
		return response.Error(c, fiber.StatusForbidden, "Not your collection")
	}

	var req CreateCollectionRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.Name != "" {
		col.Name = req.Name
	}

	if err := h.colRepo.Update(ctx, col); err != nil {
		log.Printf("Update collection: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to update collection")
	}

	return c.JSON(col)
}

func (h *CollectionHandler) Delete(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	id, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	ctx := c.UserContext()
	col, err := h.colRepo.FindByID(ctx, uint(id))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Collection not found")
	}

	if col.UserID != userID {
		return response.Error(c, fiber.StatusForbidden, "Not your collection")
	}

	if err := h.colRepo.Delete(ctx, uint(id)); err != nil {
		log.Printf("Delete collection: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to delete collection")
	}

	return c.JSON(fiber.Map{"message": "Collection deleted"})
}

type AddItemRequest struct {
	MediaID uint `json:"media_id"`
}

func (h *CollectionHandler) AddItem(c *fiber.Ctx) error {
	collectionID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	var req AddItemRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.MediaID == 0 {
		return response.Error(c, fiber.StatusBadRequest, "media_id is required")
	}

	ctx := c.UserContext()

	// Verify media exists
	if _, err := h.mediaRepo.FindByID(ctx, req.MediaID); err != nil {
		return response.Error(c, fiber.StatusNotFound, "Media not found")
	}

	item := &models.CollectionItem{
		CollectionID: uint(collectionID),
		MediaID:      req.MediaID,
	}

	if err := h.itemRepo.Add(ctx, item); err != nil {
		log.Printf("Add collection item: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to add item to collection")
	}

	return c.Status(fiber.StatusCreated).JSON(item)
}

func (h *CollectionHandler) RemoveItem(c *fiber.Ctx) error {
	collectionID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	mediaID, err := c.ParamsInt("mediaId")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()

	if err := h.itemRepo.Remove(ctx, uint(collectionID), uint(mediaID)); err != nil {
		log.Printf("Remove collection item: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to remove item")
	}

	return c.JSON(fiber.Map{"message": "Item removed"})
}

func (h *CollectionHandler) ListItems(c *fiber.Ctx) error {
	collectionID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	ctx := c.UserContext()
	items, err := h.itemRepo.FindByCollection(ctx, uint(collectionID))
	if err != nil {
		log.Printf("List collection items: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch items")
	}

	return c.JSON(items)
}
```

- [ ] **Step 4: Fix the test import**

The test uses `strconv` — add it to the import block in `collection_test.go`:

```go
import (
	"bytes"
	"encoding/json"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd backend && go test ./internal/handlers/ -run TestCollectionHandler -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add backend/internal/handlers/collection.go backend/internal/handlers/collection_test.go
git commit -m "feat: add Collection HTTP handlers"
```

---

## Task 11: Lyrics Handler

**Files:**
- Create: `backend/internal/handlers/lyrics.go`
- Create: `backend/internal/handlers/lyrics_test.go`

- [ ] **Step 1: Write the failing test**

Create `backend/internal/handlers/lyrics_test.go`:

```go
package handlers

import (
	"bytes"
	"encoding/json"
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)

func setupLyricsTestApp(t *testing.T) *fiber.App {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	lyricsRepo := repository.NewLyricsRepository(db)
	mediaRepo := repository.NewMediaRepository(db)

	// Create test media
	require.NoError(t, mediaRepo.Create(nil, &models.Media{
		Title:    "Test Song",
		Type:     "audio",
		FilePath: "/test.mp3",
	}))

	handler := NewLyricsHandler(lyricsRepo)
	app := fiber.New()

	app.Use(func(c *fiber.Ctx) error {
		c.Locals("user_id", uint(1))
		return c.Next()
	})

	app.Get("/api/media/:id/lyrics", handler.GetLyrics)
	app.Put("/api/media/:id/lyrics", handler.UpsertLyrics)

	return app
}

func TestLyricsHandler_GetLyrics_NotFound(t *testing.T) {
	app := setupLyricsTestApp(t)

	req := httptest.NewRequest("GET", "/api/media/1/lyrics", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}

func TestLyricsHandler_UpsertAndGetLyrics(t *testing.T) {
	app := setupLyricsTestApp(t)

	// Upsert lyrics
	body, _ := json.Marshal(map[string]string{
		"lyrics_text": "La la la",
		"translation": "Ля ля ля",
		"source":      "manual",
	})
	req := httptest.NewRequest("PUT", "/api/media/1/lyrics", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	// Get lyrics
	req = httptest.NewRequest("GET", "/api/media/1/lyrics", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var lyrics models.Lyrics
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	json.Unmarshal(buf.Bytes(), &lyrics)
	assert.Equal(t, "La la la", lyrics.LyricsText)
	assert.Equal(t, "Ля ля ля", lyrics.Translation)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/handlers/ -run TestLyricsHandler -v`
Expected: FAIL — `undefined: NewLyricsHandler`

- [ ] **Step 3: Write minimal implementation**

Create `backend/internal/handlers/lyrics.go`:

```go
package handlers

import (
	"errors"
	"log"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
)

type LyricsHandler struct {
	lyricsRepo repository.LyricsRepository
}

func NewLyricsHandler(lyricsRepo repository.LyricsRepository) *LyricsHandler {
	return &LyricsHandler{lyricsRepo: lyricsRepo}
}

// GetLyrics returns lyrics for a media item.
func (h *LyricsHandler) GetLyrics(c *fiber.Ctx) error {
	mediaID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	lyrics, err := h.lyricsRepo.FindByMediaID(ctx, uint(mediaID))
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return response.Error(c, fiber.StatusNotFound, "Lyrics not found")
		}
		log.Printf("GetLyrics: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch lyrics")
	}

	return c.JSON(lyrics)
}

type UpsertLyricsRequest struct {
	LyricsText  string `json:"lyrics_text"`
	Translation string `json:"translation"`
	SyncData    string `json:"sync_data"`
	Source      string `json:"source"`
}

// UpsertLyrics creates or updates lyrics for a media item.
func (h *LyricsHandler) UpsertLyrics(c *fiber.Ctx) error {
	mediaID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	var req UpsertLyricsRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	ctx := c.UserContext()

	lyrics := &models.Lyrics{
		MediaID:     uint(mediaID),
		LyricsText:  req.LyricsText,
		Translation: req.Translation,
		SyncData:    req.SyncData,
		Source:      req.Source,
	}

	if err := h.lyricsRepo.Upsert(ctx, lyrics); err != nil {
		log.Printf("UpsertLyrics: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save lyrics")
	}

	return c.JSON(lyrics)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/handlers/ -run TestLyricsHandler -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/handlers/lyrics.go backend/internal/handlers/lyrics_test.go
git commit -m "feat: add Lyrics HTTP handlers"
```

---

## Task 12: Wire Routes in app.go

**Files:**
- Modify: `backend/internal/app/app.go`

- [ ] **Step 1: Add repository and handler wiring**

In `backend/internal/app/app.go`, add imports and wire the new repositories and handlers. After the existing repository creation (line ~49), add:

```go
favRepo := repository.NewFavoriteRepository(db)
colRepo := repository.NewCollectionRepository(db)
colItemRepo := repository.NewCollectionItemRepository(db)
lyricsRepo := repository.NewLyricsRepository(db)
```

After the existing handler creation (line ~113), add:

```go
favoriteHandler := handlers.NewFavoriteHandler(favRepo, mediaRepo)
collectionHandler := handlers.NewCollectionHandler(colRepo, colItemRepo, mediaRepo)
lyricsHandler := handlers.NewLyricsHandler(lyricsRepo)
```

- [ ] **Step 2: Add routes**

In the same file, after the metadata routes (line ~187), add:

```go
// Favorites
api.Post("/media/:id/favorite", favoriteHandler.AddFavorite)
api.Delete("/media/:id/favorite", favoriteHandler.RemoveFavorite)
api.Get("/favorites", favoriteHandler.ListFavorites)
api.Post("/favorites/artist", favoriteHandler.AddArtistFavorite)
api.Delete("/favorites/artist", favoriteHandler.RemoveArtistFavorite)

// Collections
api.Post("/collections", collectionHandler.Create)
api.Get("/collections", collectionHandler.List)
api.Put("/collections/:id", collectionHandler.Update)
api.Delete("/collections/:id", collectionHandler.Delete)
api.Post("/collections/:id/items", collectionHandler.AddItem)
api.Delete("/collections/:id/items/:mediaId", collectionHandler.RemoveItem)
api.Get("/collections/:id/items", collectionHandler.ListItems)

// Lyrics
api.Get("/media/:id/lyrics", lyricsHandler.GetLyrics)
api.Put("/media/:id/lyrics", lyricsHandler.UpsertLyrics)
```

- [ ] **Step 3: Verify it compiles**

Run: `cd backend && go build ./...`
Expected: Build succeeds

- [ ] **Step 4: Run all tests**

Run: `cd backend && go test ./... -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/app/app.go
git commit -m "feat: wire favorites, collections, and lyrics routes in app.go"
```

---

## Task 13: Final Integration Verification

- [ ] **Step 1: Run full test suite**

Run: `cd backend && go test ./... -v`
Expected: ALL PASS

- [ ] **Step 2: Run build**

Run: `cd backend && go build -o /dev/null ./cmd/server`
Expected: Build succeeds

- [ ] **Step 3: Verify route list**

Run: `cd backend && go run ./cmd/server -config configs/config.yaml &` then test endpoints:

```bash
# Health check
curl -s http://localhost:8080/health

# Favorites (requires auth, expect 401)
curl -s http://localhost:8080/api/favorites

# Collections (requires auth, expect 401)
curl -s http://localhost:8080/api/collections

# Lyrics (requires auth, expect 401)
curl -s http://localhost:8080/api/media/1/lyrics
```

Expected: Health returns 200, others return 401 (no token)

Kill the server: `kill %1`

- [ ] **Step 4: Final commit if any cleanup needed**

```bash
git add -A
git commit -m "chore: backend foundations complete"
```
