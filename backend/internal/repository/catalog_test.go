package repository

import (
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"gorm.io/gorm"

	"flux/internal/models"
)

func setupCatalogDB(t *testing.T) *gormDB {
	t.Helper()
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	return db
}

// gormDB is an alias to keep the helper signature short without importing
// gorm in every test file.
type gormDB = gorm.DB

func TestCatalogSchemaTables(t *testing.T) {
	db := setupCatalogDB(t)
	for _, table := range []string{"works", "seasons", "work_items", "franchises", "franchise_entries"} {
		require.True(t, db.Migrator().HasTable(table), "missing table %s", table)
	}
	require.True(t, db.Migrator().HasColumn(&models.Media{}, "video_kind"))
}

func dropVideoKindForV1(t *testing.T, db *gorm.DB) {
	t.Helper()
	require.NoError(t, db.Exec("DROP TRIGGER IF EXISTS media_video_kind_insert").Error)
	require.NoError(t, db.Exec("DROP TRIGGER IF EXISTS media_video_kind_update").Error)
	require.NoError(t, db.Exec("DROP INDEX IF EXISTS idx_media_video_kind").Error)
	require.NoError(t, db.Exec("ALTER TABLE media DROP COLUMN video_kind").Error)
}

func TestMigrationV2PreservesChildren(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	user := models.User{Email: "v1@example.com"}
	require.NoError(t, db.Create(&user).Error)
	video := models.Media{Title: "movie", Type: models.MediaTypeVideo, FilePath: "/v.mp4"}
	audio := models.Media{Title: "track", Type: models.MediaTypeAudio, FilePath: "/a.mp3"}
	require.NoError(t, db.Create(&video).Error)
	require.NoError(t, db.Create(&audio).Error)

	collection := models.Collection{UserID: user.ID, Name: "v1", Type: models.MediaTypeVideo}
	require.NoError(t, db.Create(&collection).Error)
	artist := models.Artist{Name: "Artist", NameNorm: "artist"}
	require.NoError(t, db.Create(&artist).Error)

	require.NoError(t, db.Create(&models.Favorite{UserID: user.ID, MediaID: &video.ID}).Error)
	require.NoError(t, db.Create(&models.WatchProgress{UserID: user.ID, MediaID: video.ID, Position: 10, Duration: 100}).Error)
	require.NoError(t, db.Create(&models.CollectionItem{CollectionID: collection.ID, MediaID: video.ID}).Error)
	require.NoError(t, db.Create(&models.Lyrics{MediaID: video.ID, LyricsText: "text"}).Error)
	require.NoError(t, db.Create(&models.Subtitle{MediaID: video.ID, Lang: "en", Path: "/s.vtt"}).Error)
	require.NoError(t, db.Create(&models.MediaArtist{MediaID: video.ID, ArtistID: artist.ID}).Error)

	// Имитируем настоящую v1-схему: колонки и триггеров ещё нет.
	dropVideoKindForV1(t, db)
	require.NoError(t, RunMigrations(db))
	require.NoError(t, AutoMigrate(db))

	for table, want := range map[string]int64{
		"media": 2, "favorites": 1, "watch_progresses": 1,
		"collection_items": 1, "lyrics": 1, "subtitles": 1, "media_artists": 1,
	} {
		var got int64
		require.NoError(t, db.Table(table).Count(&got).Error, table)
		require.Equal(t, want, got, table)
	}
	var gotVideo models.Media
	require.NoError(t, db.First(&gotVideo, video.ID).Error)
	require.NotNil(t, gotVideo.VideoKind)
	require.Equal(t, models.VideoKindMovie, *gotVideo.VideoKind)
	var gotAudio models.Media
	require.NoError(t, db.First(&gotAudio, audio.ID).Error)
	require.Nil(t, gotAudio.VideoKind)
	var versions int64
	require.NoError(t, db.Model(&models.SchemaMigration{}).Count(&versions).Error)
	require.Equal(t, int64(3), versions)
}

func TestMigrationV2RunsBeforeAutoMigrate(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	video := models.Media{Title: "old video", Type: models.MediaTypeVideo, FilePath: "/old.mp4"}
	require.NoError(t, db.Create(&video).Error)
	dropVideoKindForV1(t, db)

	require.NoError(t, RunMigrations(db))
	require.NoError(t, AutoMigrate(db))
	require.NoError(t, RunMigrations(db))

	var got models.Media
	require.NoError(t, db.First(&got, video.ID).Error)
	require.NotNil(t, got.VideoKind)
	require.Equal(t, models.VideoKindMovie, *got.VideoKind)
	var versions int64
	require.NoError(t, db.Model(&models.SchemaMigration{}).Count(&versions).Error)
	require.Equal(t, int64(3), versions)
}

