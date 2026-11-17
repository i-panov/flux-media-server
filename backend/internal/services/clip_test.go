package services

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)

func TestClipServiceValidation(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	media := models.Media{Title: "Фильм", Type: models.MediaTypeVideo, FilePath: "/tmp/film.mp4", Duration: 100}
	require.NoError(t, db.Create(&media).Error)
	image := models.Media{Title: "Мем", Type: models.MediaTypeImage, FilePath: "/tmp/meme.png"}
	require.NoError(t, db.Create(&image).Error)

	service := NewClipService(
		repository.NewClipRepository(db), repository.NewMediaRepository(db),
		filepath.Join(t.TempDir(), "originals"), nil, nil,
	)
	_, err = service.Start(context.Background(), media.ID, -1, 5, "")
	require.Error(t, err)
	_, err = service.Start(context.Background(), media.ID, 10, 10, "")
	require.Error(t, err)
	_, err = service.Start(context.Background(), media.ID, 10, 10.2, "")
	require.Error(t, err)
	_, err = service.Start(context.Background(), media.ID, 10, 200, "")
	require.Error(t, err)
	_, err = service.Start(context.Background(), image.ID, 0, 5, "")
	require.Error(t, err)
	_, err = service.Start(context.Background(), 99999, 0, 5, "")
	require.Error(t, err)
}

func TestClipSourceDoesNotShadowExtractedAudio(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	source := models.Media{Title: "Источник", Type: models.MediaTypeVideo, FilePath: "/tmp/src.mp4", Duration: 60}
	require.NoError(t, db.Create(&source).Error)
	// Фрагмент видео ссылается на источник только через clip-колонку.
	clip := models.Media{Title: "Фрагмент", Type: models.MediaTypeVideo, FilePath: "/tmp/clip.mp4"}
	require.NoError(t, db.Create(&clip).Error)
	repo := repository.NewMediaRepository(db)
	require.NoError(t, repo.SetClipSourceMediaID(context.Background(), clip.ID, source.ID))
	// Извлечённого аудио ещё нет — поиск обязан вернуть not found.
	_, err = repo.FindBySourceMediaID(context.Background(), source.ID)
	require.Error(t, err)
	extracted := models.Media{Title: "Трек", Type: models.MediaTypeAudio, FilePath: "/tmp/src.m4a"}
	require.NoError(t, db.Create(&extracted).Error)
	require.NoError(t, db.Model(&extracted).Update("source_media_id", source.ID).Error)
	found, err := repo.FindBySourceMediaID(context.Background(), source.ID)
	require.NoError(t, err)
	require.Equal(t, extracted.ID, found.ID)
}
