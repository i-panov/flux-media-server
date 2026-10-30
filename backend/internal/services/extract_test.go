package services

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)

func TestExtractTargetFor(t *testing.T) {
	cases := []struct {
		codec      string
		ext        string
		format     string
		encodeFLAC bool
	}{
		{"aac", ".m4a", "mp4", false},
		{"mp3", ".mp3", "mp3", false},
		{"opus", ".opus", "opus", false},
		{"vorbis", ".ogg", "ogg", false},
		{"flac", ".flac", "flac", false},
		{"alac", ".m4a", "mp4", false},
		{"wav", ".wav", "wav", false},
		{"pcm_s16le", ".wav", "wav", false},
		{"ac3", ".flac", "flac", true},
		{"eac3", ".flac", "flac", true},
		{"dts", ".flac", "flac", true},
		{"dts_hd", ".flac", "flac", true},
		{"truehd", ".flac", "flac", true},
		{"AAC", ".m4a", "mp4", false},
		{"Opus", ".opus", "opus", false},
		// Неизвестный кодек — lossless-фолбэк вместо падения.
		{"siren", ".flac", "flac", true},
	}
	for _, tc := range cases {
		target := extractTargetFor(tc.codec)
		assert.Equal(t, tc.ext, target.ext, "codec %s", tc.codec)
		assert.Equal(t, tc.format, target.format, "codec %s", tc.codec)
		assert.Equal(t, tc.encodeFLAC, target.encodeFLAC, "codec %s", tc.codec)
	}
}

func setupExtractTestService(t *testing.T, workers int) (*ExtractService, repository.MediaRepository, string) {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	mediaRepo := repository.NewMediaRepository(db)
	thumbSvc := NewThumbnailService(t.TempDir())
	audioDir := t.TempDir()
	q := NewExtractService(context.Background(), mediaRepo, repository.NewExtractTaskRepository(db), thumbSvc, audioDir, workers, 10)
	t.Cleanup(q.Stop)
	return q, mediaRepo, audioDir
}

func TestExtractQueueEnqueueGetCancel(t *testing.T) {
	// workers=0: задание остаётся queued — детерминированная проверка
	// механики без ffmpeg.
	q, _, _ := setupExtractTestService(t, 0)

	id, err := q.Enqueue(7)
	require.NoError(t, err)

	status, _, _, ok := q.Get(id)
	require.True(t, ok)
	assert.Equal(t, ExtractJobQueued, status)

	require.NoError(t, q.Cancel(id))
	_, _, _, ok = q.Get(id)
	assert.False(t, ok)

	assert.ErrorIs(t, q.Cancel(id), ErrExtractJobNotFound)
}

func TestExtractServiceAvailableReflectsBinaries(t *testing.T) {
	// Честно в любом окружении: флаг равен наличию обоих бинарников.
	q, _, _ := setupExtractTestService(t, 0)
	_, ffmpegErr := exec.LookPath("ffmpeg")
	_, ffprobeErr := exec.LookPath("ffprobe")
	assert.Equal(t, ffmpegErr == nil && ffprobeErr == nil, q.Available())
}

// Крах в окне между Create и Done: трек со связкой уже записан, повтор
// обязан закрыться done сразу, а не гонять ffmpeg и падать в ложный
// «File already exists» по собственному сироте. Без ffmpeg: проверка
// стоит до probe, бинарники не нужны.
func TestExtractProcess_CompletesWhenTrackAlreadyLinked(t *testing.T) {
	q, mediaRepo, _ := setupExtractTestService(t, 0)
	ctx := context.Background()

	source := &models.Media{Title: "Clip", Type: models.MediaTypeVideo, FilePath: "/v/clip.mp4"}
	require.NoError(t, mediaRepo.Create(ctx, source))
	track := &models.Media{
		Title:         "Clip",
		Type:          models.MediaTypeAudio,
		FilePath:      "/a/clip.m4a",
		FileHash:      "orphan",
		SourceMediaID: &source.ID,
	}
	require.NoError(t, mediaRepo.Create(ctx, track))

	id, err := q.Enqueue(source.ID)
	require.NoError(t, err)
	q.mu.Lock()
	job := q.jobs[id]
	q.mu.Unlock()

	q.process(job)

	status, _, mediaID, ok := q.Get(id)
	require.True(t, ok)
	assert.Equal(t, ExtractJobDone, status)
	assert.Equal(t, track.ID, mediaID)
}

