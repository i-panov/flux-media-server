package repository

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/require"
	"gorm.io/gorm"

	"flux/internal/models"
)

func catalogVideo(t *testing.T, db *gorm.DB, path string) *models.Media {
	t.Helper()
	media := models.Media{Title: path, Type: models.MediaTypeVideo, FilePath: path}
	require.NoError(t, db.Create(&media).Error)
	return &media
}

func TestWorkStoreSeriesAndEpisodes(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewWorkRepository(db)
	ctx := context.Background()

	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, store.Create(ctx, &work))
	got, err := store.Get(ctx, work.ID)
	require.NoError(t, err)
	require.Len(t, got.Seasons, 1)
	require.Equal(t, 1, got.Seasons[0].SeasonNumber)

	season2, err := store.CreateSeason(ctx, work.ID, 2, "Season 2")
	require.NoError(t, err)
	require.Equal(t, 1, season2.Position)

	video := catalogVideo(t, db, "/episode.mp4")
	_, err = store.AddEpisode(ctx, got.Seasons[0].ID, video.ID, nil)
	require.NoError(t, err)
	var stored models.Media
	require.NoError(t, db.First(&stored, video.ID).Error)
	require.NotNil(t, stored.VideoKind)
	require.Equal(t, models.VideoKindEpisode, *stored.VideoKind)

	// Один эпизод — ровно один сезон.
	_, err = store.AddEpisode(ctx, season2.ID, video.ID, nil)
	require.ErrorIs(t, err, ErrEpisodeAlreadyInSeason)

	// Второй сезон удалить можно; последний — нельзя.
	require.NoError(t, store.DeleteSeason(ctx, season2.ID))
	require.ErrorIs(t, store.DeleteSeason(ctx, got.Seasons[0].ID), ErrLastSeason)
}

func TestWorkStoreFilmSeries(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewWorkRepository(db)
	ctx := context.Background()
	work := models.Work{Kind: models.WorkKindFilmSeries, Title: "Films"}
	require.NoError(t, store.Create(ctx, &work))
	got, err := store.Get(ctx, work.ID)
	require.NoError(t, err)
	require.Empty(t, got.Seasons)

	first := catalogVideo(t, db, "/f1.mp4")
	second := catalogVideo(t, db, "/f2.mp4")
	_, err = store.AddFilm(ctx, work.ID, first.ID)
	require.NoError(t, err)
	_, err = store.AddFilm(ctx, work.ID, second.ID)
	require.NoError(t, err)
	_, err = store.AddFilm(ctx, work.ID, first.ID)
	require.ErrorIs(t, err, ErrDuplicateWorkItem)

	got, err = store.Get(ctx, work.ID)
	require.NoError(t, err)
	require.Len(t, got.Items, 2)
}

func TestWorkStoreRequiresSeasonAndRejectsLastDelete(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewWorkRepository(db)
	ctx := context.Background()
	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, store.Create(ctx, &work))
	got, err := store.Get(ctx, work.ID)
	require.NoError(t, err)
	require.Len(t, got.Seasons, 1)
	require.ErrorIs(t, store.DeleteSeason(ctx, got.Seasons[0].ID), ErrLastSeason)
	_, err = store.CreateSeason(ctx, work.ID, 1, "")
	require.ErrorIs(t, err, ErrDuplicateSeason)
}

func TestWorkStoreReorder(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewWorkRepository(db)
	ctx := context.Background()
	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, store.Create(ctx, &work))
	season1, err := store.CreateSeason(ctx, work.ID, 2, "")
	require.NoError(t, err)
	season2, err := store.CreateSeason(ctx, work.ID, 3, "")
	require.NoError(t, err)
	all, err := store.Get(ctx, work.ID)
	require.NoError(t, err)
	require.NoError(t, store.ReorderSeasons(ctx, work.ID, []uint{season2.ID, season1.ID, all.Seasons[0].ID}))
	require.ErrorIs(t, store.ReorderSeasons(ctx, work.ID, []uint{season1.ID}), ErrInvalidOrder)

	videoA := catalogVideo(t, db, "/a.mp4")
	videoB := catalogVideo(t, db, "/b.mp4")
	itemA, err := store.AddEpisode(ctx, season1.ID, videoA.ID, nil)
	require.NoError(t, err)
	itemB, err := store.AddEpisode(ctx, season1.ID, videoB.ID, nil)
	require.NoError(t, err)
	require.NoError(t, store.ReorderSeasonItems(ctx, season1.ID, []uint{itemB.ID, itemA.ID}))
	require.ErrorIs(t, store.ReorderSeasonItems(ctx, season1.ID, []uint{itemA.ID}), ErrInvalidOrder)
}

