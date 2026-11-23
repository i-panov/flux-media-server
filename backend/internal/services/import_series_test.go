package services

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)

// fakeTranscoder создаёт медиа сразу и отдаёт done: тест проверяет
// каталог, а не ffmpeg.
type fakeTranscoder struct {
	media  *repository.MediaStore
	next   uint64
	lastID uint
}

func (f *fakeTranscoder) Enqueue(sourcePath, filename string) (uint64, error) {
	f.next++
	media := models.Media{
		Title:    filename,
		Type:     models.MediaTypeVideo,
		FilePath: sourcePath,
		Duration: 1,
	}
	if err := f.media.Create(context.Background(), &media); err != nil {
		return 0, err
	}
	f.lastID = media.ID
	return f.next, nil
}

func (f *fakeTranscoder) Get(id uint64) (TranscodeJobStatus, bool) {
	// Один job на файл: media ищем по последнему созданному.
	return TranscodeJobStatus{Status: TranscodeTaskDone, MediaID: f.lastID, Progress: 100}, true
}

func (f *fakeTranscoder) Cancel(uint64) error { return nil }

func TestImportCreatesSeriesWithSeasonsAndEpisodes(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	loader := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/videos":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{
				"status":"ready","collection":true,
				"series":{"id":"s-1","title":"Тестовый сериал"},
				"seasons":[1,2],
				"episodes":[
					{"season":1,"episode":1,"title":"Пилот","status":"ready","filename":"s01e01.mp4","download_url":"/files/1"},
					{"season":1,"episode":2,"title":"Второй","status":"ready","filename":"s01e02.mp4","download_url":"/files/2"},
					{"season":2,"episode":1,"title":"Третий","status":"ready","filename":"s02e01.mp4","download_url":"/files/3"}
				]
			}`))
		case r.Method == http.MethodGet && r.URL.Path == "/files/1":
			_, _ = w.Write([]byte("first"))
		case r.Method == http.MethodGet && r.URL.Path == "/files/2":
			_, _ = w.Write([]byte("second"))
		case r.Method == http.MethodGet && r.URL.Path == "/files/3":
			_, _ = w.Write([]byte("third"))
		default:
			http.NotFound(w, r)
		}
	}))
	defer loader.Close()

	mediaRepo := repository.NewMediaRepository(db)
	transcoder := &fakeTranscoder{media: mediaRepo}
	mediaLoader := NewMediaLoader(loader.URL, "", t.TempDir(), 1<<20, time.Second,
		fakeUploadEnqueuer{}, transcoder)
	mediaLoader.SetSourceStore(mediaRepo)
	works := repository.NewWorkRepository(db)
	imports := repository.NewImportRepository(db)
	service := NewImportService(mediaLoader, works, imports)

	job, err := service.Start(ImportRequest{
		URL: "https://example.com/series", Scope: "series",
		Title: "Тестовый сериал", SeriesID: "s-1",
		Episodes: []ImportSelection{{Season: 1, Episode: 1}, {Season: 1, Episode: 2}, {Season: 2, Episode: 1}},
	})
	require.NoError(t, err)

	require.Eventually(t, func() bool {
		stored, _, err := imports.Get(context.Background(), job.ID)
		if err != nil {
			return false
		}
		return stored.Status == models.ImportDone
	}, 10*time.Second, 50*time.Millisecond)

	series, err := works.List(context.Background(), models.WorkKindSeries)
	require.NoError(t, err)
	require.Len(t, series, 1)
	require.Equal(t, models.WorkKindSeries, series[0].Kind)
	require.Equal(t, "Тестовый сериал", series[0].Title)

	work, err := works.Get(context.Background(), series[0].ID)
	require.NoError(t, err)
	require.Len(t, work.Seasons, 2)
	numbers := map[int]int{}
	for _, season := range work.Seasons {
		numbers[season.SeasonNumber] = len(season.Items)
	}
	require.Equal(t, 2, numbers[1])
	require.Equal(t, 1, numbers[2])

	// Серии — эпизоды, а не отдельные фильмы в гриде.
	var episodes int64
	require.NoError(t, db.Model(&models.Media{}).
		Where("video_kind = ?", models.VideoKindEpisode).Count(&episodes).Error)
	require.Equal(t, int64(3), episodes)

	// Ссылка на сериал сохраняется как источник у каждой серии.
	var withSource int64
	require.NoError(t, db.Model(&models.Media{}).
		Where("source_url = ?", "https://example.com/series").Count(&withSource).Error)
	require.Equal(t, int64(3), withSource)
}
