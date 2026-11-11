package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

func newSettingTestStore(t *testing.T) *SettingStore {
	t.Helper()
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	return NewSettingRepository(db)
}

func TestSettingStore_GetMissing(t *testing.T) {
	store := newSettingTestStore(t)

	value, ok, err := store.Get(context.Background(), "missing")
	require.NoError(t, err)
	assert.False(t, ok)
	assert.Empty(t, value)
}

func TestSettingStore_SetGetOverwrite(t *testing.T) {
	store := newSettingTestStore(t)
	ctx := context.Background()

	require.NoError(t, store.Set(ctx, "k", "v1"))
	value, ok, err := store.Get(ctx, "k")
	require.NoError(t, err)
	assert.True(t, ok)
	assert.Equal(t, "v1", value)

	require.NoError(t, store.Set(ctx, "k", "v2"))
	value, ok, err = store.Get(ctx, "k")
	require.NoError(t, err)
	assert.True(t, ok)
	assert.Equal(t, "v2", value)

	// В таблице ровно одна строка: Set — upsert, а не insert.
	var count int64
	require.NoError(t, store.db.Model(&models.Setting{}).Where("key = ?", "k").Count(&count).Error)
	assert.Equal(t, int64(1), count)
}

func TestSettingStore_Bool(t *testing.T) {
	store := newSettingTestStore(t)
	ctx := context.Background()

	value, ok, err := store.GetBool(ctx, SettingAutoCleanupOriginals)
	require.NoError(t, err)
	assert.False(t, ok)
	assert.False(t, value)

	require.NoError(t, store.SetBool(ctx, SettingAutoCleanupOriginals, true))
	value, ok, err = store.GetBool(ctx, SettingAutoCleanupOriginals)
	require.NoError(t, err)
	assert.True(t, ok)
	assert.True(t, value)

	require.NoError(t, store.SetBool(ctx, SettingAutoCleanupOriginals, false))
	value, ok, err = store.GetBool(ctx, SettingAutoCleanupOriginals)
	require.NoError(t, err)
	assert.True(t, ok)
	assert.False(t, value)
}

func TestSettingStore_BoolInvalidValueIsUnset(t *testing.T) {
	store := newSettingTestStore(t)
	ctx := context.Background()

	require.NoError(t, store.Set(ctx, "k", "not-a-bool"))
	value, ok, err := store.GetBool(ctx, "k")
	require.NoError(t, err)
	assert.False(t, ok, "испорченное значение не должно выглядеть как настройка")
	assert.False(t, value)
}