func TestWorkStoreDeleteKeepsMedia(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewWorkRepository(db)
	ctx := context.Background()
	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, store.Create(ctx, &work))
	got, err := store.Get(ctx, work.ID)
	require.NoError(t, err)
	video := catalogVideo(t, db, "/e.mp4")
	_, err = store.AddEpisode(ctx, got.Seasons[0].ID, video.ID, nil)
	require.NoError(t, err)
	require.NoError(t, store.Delete(ctx, work.ID))
	var mediaCount int64
	require.NoError(t, db.Model(&models.Media{}).Count(&mediaCount).Error)
	require.Equal(t, int64(1), mediaCount)
}

func TestFranchiseStoreMixedEntries(t *testing.T) {
	db := setupCatalogDB(t)
	works := NewWorkRepository(db)
	franchises := NewFranchiseRepository(db)
	ctx := context.Background()

	series := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, works.Create(ctx, &series))
	films := models.Work{Kind: models.WorkKindFilmSeries, Title: "Films"}
	require.NoError(t, works.Create(ctx, &films))
	movie := catalogVideo(t, db, "/movie.mp4")

	franchise := models.Franchise{Name: "Universe"}
	require.NoError(t, franchises.Create(ctx, &franchise))
	movieEntry, err := franchises.AddEntry(ctx, franchise.ID, nil, &movie.ID)
	require.NoError(t, err)
	seriesEntry, err := franchises.AddEntry(ctx, franchise.ID, &series.ID, nil)
	require.NoError(t, err)
	filmsEntry, err := franchises.AddEntry(ctx, franchise.ID, &films.ID, nil)
	require.NoError(t, err)
	require.NoError(t, franchises.ReorderEntries(ctx, franchise.ID, []uint{filmsEntry.ID, movieEntry.ID, seriesEntry.ID}))

	got, err := franchises.Get(ctx, franchise.ID)
	require.NoError(t, err)
	require.Len(t, got.Entries, 3)
	require.Equal(t, filmsEntry.ID, got.Entries[0].ID)
	require.ErrorIs(t, franchises.ReorderEntries(ctx, franchise.ID, []uint{movieEntry.ID}), ErrInvalidOrder)
	_, err = franchises.AddEntry(ctx, franchise.ID, &series.ID, nil)
	require.ErrorIs(t, err, ErrDuplicateFranchiseEntry)
}

func TestFranchiseDeleteKeepsCatalog(t *testing.T) {
	db := setupCatalogDB(t)
	works := NewWorkRepository(db)
	franchises := NewFranchiseRepository(db)
	ctx := context.Background()
	work := models.Work{Kind: models.WorkKindFilmSeries, Title: "Films"}
	require.NoError(t, works.Create(ctx, &work))
	franchise := models.Franchise{Name: "Universe"}
	require.NoError(t, franchises.Create(ctx, &franchise))
	_, err := franchises.AddEntry(ctx, franchise.ID, &work.ID, nil)
	require.NoError(t, err)
	require.NoError(t, franchises.Delete(ctx, franchise.ID))
	var workCount int64
	require.NoError(t, db.Model(&models.Work{}).Count(&workCount).Error)
	require.Equal(t, int64(1), workCount)
	var entryCount int64
	require.NoError(t, db.Model(&models.FranchiseEntry{}).Count(&entryCount).Error)
	require.Zero(t, entryCount)
}

func TestWorkStoreRemoveLastEpisodeMakesMovie(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewWorkRepository(db)
	ctx := context.Background()
	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, store.Create(ctx, &work))
	got, err := store.Get(ctx, work.ID)
	require.NoError(t, err)
	video := catalogVideo(t, db, "/e.mp4")
	_, err = store.AddEpisode(ctx, got.Seasons[0].ID, video.ID, nil)
	require.NoError(t, err)
	require.NoError(t, store.RemoveEpisode(ctx, got.Seasons[0].ID, video.ID))
	var stored models.Media
	require.NoError(t, db.First(&stored, video.ID).Error)
	require.NotNil(t, stored.VideoKind)
	require.Equal(t, models.VideoKindMovie, *stored.VideoKind)
}

func TestWorkStoreNotFound(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewWorkRepository(db)
	_, err := store.Get(context.Background(), 404)
	require.True(t, errors.Is(err, gorm.ErrRecordNotFound))
}