func TestWorkItemRequiresExactlyOneTarget(t *testing.T) {
	db := setupCatalogDB(t)
	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, db.Create(&work).Error)
	season := models.Season{WorkID: work.ID, SeasonNumber: 1, Title: "Season 1"}
	require.NoError(t, db.Create(&season).Error)
	media := models.Media{Title: "Episode", Type: models.MediaTypeVideo, FilePath: "/e.mp4"}
	require.NoError(t, db.Create(&media).Error)

	both := models.WorkItem{WorkID: &work.ID, SeasonID: &season.ID, MediaID: media.ID}
	require.Error(t, db.Create(&both).Error)
	neither := models.WorkItem{MediaID: media.ID}
	require.Error(t, db.Create(&neither).Error)
}

func TestWorkItemPartialUnique(t *testing.T) {
	db := setupCatalogDB(t)
	work := models.Work{Kind: models.WorkKindFilmSeries, Title: "Films"}
	require.NoError(t, db.Create(&work).Error)
	media := models.Media{Title: "Film", Type: models.MediaTypeVideo, FilePath: "/f.mp4"}
	require.NoError(t, db.Create(&media).Error)
	first := models.WorkItem{WorkID: &work.ID, MediaID: media.ID, Position: 0}
	require.NoError(t, db.Create(&first).Error)
	second := models.WorkItem{WorkID: &work.ID, MediaID: media.ID, Position: 1}
	require.Error(t, db.Create(&second).Error)
}

func TestFranchiseEntryRequiresExactlyOneTarget(t *testing.T) {
	db := setupCatalogDB(t)
	franchise := models.Franchise{Name: "Universe"}
	require.NoError(t, db.Create(&franchise).Error)
	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, db.Create(&work).Error)
	media := models.Media{Title: "Film", Type: models.MediaTypeVideo, FilePath: "/f.mp4"}
	require.NoError(t, db.Create(&media).Error)

	both := models.FranchiseEntry{FranchiseID: franchise.ID, WorkID: &work.ID, MediaID: &media.ID}
	require.Error(t, db.Create(&both).Error)
	neither := models.FranchiseEntry{FranchiseID: franchise.ID}
	require.Error(t, db.Create(&neither).Error)
}

func TestDeleteWorkKeepsMediaAndCascadesCatalog(t *testing.T) {
	db := setupCatalogDB(t)
	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, db.Create(&work).Error)
	season := models.Season{WorkID: work.ID, SeasonNumber: 1, Title: "Season 1"}
	require.NoError(t, db.Create(&season).Error)
	media := models.Media{Title: "Episode", Type: models.MediaTypeVideo, FilePath: "/e.mp4"}
	require.NoError(t, db.Create(&media).Error)
	item := models.WorkItem{SeasonID: &season.ID, MediaID: media.ID}
	require.NoError(t, db.Create(&item).Error)

	require.NoError(t, db.Unscoped().Delete(&models.Work{}, work.ID).Error)
	var seasons, items, mediaCount int64
	require.NoError(t, db.Model(&models.Season{}).Count(&seasons).Error)
	require.NoError(t, db.Model(&models.WorkItem{}).Count(&items).Error)
	require.NoError(t, db.Model(&models.Media{}).Count(&mediaCount).Error)
	require.Zero(t, seasons)
	require.Zero(t, items)
	require.Equal(t, int64(1), mediaCount)
}

func TestWorkItemAllowsMultipleDifferentMedia(t *testing.T) {
	db := setupCatalogDB(t)
	work := models.Work{Kind: models.WorkKindFilmSeries, Title: "Films"}
	require.NoError(t, db.Create(&work).Error)
	for i := 0; i < 2; i++ {
		media := models.Media{Title: "Film", Type: models.MediaTypeVideo, FilePath: fmt.Sprintf("/f%d.mp4", i)}
		require.NoError(t, db.Create(&media).Error)
		require.NoError(t, db.Create(&models.WorkItem{WorkID: &work.ID, MediaID: media.ID, Position: i}).Error)
	}
	var count int64
	require.NoError(t, db.Model(&models.WorkItem{}).Where("work_id = ?", work.ID).Count(&count).Error)
	require.Equal(t, int64(2), count)
}

