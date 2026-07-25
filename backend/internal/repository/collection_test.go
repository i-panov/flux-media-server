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
	db, err := InitDB(":memory:")
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