func TestAddFilmAllowsMovieInTwoFilmSeries(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewWorkRepository(db)
	ctx := context.Background()
	first := models.Work{Kind: models.WorkKindFilmSeries, Title: "First"}
	second := models.Work{Kind: models.WorkKindFilmSeries, Title: "Second"}
	require.NoError(t, store.Create(ctx, &first))
	require.NoError(t, store.Create(ctx, &second))
	movie := catalogVideo(t, db, "/crossover.mp4")
	_, err := store.AddFilm(ctx, first.ID, movie.ID)
	require.NoError(t, err)
	_, err = store.AddFilm(ctx, second.ID, movie.ID)
	require.NoError(t, err)
}

func TestDeleteSeasonResetsEpisodeKind(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewWorkRepository(db)
	ctx := context.Background()
	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, store.Create(ctx, &work))
	second, err := store.CreateSeason(ctx, work.ID, 2, "")
	require.NoError(t, err)
	video := catalogVideo(t, db, "/e.mp4")
	_, err = store.AddEpisode(ctx, second.ID, video.ID, nil)
	require.NoError(t, err)
	require.NoError(t, store.DeleteSeason(ctx, second.ID))
	var stored models.Media
	require.NoError(t, db.First(&stored, video.ID).Error)
	require.NotNil(t, stored.VideoKind)
	require.Equal(t, models.VideoKindMovie, *stored.VideoKind)
}

func TestDeleteWorkResetsEpisodeKind(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewWorkRepository(db)
	ctx := context.Background()
	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, store.Create(ctx, &work))
	got, err := store.Get(ctx, work.ID)
	require.NoError(t, err)
	video := catalogVideo(t, db, "/e.mp4")
	_, err = store.AddEpisode(ctx, got.Seasons[0].ID, video.ID, nil)
	require.NoError(t, err)
	require.NoError(t, store.Delete(ctx, work.ID))
	var stored models.Media
	require.NoError(t, db.First(&stored, video.ID).Error)
	require.NotNil(t, stored.VideoKind)
	require.Equal(t, models.VideoKindMovie, *stored.VideoKind)
}

func TestAddEpisodeRejectedWhenMovieInFranchise(t *testing.T) {
	db := setupCatalogDB(t)
	works := NewWorkRepository(db)
	franchises := NewFranchiseRepository(db)
	ctx := context.Background()
	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, works.Create(ctx, &work))
	got, err := works.Get(ctx, work.ID)
	require.NoError(t, err)
	movie := catalogVideo(t, db, "/movie.mp4")
	franchise := models.Franchise{Name: "Universe"}
	require.NoError(t, franchises.Create(ctx, &franchise))
	_, err = franchises.AddEntry(ctx, franchise.ID, nil, &movie.ID)
	require.NoError(t, err)
	_, err = works.AddEpisode(ctx, got.Seasons[0].ID, movie.ID, nil)
	require.ErrorIs(t, err, ErrEpisodeInFranchise)
}

func TestGetAttachesMediaToEpisodes(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewWorkRepository(db)
	ctx := context.Background()
	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, store.Create(ctx, &work))
	got, err := store.Get(ctx, work.ID)
	require.NoError(t, err)
	video := catalogVideo(t, db, "/e.mp4")
	_, err = store.AddEpisode(ctx, got.Seasons[0].ID, video.ID, nil)
	require.NoError(t, err)
	got, err = store.Get(ctx, work.ID)
	require.NoError(t, err)
	require.Len(t, got.Seasons[0].Items, 1)
	require.NotNil(t, got.Seasons[0].Items[0].Media)
	require.Equal(t, video.ID, got.Seasons[0].Items[0].Media.ID)
}

func TestReorderRejectsMissingParent(t *testing.T) {
	db := setupCatalogDB(t)
	works := NewWorkRepository(db)
	franchises := NewFranchiseRepository(db)
	ctx := context.Background()
	require.ErrorIs(t, works.ReorderSeasons(ctx, 404, []uint{}), gorm.ErrRecordNotFound)
	require.ErrorIs(t, works.ReorderSeasonItems(ctx, 404, []uint{}), gorm.ErrRecordNotFound)
	require.ErrorIs(t, works.ReorderWorkItems(ctx, 404, []uint{}), gorm.ErrRecordNotFound)
	require.ErrorIs(t, franchises.ReorderEntries(ctx, 404, []uint{}), gorm.ErrRecordNotFound)

	series := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, works.Create(ctx, &series))
	require.ErrorIs(t, works.ReorderWorkItems(ctx, series.ID, []uint{}), ErrNotFilmSeries)
	films := models.Work{Kind: models.WorkKindFilmSeries, Title: "Films"}
	require.NoError(t, works.Create(ctx, &films))
	require.ErrorIs(t, works.ReorderSeasons(ctx, films.ID, []uint{}), ErrNotSeries)
}