func TestSeasonNumberUniquePerWork(t *testing.T) {
	db := setupCatalogDB(t)
	first := models.Work{Kind: models.WorkKindSeries, Title: "A"}
	second := models.Work{Kind: models.WorkKindSeries, Title: "B"}
	require.NoError(t, db.Create(&first).Error)
	require.NoError(t, db.Create(&second).Error)
	require.NoError(t, db.Create(&models.Season{WorkID: first.ID, SeasonNumber: 1}).Error)
	require.Error(t, db.Create(&models.Season{WorkID: first.ID, SeasonNumber: 1}).Error)
	require.NoError(t, db.Create(&models.Season{WorkID: second.ID, SeasonNumber: 1}).Error)
}

func TestFranchiseEntryUniqueTarget(t *testing.T) {
	db := setupCatalogDB(t)
	franchise := models.Franchise{Name: "Universe"}
	require.NoError(t, db.Create(&franchise).Error)
	media := models.Media{Title: "Film", Type: models.MediaTypeVideo, FilePath: "/f.mp4"}
	require.NoError(t, db.Create(&media).Error)
	first := models.FranchiseEntry{FranchiseID: franchise.ID, MediaID: &media.ID, Position: 0}
	require.NoError(t, db.Create(&first).Error)
	second := models.FranchiseEntry{FranchiseID: franchise.ID, MediaID: &media.ID, Position: 1}
	require.Error(t, db.Create(&second).Error)
}

func TestWorkKindCheck(t *testing.T) {
	db := setupCatalogDB(t)
	require.Error(t, db.Create(&models.Work{Kind: "bogus", Title: "Bad"}).Error)
}

func TestMediaVideoKindInvariant(t *testing.T) {
	db := setupCatalogDB(t)
	video := models.Media{Title: "Video", Type: models.MediaTypeVideo, FilePath: "/v.mp4"}
	require.NoError(t, db.Create(&video).Error)
	require.NotNil(t, video.VideoKind)
	require.Equal(t, models.VideoKindMovie, *video.VideoKind)

	movie := models.VideoKindMovie
	audio := models.Media{Title: "Audio", Type: models.MediaTypeAudio, FilePath: "/a.mp3", VideoKind: &movie}
	require.NoError(t, db.Create(&audio).Error)
	require.Nil(t, audio.VideoKind, "audio must not keep video_kind")

	bogus := models.VideoKind("bogus")
	bad := models.Media{Title: "Bad", Type: models.MediaTypeVideo, FilePath: "/bad.mp4", VideoKind: &bogus}
	require.Error(t, db.Create(&bad).Error)
}

func TestVideoKindTriggerRejectsInvalidRawValues(t *testing.T) {
	db := setupCatalogDB(t)
	require.Error(t, db.Exec(`INSERT INTO media (title, type, video_kind, file_path)
		VALUES ('bad', 'video', NULL, '/bad.mp4')`).Error)
	require.Error(t, db.Exec(`INSERT INTO media (title, type, video_kind, file_path)
		VALUES ('bad', 'audio', 'movie', '/bad.mp3')`).Error)
	require.NoError(t, db.Exec(`INSERT INTO media (title, type, video_kind, file_path)
		VALUES ('ok', 'video', 'movie', '/ok.mp4')`).Error)
	require.Error(t, db.Exec(`UPDATE media SET video_kind = 'bogus' WHERE file_path = '/ok.mp4'`).Error)
}

func TestHardDeleteMediaCascadesCatalog(t *testing.T) {
	db := setupCatalogDB(t)
	work := models.Work{Kind: models.WorkKindFilmSeries, Title: "Films"}
	require.NoError(t, db.Create(&work).Error)
	franchise := models.Franchise{Name: "Universe"}
	require.NoError(t, db.Create(&franchise).Error)
	media := models.Media{Title: "Film", Type: models.MediaTypeVideo, FilePath: "/f.mp4"}
	require.NoError(t, db.Create(&media).Error)
	item := models.WorkItem{WorkID: &work.ID, MediaID: media.ID}
	require.NoError(t, db.Create(&item).Error)
	entry := models.FranchiseEntry{FranchiseID: franchise.ID, MediaID: &media.ID}
	require.NoError(t, db.Create(&entry).Error)

	require.NoError(t, db.Unscoped().Delete(&models.Media{}, media.ID).Error)
	var items, entries int64
	require.NoError(t, db.Model(&models.WorkItem{}).Count(&items).Error)
	require.NoError(t, db.Model(&models.FranchiseEntry{}).Count(&entries).Error)
	require.Zero(t, items)
	require.Zero(t, entries)
	var works, franchises int64
	require.NoError(t, db.Model(&models.Work{}).Count(&works).Error)
	require.NoError(t, db.Model(&models.Franchise{}).Count(&franchises).Error)
	require.Equal(t, int64(1), works)
	require.Equal(t, int64(1), franchises)
}