// Управляемый рестарт (SIGTERM → Stop) не должен хоронить летящее
// задание в error: fail при мёртвом q.ctx возвращает строку в queued,
// следующий старт подхватывает её через recovery. Живой контекст
// по-прежнему пишет терминальный error.
func TestExtractFail_RequeuesOnShutdown(t *testing.T) {
	q, _, _ := setupExtractTestService(t, 0)

	id, err := q.Enqueue(11)
	require.NoError(t, err)
	q.mu.Lock()
	job := q.jobs[id]
	q.mu.Unlock()

	q.cancel()
	q.fail(job, context.Canceled, "boom")

	status, errMsg, _, ok := q.Get(id)
	require.True(t, ok)
	assert.Equal(t, ExtractJobQueued, status)
	assert.Empty(t, errMsg)

	// Контроль: живой контекст по-прежнему пишет терминальный error.
	q2, _, _ := setupExtractTestService(t, 0)
	other, err := q2.Enqueue(12)
	require.NoError(t, err)
	q2.mu.Lock()
	otherJob := q2.jobs[other]
	q2.mu.Unlock()
	q2.fail(otherJob, assert.AnError, "boom")

	status, errMsg, _, ok = q2.Get(other)
	require.True(t, ok)
	assert.Equal(t, ExtractJobError, status)
	assert.Equal(t, "boom", errMsg)
}

// Перезапуск сервера поднимает незавершённые задания из БД: processing
// сбрасывается в queued, ID не переиспользуются, дедуп по источнику
// работает и для поднятых заданий.
func TestExtractService_RestartRecovery(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	ctx := context.Background()
	newService := func() *ExtractService {
		return NewExtractService(
			context.Background(),
			repository.NewMediaRepository(db),
			repository.NewExtractTaskRepository(db),
			NewThumbnailService(t.TempDir()),
			t.TempDir(),
			0,
			10,
		)
	}

	q1 := newService()
	id1, err := q1.Enqueue(7)
	require.NoError(t, err)
	require.NotZero(t, id1)
	// Имитация краха посреди обработки: строка осталась processing.
	store := repository.NewExtractTaskRepository(db)
	require.NoError(t, store.SetStatus(ctx, id1, ExtractJobProcessing, "", 0))
	q1.Stop()

	q2 := newService()
	t.Cleanup(q2.Stop)

	status, _, _, ok := q2.Get(id1)
	require.True(t, ok, "recovered job must be visible")
	assert.Equal(t, ExtractJobQueued, status)

	row, err := store.Get(ctx, id1)
	require.NoError(t, err)
	assert.Equal(t, ExtractJobQueued, row.Status)

	// Дедуп видит поднятое задание: повторный POST отдаёт тот же ID.
	dup, err := q2.Enqueue(7)
	require.NoError(t, err)
	assert.Equal(t, id1, dup)

	// Новые задания продолжают счётчик, а не занимают старые ID.
	id2, err := q2.Enqueue(8)
	require.NoError(t, err)
	assert.Greater(t, id2, id1)

	// Отмена удаляет и строку.
	require.NoError(t, q2.Cancel(id1))
	_, _, _, ok = q2.Get(id1)
	assert.False(t, ok)
	_, err = store.Get(ctx, id1)
	require.Error(t, err)
}

