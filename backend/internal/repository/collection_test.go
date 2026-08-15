package repository

import (
	"context"
	"fmt"
	"sync"
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
		Type:   models.MediaTypeVideo,
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

// Regression test (MAJOR): частичный Update не должен затирать type
// (старый Save писал все колонки включая нулевые).
func TestCollectionStore_UpdatePartialFields(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewCollectionRepository(db)
	ctx := context.Background()

	col := &models.Collection{UserID: 1, Name: "Want to Watch", Type: models.MediaTypeVideo}
	require.NoError(t, store.Create(ctx, col))

	require.NoError(t, store.Update(ctx, &models.Collection{ID: col.ID, Name: "Renamed"}))

	found, err := store.FindByID(ctx, col.ID)
	require.NoError(t, err)
	assert.Equal(t, "Renamed", found.Name)
	assert.Equal(t, models.MediaTypeVideo, found.Type, "type must be preserved on partial update")
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

	// Создаём коллекцию и медиа, чтобы FK constraints были удовлетворены.
	require.NoError(t, db.Create(&models.Collection{ID: 1, Name: "Test"}).Error)
	require.NoError(t, db.Create(&models.Media{ID: 10, Title: "M10"}).Error)
	require.NoError(t, db.Create(&models.Media{ID: 20, Title: "M20"}).Error)

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
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	// Создаём коллекцию и медиа, чтобы FK constraints были удовлетворены.
	require.NoError(t, db.Create(&models.Collection{ID: 1, Name: "Test"}).Error)
	require.NoError(t, db.Create(&models.Media{ID: 10, Title: "M10"}).Error)

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

// Regression test (MAJOR): AddItemAtomic присваивает позицию MAX+1 в одной
// транзакции и возвращает корректную ошибку дубликата.
func TestCollectionItemStore_AddItemAtomic(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	require.NoError(t, db.Create(&models.Collection{ID: 1, Name: "Test"}).Error)
	for _, id := range []uint{10, 20, 30} {
		require.NoError(t, db.Create(&models.Media{ID: id, Title: fmt.Sprintf("M%d", id)}).Error)
	}

	itemStore := NewCollectionItemRepository(db)
	ctx := context.Background()

	item1, err := itemStore.AddItemAtomic(ctx, 1, 10)
	require.NoError(t, err)
	assert.Equal(t, 1, item1.Position, "first item gets position 1")
	require.NotZero(t, item1.ID)
	require.NotZero(t, item1.AddedAt)

	item2, err := itemStore.AddItemAtomic(ctx, 1, 20)
	require.NoError(t, err)
	assert.Equal(t, 2, item2.Position)

	// Дубликат (collection_id, media_id) → ErrDuplicateItem.
	_, err = itemStore.AddItemAtomic(ctx, 1, 10)
	assert.ErrorIs(t, err, ErrDuplicateItem, "duplicate item must return ErrDuplicateItem")

	// Третья запись получает следующую позицию.
	item3, err := itemStore.AddItemAtomic(ctx, 1, 30)
	require.NoError(t, err)
	assert.Equal(t, 3, item3.Position)
}

// Regression test (MAJOR): параллельные AddItemAtomic разным медиа не должны
// получить одинаковую позицию (гонка MAX+INSERT вне транзакции). Файловая
// БД нужна для конкурентных транзакций.
func TestCollectionItemStore_AddItemAtomicParallel(t *testing.T) {
	db := fileDB(t)

	require.NoError(t, db.Create(&models.Collection{ID: 1, Name: "Test"}).Error)
	const n = 6
	for i := 0; i < n; i++ {
		require.NoError(t, db.Create(&models.Media{ID: uint(100 + i), Title: fmt.Sprintf("M%d", i)}).Error)
	}

	itemStore := NewCollectionItemRepository(db)
	ctx := context.Background()

	var wg sync.WaitGroup
	start := make(chan struct{})
	errs := make([]error, n)
	items := make([]models.CollectionItem, n)
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			items[i], errs[i] = itemStore.AddItemAtomic(ctx, 1, uint(100+i))
		}(i)
	}
	close(start)
	wg.Wait()

	positions := make(map[int]bool)
	for i := 0; i < n; i++ {
		require.NoError(t, errs[i], "all parallel adds must succeed")
		require.False(t, positions[items[i].Position], "positions must be unique: %d duplicated", items[i].Position)
		positions[items[i].Position] = true
	}
	assert.Equal(t, n, len(positions))

	// Позиции — 1..n без пропусков.
	for p := 1; p <= n; p++ {
		assert.True(t, positions[p], "position %d must be present", p)
	}
}