func TestDeleteFilmSeriesCascadesItemsButNotMedia(t *testing.T) {
	db := setupCatalogDB(t)
	work := models.Work{Kind: models.WorkKindFilmSeries, Title: "Films"}
	require.NoError(t, db.Create(&work).Error)
	media := models.Media{Title: "Film", Type: models.MediaTypeVideo, FilePath: "/f.mp4"}
	require.NoError(t, db.Create(&media).Error)
	require.NoError(t, db.Create(&models.WorkItem{WorkID: &work.ID, MediaID: media.ID}).Error)
	require.NoError(t, db.Unscoped().Delete(&models.Work{}, work.ID).Error)
	var items, mediaCount int64
	require.NoError(t, db.Model(&models.WorkItem{}).Count(&items).Error)
	require.NoError(t, db.Model(&models.Media{}).Count(&mediaCount).Error)
	require.Zero(t, items)
	require.Equal(t, int64(1), mediaCount)
}

func TestFranchiseEntryWorkUniqueTarget(t *testing.T) {
	db := setupCatalogDB(t)
	franchise := models.Franchise{Name: "Universe"}
	require.NoError(t, db.Create(&franchise).Error)
	work := models.Work{Kind: models.WorkKindSeries, Title: "Show"}
	require.NoError(t, db.Create(&work).Error)
	require.NoError(t, db.Create(&models.FranchiseEntry{FranchiseID: franchise.ID, WorkID: &work.ID}).Error)
	require.Error(t, db.Create(&models.FranchiseEntry{FranchiseID: franchise.ID, WorkID: &work.ID}).Error)
}

func TestMigrationV3RepairsInvalidVideoKind(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	// Убираем только INSERT-триггер, чтобы засеять мусор; UPDATE-триггер
	// остаётся, как на persisted-БД после прежней v2.
	require.NoError(t, db.Exec("DROP TRIGGER IF EXISTS media_video_kind_insert").Error)
	for version := uint(1); version <= 2; version++ {
		require.NoError(t, db.Create(&models.SchemaMigration{
			Version: version, AppliedAt: time.Now().UTC(),
		}).Error)
	}
	require.NoError(t, db.Exec(`INSERT INTO media (title, type, video_kind, file_path)
		VALUES ('audio', 'audio', 'movie', '/a.mp3')`).Error)
	require.NoError(t, db.Exec(`INSERT INTO media (title, type, video_kind, file_path)
		VALUES ('bad video', 'video', 'bogus', '/b.mp4')`).Error)
	require.NoError(t, db.Exec(`INSERT INTO media (title, type, video_kind, file_path)
		VALUES ('null type', NULL, 'movie', '/n.mp4')`).Error)

	require.NoError(t, RunMigrations(db))
	require.NoError(t, AutoMigrate(db))

	var rows []models.Media
	require.NoError(t, db.Order("id").Find(&rows).Error)
	require.Len(t, rows, 3)
	require.Nil(t, rows[0].VideoKind)
	require.NotNil(t, rows[1].VideoKind)
	require.Equal(t, models.VideoKindMovie, *rows[1].VideoKind)
	require.Nil(t, rows[2].VideoKind)

	// После ремонта обычное обновление не должно упираться в триггер.
	require.NoError(t, db.Model(&rows[0]).Update("title", "renamed").Error)
	require.NoError(t, db.Model(&rows[0]).Update("deleted_at", time.Now().UTC()).Error)
	require.NoError(t, db.Model(&rows[0]).Update("view_count", 1).Error)
	require.NoError(t, db.Model(&rows[1]).Update("deleted_at", time.Now().UTC()).Error)
	var versions int64
	require.NoError(t, db.Model(&models.SchemaMigration{}).Count(&versions).Error)
	require.Equal(t, int64(3), versions)
}

func TestVideoKindTriggerAllowsClearingOnTypeChange(t *testing.T) {
	db := setupCatalogDB(t)
	media := models.Media{Title: "Video", Type: models.MediaTypeVideo, FilePath: "/v.mp4"}
	require.NoError(t, db.Create(&media).Error)
	require.Error(t, db.Model(&media).Updates(map[string]any{
		"type": models.MediaTypeAudio,
	}).Error)
	require.NoError(t, db.Model(&media).Updates(map[string]any{
		"type":       models.MediaTypeAudio,
		"video_kind": nil,
	}).Error)
	var got models.Media
	require.NoError(t, db.First(&got, media.ID).Error)
	require.Equal(t, models.MediaTypeAudio, got.Type)
	require.Nil(t, got.VideoKind)
}
