package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

func TestTagStoreMediaWorkFranchise(t *testing.T) {
	db := setupCatalogDB(t)
	tags := NewTagRepository(db)
	ctx := context.Background()

	var format models.Tag
	require.NoError(t, db.Where("tag_group = ? AND slug = ?", models.TagGroupFormat, "film").First(&format).Error)
	genre := models.Tag{Group: models.TagGroupGenre, Slug: "comedy", Name: "Комедия"}
	drama := models.Tag{Group: models.TagGroupGenre, Slug: "drama", Name: "Драма"}
	require.NoError(t, tags.Create(ctx, &genre))
	require.NoError(t, tags.Create(ctx, &drama))
	require.ErrorIs(t, tags.Create(ctx, &models.Tag{Group: models.TagGroupFormat, Slug: "film", Name: "Dup"}), ErrTagSlugTaken)

	media := catalogVideo(t, db, "/film.mp4")
	require.NoError(t, tags.SetMediaTags(ctx, media.ID, []uint{format.ID, genre.ID, drama.ID}))
	got, err := tags.MediaTags(ctx, media.ID)
	require.NoError(t, err)
	require.Len(t, got, 3)

	var secondFormat models.Tag
	require.NoError(t, db.Where("tag_group = ? AND slug = ?", models.TagGroupFormat, "clip").First(&secondFormat).Error)
	require.ErrorIs(t, tags.SetMediaTags(ctx, media.ID, []uint{format.ID, secondFormat.ID}), ErrTooManyFormatTags)

	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, NewWorkRepository(db).Create(ctx, &work))
	require.NoError(t, tags.SetWorkTags(ctx, work.ID, []uint{genre.ID}))
	require.ErrorIs(t, tags.SetWorkTags(ctx, work.ID, []uint{format.ID}), ErrFormatOnWork)
	workTags, err := tags.WorkTags(ctx, work.ID)
	require.NoError(t, err)
	require.Len(t, workTags, 1)

	franchise := models.Franchise{Name: "Universe"}
	require.NoError(t, NewFranchiseRepository(db).Create(ctx, &franchise))
	require.NoError(t, tags.SetFranchiseTags(ctx, franchise.ID, []uint{drama.ID}))
	franchiseTags, err := tags.FranchiseTags(ctx, franchise.ID)
	require.NoError(t, err)
	require.Len(t, franchiseTags, 1)

	image := models.Media{Title: "Meme", Type: models.MediaTypeImage, FilePath: "/meme.png"}
	require.NoError(t, db.Create(&image).Error)
	require.ErrorIs(t, tags.SetMediaTags(ctx, image.ID, []uint{format.ID}), ErrTagsForImage)

	// FK cascade: удаление media уносит связи, тег остаётся.
	require.NoError(t, db.Unscoped().Delete(&models.Media{}, media.ID).Error)
	var count int64
	require.NoError(t, db.Model(&models.MediaTag{}).Where("media_id = ?", media.ID).Count(&count).Error)
	require.Zero(t, count)
	require.NoError(t, tags.Delete(ctx, format.ID))
	require.NoError(t, db.Model(&models.WorkTag{}).Count(&count).Error)
}

func TestMediaFormatFilter(t *testing.T) {
	db := setupCatalogDB(t)
	tags := NewTagRepository(db)
	ctx := context.Background()
	var format models.Tag
	require.NoError(t, db.Where("tag_group = ? AND slug = ?", models.TagGroupFormat, "film").First(&format).Error)
	film := catalogVideo(t, db, "/film.mp4")
	clip := catalogVideo(t, db, "/clip.mp4")
	require.NoError(t, tags.SetMediaTags(ctx, film.ID, []uint{format.ID}))

	media := NewMediaRepository(db)
	rows, total, err := media.FindAll(ctx, MediaFilters{Type: models.MediaTypeVideo, Format: "film"}, 20, 0)
	require.NoError(t, err)
	require.Equal(t, int64(1), total)
	require.Len(t, rows, 1)
	require.Equal(t, film.ID, rows[0].ID)

	rows, total, err = media.FindAll(ctx, MediaFilters{Type: models.MediaTypeVideo, ExcludeFormat: "film"}, 20, 0)
	require.NoError(t, err)
	require.Equal(t, int64(1), total)
	require.Len(t, rows, 1)
	require.Equal(t, clip.ID, rows[0].ID)
}

func TestSystemFormatTagsSeeded(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	var tags []models.Tag
	require.NoError(t, db.Where("tag_group = ?", models.TagGroupFormat).Order("slug").Find(&tags).Error)
	require.Len(t, tags, 3)
	require.Equal(t, "clip", tags[0].Slug)
	require.Equal(t, "film", tags[1].Slug)
	require.Equal(t, "podcast", tags[2].Slug)
}
