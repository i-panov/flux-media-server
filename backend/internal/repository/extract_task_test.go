package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

func TestExtractTaskStore_CRUD(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	store := NewExtractTaskRepository(db)
	ctx := context.Background()

	task := &models.ExtractTask{SourceMediaID: 7, Status: "queued"}
	require.NoError(t, store.Create(ctx, task))
	require.NotZero(t, task.ID)

	got, err := store.Get(ctx, task.ID)
	require.NoError(t, err)
	assert.Equal(t, uint(7), got.SourceMediaID)
	assert.Equal(t, "queued", got.Status)

	require.NoError(t, store.SetStatus(ctx, task.ID, "done", "", 9))
	got, err = store.Get(ctx, task.ID)
	require.NoError(t, err)
	assert.Equal(t, "done", got.Status)
	assert.Equal(t, uint(9), got.MediaID)

	require.NoError(t, store.Delete(ctx, task.ID))
	_, err = store.Get(ctx, task.ID)
	require.Error(t, err)
}

func TestExtractTaskStore_UnfinishedAndActive(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	store := NewExtractTaskRepository(db)
	ctx := context.Background()

	seed := []models.ExtractTask{
		{SourceMediaID: 1, Status: "queued"},
		{SourceMediaID: 2, Status: "processing"},
		{SourceMediaID: 3, Status: "done", MediaID: 30},
		{SourceMediaID: 4, Status: "error", Error: "boom"},
	}
	for i := range seed {
		require.NoError(t, store.Create(ctx, &seed[i]))
	}

	unfinished, err := store.FindUnfinished(ctx, "queued", "processing")
	require.NoError(t, err)
	require.Len(t, unfinished, 2)
	assert.Equal(t, uint(1), unfinished[0].SourceMediaID)
	assert.Equal(t, uint(2), unfinished[1].SourceMediaID)

	active, err := store.FindActiveBySource(ctx, 2, "queued", "processing")
	require.NoError(t, err)
	assert.Equal(t, seed[1].ID, active.ID)

	_, err = store.FindActiveBySource(ctx, 3, "queued", "processing")
	require.Error(t, err)

	_, err = store.FindActiveBySource(ctx, 999, "queued", "processing")
	require.Error(t, err)
}