func TestReorderPositionsPersist(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewWorkRepository(db)
	ctx := context.Background()
	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, store.Create(ctx, &work))
	got, err := store.Get(ctx, work.ID)
	require.NoError(t, err)
	second, err := store.CreateSeason(ctx, work.ID, 2, "")
	require.NoError(t, err)
	require.NoError(t, store.ReorderSeasons(ctx, work.ID, []uint{second.ID, got.Seasons[0].ID}))
	got, err = store.Get(ctx, work.ID)
	require.NoError(t, err)
	require.Equal(t, second.ID, got.Seasons[0].ID)
	require.Equal(t, 0, got.Seasons[0].Position)
}

func TestAutoMigrateDoesNotRebuildCatalog(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewWorkRepository(db)
	ctx := context.Background()
	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, store.Create(ctx, &work))
	got, err := store.Get(ctx, work.ID)
	require.NoError(t, err)
	episode := catalogVideo(t, db, "/e.mp4")
	_, err = store.AddEpisode(ctx, got.Seasons[0].ID, episode.ID, nil)
	require.NoError(t, err)
	filmWork := models.Work{Kind: models.WorkKindFilmSeries, Title: "Films"}
	require.NoError(t, store.Create(ctx, &filmWork))
	film := catalogVideo(t, db, "/f.mp4")
	_, err = store.AddFilm(ctx, filmWork.ID, film.ID)
	require.NoError(t, err)

	roots := func(table string) int {
		var row struct{ Rootpage int }
		require.NoError(t, db.Raw("SELECT rootpage FROM sqlite_master WHERE type='table' AND name=?", table).Scan(&row).Error)
		return row.Rootpage
	}
	beforeItems, beforeSeasons := roots("work_items"), roots("seasons")
	require.NoError(t, AutoMigrate(db))
	require.Equal(t, beforeItems, roots("work_items"), "AutoMigrate must not rebuild work_items")
	require.Equal(t, beforeSeasons, roots("seasons"), "AutoMigrate must not rebuild seasons")
	var count int64
	require.NoError(t, db.Model(&models.WorkItem{}).Count(&count).Error)
	require.Equal(t, int64(2), count)
}

func TestLegacyCatalogFKDetected(t *testing.T) {
	require.Equal(t, "fk_works_seasons", legacyCatalogFK("CONSTRAINT fk_works_seasons FOREIGN KEY ..."))
	require.Equal(t, "fk_seasons_items", legacyCatalogFK("CONSTRAINT fk_seasons_items FOREIGN KEY ..."))
	require.Equal(t, "fk_works_items", legacyCatalogFK("CONSTRAINT fk_works_items FOREIGN KEY ..."))
	require.Empty(t, legacyCatalogFK("CONSTRAINT fk_seasons_work FOREIGN KEY ..."))
	require.NoError(t, guardLegacyCatalogSchema(setupCatalogDB(t)))
}

func TestFranchiseAddEntryRequiresExactlyOneTarget(t *testing.T) {
	db := setupCatalogDB(t)
	franchises := NewFranchiseRepository(db)
	ctx := context.Background()
	franchise := models.Franchise{Name: "Universe"}
	require.NoError(t, franchises.Create(ctx, &franchise))
	_, err := franchises.AddEntry(ctx, franchise.ID, nil, nil)
	require.ErrorIs(t, err, ErrFranchiseEntryTarget)
}