func TestExtractQueueDedupsInflightBySource(t *testing.T) {
	// Два параллельных POST одного видео — один джоб: повтор возвращает
	// ID летящего задания вместо нового (иначе два ffmpeg на источник).
	q, _, _ := setupExtractTestService(t, 0)

	first, err := q.Enqueue(7)
	require.NoError(t, err)
	second, err := q.Enqueue(7)
	require.NoError(t, err)
	assert.Equal(t, first, second)

	// Другое видео — отдельный джоб.
	other, err := q.Enqueue(8)
	require.NoError(t, err)
	assert.NotEqual(t, first, other)

	q.mu.Lock()
	count := len(q.jobs)
	q.mu.Unlock()
	assert.Equal(t, 2, count)
}

func TestExtractQueueConcurrentEnqueueSameSource(t *testing.T) {
	// Настоящая гонка: 8 горутин одновременно ставят одно видео.
	// Без дедупа в карте оказалось бы 8 джобов и 8 ffmpeg.
	q, _, _ := setupExtractTestService(t, 0)

	const n = 8
	ids := make([]uint, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			id, err := q.Enqueue(7)
			assert.NoError(t, err)
			ids[i] = id
		}(i)
	}
	wg.Wait()

	for _, id := range ids[1:] {
		assert.Equal(t, ids[0], id)
	}
	q.mu.Lock()
	count := len(q.jobs)
	q.mu.Unlock()
	assert.Equal(t, 1, count)
}

func TestExtractQueueFull(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	// limit=1, workers=0: первое задание занимает канал, второе — 429.
	q := NewExtractService(
		context.Background(),
		repository.NewMediaRepository(db),
		repository.NewExtractTaskRepository(db),
		NewThumbnailService(t.TempDir()),
		t.TempDir(),
		0,
		1,
	)
	t.Cleanup(q.Stop)

	_, err = q.Enqueue(1)
	require.NoError(t, err)
	_, err = q.Enqueue(2)
	assert.ErrorIs(t, err, ErrExtractQueueFull)
}

func TestCommitFile(t *testing.T) {
	dir := t.TempDir()

	tmp := filepath.Join(dir, "a.m4a.part-1")
	require.NoError(t, os.WriteFile(tmp, []byte("data"), 0644))
	dst := filepath.Join(dir, "a.m4a")

	require.NoError(t, commitFile(tmp, dst))
	assert.FileExists(t, dst)
	assert.NoFileExists(t, tmp)

	// Занятый dst — ошибка без перезаписи (у чужой записи свой путь).
	tmp2 := filepath.Join(dir, "b.m4a.part-2")
	require.NoError(t, os.WriteFile(tmp2, []byte("new"), 0644))
	err := commitFile(tmp2, dst)
	assert.ErrorIs(t, err, errExtractFileExists)
	assert.FileExists(t, tmp2)
	content, err := os.ReadFile(dst)
	require.NoError(t, err)
	assert.Equal(t, "data", string(content))
}

func TestExtractSweepRemovesTerminal(t *testing.T) {
	q, _, _ := setupExtractTestService(t, 0)

	old, err := q.Enqueue(1)
	require.NoError(t, err)
	fresh, err := q.Enqueue(2)
	require.NoError(t, err)

	q.mu.Lock()
	q.jobs[old].Status = ExtractJobError
	q.jobs[old].createdAt = time.Now().Add(-2 * extractJobTTL)
	q.mu.Unlock()

	q.sweep()

	_, _, _, ok := q.Get(old)
	assert.False(t, ok)
	_, _, _, ok = q.Get(fresh)
	assert.True(t, ok)
}

func TestExtractCancelProcessingJob(t *testing.T) {
	// Отмена стирает задание из карты: статус превращается в 404.
	q, _, _ := setupExtractTestService(t, 0)

	id, err := q.Enqueue(3)
	require.NoError(t, err)
	require.NoError(t, q.Cancel(id))

	_, _, _, ok := q.Get(id)
	assert.False(t, ok)
}

