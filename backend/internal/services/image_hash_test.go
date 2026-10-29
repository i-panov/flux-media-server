package services_test

import (
	"context"
	"image"
	"image/color"
	"image/jpeg"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

func TestIsSimilarImageThreshold(t *testing.T) {
	var base int64 = 0x0F0F_0F0F_0F0F_0F0F
	// Ровно 8 бит различия — ещё похоже, 9 — уже нет.
	eightBits := base ^ 0xFF
	nineBits := base ^ 0x1FF

	assert.True(t, services.IsSimilarImage(base, eightBits))
	assert.False(t, services.IsSimilarImage(base, nineBits))
	// Нулевой хэш означает «не посчитан» и не совпадает ни с чем.
	assert.False(t, services.IsSimilarImage(0, base))
	assert.False(t, services.IsSimilarImage(base, 0))
}

func TestImagePHash(t *testing.T) {
	dir := t.TempDir()
	first := filepath.Join(dir, "first.jpg")
	second := filepath.Join(dir, "second.jpg")
	writeGradientJPEG(t, first, false)
	writeGradientJPEG(t, second, true)

	hashA, err := services.ImagePHash(first)
	require.NoError(t, err)
	assert.NotZero(t, hashA)

	hashA2, err := services.ImagePHash(first)
	require.NoError(t, err)
	assert.Equal(t, hashA, hashA2)

	hashB, err := services.ImagePHash(second)
	require.NoError(t, err)
	assert.NotEqual(t, hashA, hashB)
}

func TestFindSimilarImageIgnoresOtherTypesAndTrash(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	repo := repository.NewMediaRepository(db)
	ctx := context.Background()

	const base int64 = 0x0F0F_0F0F_0F0F_0F0F

	self := createPHashMedia(t, repo, models.MediaTypeImage, base)
	similar := createPHashMedia(t, repo, models.MediaTypeImage, base^0x3)
	createPHashMedia(t, repo, models.MediaTypeVideo, base)
	trashed := createPHashMedia(t, repo, models.MediaTypeImage, base)
	require.NoError(t, repo.Delete(ctx, trashed.ID))

	found, err := services.FindSimilarImage(ctx, repo, base, self.ID)
	require.NoError(t, err)
	require.NotNil(t, found)
	assert.Equal(t, similar.ID, found.ID)

	// Своя запись исключается, даже если хэш совпадает.
	found, err = services.FindSimilarImage(ctx, repo, base, 0)
	require.NoError(t, err)
	require.NotNil(t, found)
	assert.Equal(t, self.ID, found.ID)

	// Нулевой хэш не ищется вовсе.
	found, err = services.FindSimilarImage(ctx, nil, 0, 0)
	require.NoError(t, err)
	assert.Nil(t, found)
}

func createPHashMedia(
	t *testing.T,
	repo repository.MediaRepository,
	mediaType models.MediaType,
	phash int64,
) *models.Media {
	t.Helper()
	media := &models.Media{
		Title:    "item",
		Type:     mediaType,
		FilePath: filepath.Join(t.TempDir(), "file"),
	}
	require.NoError(t, repo.Create(context.Background(), media))
	require.NoError(t, repo.SetPHash(context.Background(), media.ID, phash))
	return media
}

func writeGradientJPEG(t *testing.T, path string, invert bool) {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 64, 64))
	for y := range 64 {
		for x := range 64 {
			if invert {
				// Контрастная шахматка: pHash гарантированно отличается
				// от плавного градиента.
				if (x/8+y/8)%2 == 0 {
					img.Set(x, y, color.RGBA{R: 255, G: 255, B: 255, A: 255})
				} else {
					img.Set(x, y, color.RGBA{R: 0, G: 0, B: 0, A: 255})
				}
				continue
			}
			img.Set(x, y, color.RGBA{R: uint8(x * 4), G: uint8(255 - y*4), B: 32, A: 255})
		}
	}
	file, err := os.Create(path)
	require.NoError(t, err)
	require.NoError(t, jpeg.Encode(file, img, nil))
	require.NoError(t, file.Close())
}
