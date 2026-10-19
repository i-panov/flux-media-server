package services

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)

// writeTempFile создаёт временный файл с указанным содержимым.
func writeTempFile(t *testing.T, name string, content []byte) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	require.NoError(t, os.WriteFile(path, content, 0o600))
	return path
}

// Бэкфилл не должен ни зависать, ни падать на записях, которые ffprobe
// не осилил: отсутствующий файл и мусорный контейнер оставляют запись с
// нулевыми размерами, и она просто переспрашивается при следующем старте.
func TestBackfillVideoDimensions_SkipsUnreadable(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	store := repository.NewMediaRepository(db)
	ctx := context.Background()

	// Файла нет на диске.
	missing := &models.Media{
		Title: "Missing", Type: models.MediaTypeVideo,
		FilePath: filepath.Join(t.TempDir(), "missing.mkv"),
	}
	// Файл есть, но это не видео — ffprobe вернёт ошибку.
	junk := &models.Media{
		Title: "Junk", Type: models.MediaTypeVideo,
		FilePath: writeTempFile(t, "junk.mkv", []byte("not a video at all")),
	}
	for _, m := range []*models.Media{missing, junk} {
		require.NoError(t, store.Create(ctx, m))
	}

	assert.Zero(t, BackfillVideoDimensions(ctx, store))

	for _, id := range []uint{missing.ID, junk.ID} {
		got, err := store.FindByID(ctx, id)
		require.NoError(t, err)
		assert.Zero(t, got.Width)
		assert.Zero(t, got.Height)
	}
}

// Полный батч нечитаемых записей: проход обязан завершиться, а не
// крутить выборку по кругу до общего таймаута.
func TestBackfillVideoDimensions_TerminatesOnUnfillableBatch(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	store := repository.NewMediaRepository(db)
	ctx := context.Background()

	for i := 0; i < dimensionsBackfillBatch+5; i++ {
		require.NoError(t, store.Create(ctx, &models.Media{
			Title: "Junk", Type: models.MediaTypeVideo,
			FilePath: writeTempFile(t, "junk.mkv", []byte("garbage")),
		}))
	}

	assert.Zero(t, BackfillVideoDimensions(ctx, store))
}

// Запись, которой размеры уже есть, в проход не попадает — даже если
// лежит рядом с нечитаемыми.
func TestBackfillVideoDimensions_IgnoresFilled(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	store := repository.NewMediaRepository(db)
	ctx := context.Background()

	filled := &models.Media{
		Title: "Filled", Type: models.MediaTypeVideo,
		FilePath: writeTempFile(t, "filled.mkv", []byte("garbage")),
		Width:    640, Height: 480,
	}
	require.NoError(t, store.Create(ctx, filled))

	assert.Zero(t, BackfillVideoDimensions(ctx, store))

	got, err := store.FindByID(ctx, filled.ID)
	require.NoError(t, err)
	assert.Equal(t, 640, got.Width)
	assert.Equal(t, 480, got.Height)
}

// Отменённый контекст останавливает проход без паники.
func TestBackfillVideoDimensions_RespectsCancel(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	store := repository.NewMediaRepository(db)
	base := context.Background()
	require.NoError(t, store.Create(base, &models.Media{
		Title: "Junk", Type: models.MediaTypeVideo,
		FilePath: writeTempFile(t, "junk.mkv", []byte("garbage")),
	}))

	ctx, cancel := context.WithCancel(base)
	cancel()
	assert.Zero(t, BackfillVideoDimensions(ctx, store))
}