func TestExtractProcessCopiesAudioStream(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg not available")
	}
	if _, err := exec.LookPath("ffprobe"); err != nil {
		t.Skip("ffprobe not available")
	}

	q, mediaRepo, audioDir := setupExtractTestService(t, 1)

	// Фикстура: 2 секунды видео с синусом 440 Гц (aac) — генерим тут же,
	// хранить бинарные фикстуры в репозитории не будем.
	srcPath := filepath.Join(t.TempDir(), "clip.mp4")
	gen := exec.Command("ffmpeg",
		"-f", "lavfi", "-i", "testsrc=duration=2:size=64x64:rate=10",
		"-f", "lavfi", "-i", "sine=frequency=440:duration=2",
		"-c:v", "libx264", "-c:a", "aac", "-shortest", "-y", srcPath,
	)
	require.NoError(t, gen.Run())

	source := &models.Media{
		Title:    "Clip",
		Filename: "clip.mp4",
		Type:     models.MediaTypeVideo,
		FilePath: srcPath,
	}
	require.NoError(t, mediaRepo.Create(context.Background(), source))

	id, err := q.Enqueue(source.ID)
	require.NoError(t, err)

	// Ждём терминального статуса (stream copy идёт со скоростью IO).
	deadline := time.Now().Add(2 * time.Minute)
	for {
		status, errMsg, mediaID, ok := q.Get(id)
		require.True(t, ok)
		require.NotEqual(t, ExtractJobError, status, "error: %s", errMsg)
		if status == ExtractJobDone {
			require.NotZero(t, mediaID)
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("extract job did not finish in time")
		}
		time.Sleep(100 * time.Millisecond)
	}

	_, _, mediaID, _ := q.Get(id)
	track, err := mediaRepo.FindByID(context.Background(), mediaID)
	require.NoError(t, err)
	assert.True(t, track.Type.IsAudio())
	assert.Equal(t, ".m4a", filepath.Ext(track.FilePath))
	assert.Equal(t, source.ID, *track.SourceMediaID)
	assert.Equal(t, "Clip", track.Title)
	assert.DirExists(t, audioDir)
	assert.FileExists(t, track.FilePath)

	// Связка находится обратным поиском для экрана видео.
	linked, err := mediaRepo.FindBySourceMediaID(context.Background(), source.ID)
	require.NoError(t, err)
	assert.Equal(t, track.ID, linked.ID)
}

func TestExtractProcessNoAudioStream(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg not available")
	}

	q, mediaRepo, _ := setupExtractTestService(t, 1)

	// Видео без аудиодорожки.
	srcPath := filepath.Join(t.TempDir(), "silent.mp4")
	gen := exec.Command("ffmpeg",
		"-f", "lavfi", "-i", "testsrc=duration=1:size=64x64:rate=10",
		"-c:v", "libx264", "-an", "-y", srcPath,
	)
	require.NoError(t, gen.Run())

	source := &models.Media{
		Title:    "Silent",
		Filename: "silent.mp4",
		Type:     models.MediaTypeVideo,
		FilePath: srcPath,
	}
	require.NoError(t, mediaRepo.Create(context.Background(), source))

	id, err := q.Enqueue(source.ID)
	require.NoError(t, err)

	deadline := time.Now().Add(2 * time.Minute)
	for {
		status, errMsg, _, ok := q.Get(id)
		require.True(t, ok)
		if status == ExtractJobError {
			assert.Contains(t, errMsg, "audio")
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("extract job did not finish in time")
		}
		time.Sleep(100 * time.Millisecond)
	}
}

