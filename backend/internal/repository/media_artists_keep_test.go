package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

// Регрессия (P0): Update на записи, прочитанной БЕЗ Preload("Artists"),
// стирал связи видео с артистами.
//
// Цепочка: resolveArtists(nil) возвращает НЕ-nil пустой срез
// (make([]models.Artist, 0, 0)), updateMediaTx присваивает его обратно в
// media.Artists, после чего проверка `media.Artists != nil` истинна, и
// Association("Artists").Replace(&пустой срез) удаляет все строки
// media_artists у этой записи.
//
// Триггером был бэкфилл размеров кадра при старте сервера: он брал
// записи без артистов и вызывал на них Update.
func TestMediaStore_UpdateWithoutArtistsKeepsThem(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	// Видео с артистом.
	media := &models.Media{
		Title: "With Artist", Type: models.MediaTypeVideo, FilePath: "/a.mkv",
		Artists: []models.Artist{{Name: "Someone"}},
	}
	require.NoError(t, store.Create(ctx, media))

	full, err := store.FindByID(ctx, media.ID)
	require.NoError(t, err)
	require.Len(t, full.Artists, 1, "создание должно было привязать артиста")

	// Запись, прочитанная БЕЗ Preload: Artists == nil. Именно так её
	// получает бэкфилл размеров.
	bare := &models.Media{ID: media.ID}
	err = db.WithContext(ctx).First(bare, media.ID).Error
	require.NoError(t, err)
	require.Nil(t, bare.Artists)

	// Update такой записи не должен терять артиста.
	bare.Width = 1920
	bare.Height = 1080
	require.NoError(t, store.Update(ctx, bare))

	after, err := store.FindByID(ctx, media.ID)
	require.NoError(t, err)
	assert.Len(t, after.Artists, 1, "артист потерян при Update без Preload")
	assert.Equal(t, "Someone", after.Artists[0].Name)
}
