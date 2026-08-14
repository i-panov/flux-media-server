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