func TestExtractRejectsTraversalTitleWithoutFFmpeg(t *testing.T) {
	// Валидация имени идёт до probe: траверсал в title отклоняется
	// без ffmpeg/ffprobe.
	q, mediaRepo, _ := setupExtractTestService(t, 1)

	source := &models.Media{
		Title:    "../../evil",
		Filename: "clip.mp4",
		Type:     models.MediaTypeVideo,
		FilePath: "/nonexistent.mp4",
	}
	require.NoError(t, mediaRepo.Create(context.Background(), source))

	id, err := q.Enqueue(source.ID)
	require.NoError(t, err)

	deadline := time.Now().Add(30 * time.Second)
	for {
		status, errMsg, _, ok := q.Get(id)
		require.True(t, ok)
		if status == ExtractJobError {
			assert.Contains(t, errMsg, "Invalid filename")
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("extract job did not finish in time")
		}
		time.Sleep(50 * time.Millisecond)
	}
}

func TestExtractMaxKeptOverflow(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	store := repository.NewExtractTaskRepository(db)
	q := NewExtractService(context.Background(), repository.NewMediaRepository(db), store, NewThumbnailService(t.TempDir()), t.TempDir(), 0, 1000)
	t.Cleanup(q.Stop)

	// Набиваем терминальных заданий сверх потолка напрямую.
	ctx := context.Background()
	for i := 0; i < maxKeptExtractJobs+10; i++ {
		row := &models.ExtractTask{SourceMediaID: uint(i + 1), Status: ExtractJobError}
		require.NoError(t, store.Create(ctx, row))
		q.mu.Lock()
		q.jobs[row.ID] = &ExtractJob{
			ID:        row.ID,
			Status:    ExtractJobError,
			createdAt: time.Now(),
		}
		q.mu.Unlock()
	}

	q.sweep()

	q.mu.Lock()
	count := len(q.jobs)
	q.mu.Unlock()
	assert.Equal(t, maxKeptExtractJobs, count)

	var rows int64
	require.NoError(t, db.Model(&models.ExtractTask{}).Count(&rows).Error)
	assert.Equal(t, int64(maxKeptExtractJobs), rows)
}

func TestTruncateFilename(t *testing.T) {
	short := "clip.m4a"
	assert.Equal(t, short, truncateFilename(short))

	long := string(make([]byte, 0))
	for i := 0; i < 300; i++ {
		long += "a"
	}
	long += ".m4a"
	got := truncateFilename(long)
	assert.LessOrEqual(t, len(got), maxExtractFilename)
	assert.True(t, len(got) > 0)
	assert.Equal(t, ".m4a", filepath.Ext(got))

	// Многобайтовые руны не рвутся пополам.
	wide := ""
	for i := 0; i < 100; i++ {
		wide += "ж"
	}
	wide += ".m4a"
	got = truncateFilename(wide)
	assert.LessOrEqual(t, len(got), maxExtractFilename)
	assert.True(t, len(got) > 0)
	assert.Equal(t, ".m4a", filepath.Ext(got))
	require.NotPanics(t, func() {
		_ = []rune(got)
	})
}

func TestFFmpegArgs(t *testing.T) {
	// Проверяем собранные args без бинарника: -f обязателен (tmp-файл
	// с суффиксом .part-N ffmpeg иначе не опознаёт), -map режет лишние
	// дорожки, -n запрещает молчаливую перезапись.
	copyArgs := ffmpegArgs("/v/clip.mkv", "/a/clip.m4a.part-3", extractTargetFor("aac"))
	assert.Equal(t, []string{
		"-i", "/v/clip.mkv", "-vn", "-n", "-f", "mp4",
		"-map", "0:a:0", "-c:a", "copy", "/a/clip.m4a.part-3",
	}, copyArgs)

	flacArgs := ffmpegArgs("/v/clip.mkv", "/a/clip.flac.part-3", extractTargetFor("truehd"))
	assert.Equal(t, []string{
		"-i", "/v/clip.mkv", "-vn", "-n", "-f", "flac",
		"-map", "0:a:0", "-c:a", "flac", "/a/clip.flac.part-3",
	}, flacArgs)
}