func TestFranchiseAndFilmSeriesRejectCrossMembership(t *testing.T) {
	db := setupCatalogDB(t)
	works := NewWorkRepository(db)
	franchises := NewFranchiseRepository(db)
	ctx := context.Background()

	filmSeries := models.Work{Kind: models.WorkKindFilmSeries, Title: "Films"}
	require.NoError(t, works.Create(ctx, &filmSeries))
	first := catalogVideo(t, db, "/f1.mp4")
	_, err := works.AddFilm(ctx, filmSeries.ID, first.ID)
	require.NoError(t, err)
	franchise := models.Franchise{Name: "Universe"}
	require.NoError(t, franchises.Create(ctx, &franchise))
	_, err = franchises.AddEntry(ctx, franchise.ID, nil, &first.ID)
	require.ErrorIs(t, err, ErrFranchiseMediaInWork)

	second := catalogVideo(t, db, "/f2.mp4")
	_, err = franchises.AddEntry(ctx, franchise.ID, nil, &second.ID)
	require.NoError(t, err)
	_, err = works.AddFilm(ctx, filmSeries.ID, second.ID)
	require.ErrorIs(t, err, ErrMovieInFranchise)
}

func TestLegacyCatalogGuardRejectsOldSchema(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, db.Exec(`CREATE TABLE works (id INTEGER PRIMARY KEY)`).Error)
	require.NoError(t, db.Exec(`INSERT INTO works (id) VALUES (1)`).Error)
	require.NoError(t, db.Exec(`CREATE TABLE seasons (
		id INTEGER PRIMARY KEY, work_id INTEGER,
		CONSTRAINT fk_works_seasons FOREIGN KEY (work_id) REFERENCES works(id))`).Error)
	require.NoError(t, db.Exec(`CREATE TABLE work_items (
		id INTEGER PRIMARY KEY, season_id INTEGER,
		CONSTRAINT fk_seasons_items FOREIGN KEY (season_id) REFERENCES seasons(id))`).Error)
	require.NoError(t, db.Exec(`INSERT INTO seasons (id, work_id) VALUES (1, 1)`).Error)
	require.NoError(t, db.Exec(`INSERT INTO work_items (id, season_id) VALUES (1, 1)`).Error)

	require.Error(t, guardLegacyCatalogSchema(db))
	require.Error(t, RunMigrations(db))
	var seasons, items int64
	require.NoError(t, db.Table("seasons").Count(&seasons).Error)
	require.NoError(t, db.Table("work_items").Count(&items).Error)
	require.Equal(t, int64(1), seasons)
	require.Equal(t, int64(1), items)
}

func TestMediaListHidesEpisodesByDefault(t *testing.T) {
	db := setupCatalogDB(t)
	movie := catalogVideo(t, db, "/movie.mp4")
	kind := models.VideoKindEpisode
	episode := models.Media{Title: "Episode", Type: models.MediaTypeVideo, FilePath: "/ep.mp4", VideoKind: &kind}
	require.NoError(t, db.Create(&episode).Error)
	store := NewMediaRepository(db)
	ctx := context.Background()

	rows, total, err := store.FindAll(ctx, MediaFilters{Type: models.MediaTypeVideo}, 0, 0)
	require.NoError(t, err)
	require.Equal(t, int64(1), total)
	require.Len(t, rows, 1)
	require.Equal(t, movie.ID, rows[0].ID)

	rows, total, err = store.FindAll(ctx, MediaFilters{Type: models.MediaTypeVideo, IncludeEpisodes: true}, 0, 0)
	require.NoError(t, err)
	require.Equal(t, int64(2), total)
	require.Len(t, rows, 2)
}

func TestGetMediaContextEpisodeAndFranchise(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewWorkRepository(db)
	franchises := NewFranchiseRepository(db)
	ctx := context.Background()

	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, store.Create(ctx, &work))
	got, err := store.Get(ctx, work.ID)
	require.NoError(t, err)
	episode := catalogVideo(t, db, "/episode.mp4")
	number := 3
	_, err = store.AddEpisode(ctx, got.Seasons[0].ID, episode.ID, &number)
	require.NoError(t, err)

	franchise := models.Franchise{Name: "Universe"}
	require.NoError(t, franchises.Create(ctx, &franchise))
	_, err = franchises.AddEntry(ctx, franchise.ID, &work.ID, nil)
	require.NoError(t, err)

	context, err := store.GetMediaContext(ctx, episode.ID)
	require.NoError(t, err)
	require.NotNil(t, context.WorkID)
	require.Equal(t, work.ID, *context.WorkID)
	require.Equal(t, "Show", context.WorkTitle)
	require.Equal(t, models.WorkKindSeries, context.WorkKind)
	require.NotNil(t, context.SeasonID)
	require.Equal(t, 1, context.SeasonNumber)
	require.NotNil(t, context.EpisodeNumber)
	require.Equal(t, number, *context.EpisodeNumber)
	require.Len(t, context.Franchises, 1)
	require.Equal(t, "Universe", context.Franchises[0].Name)
}
