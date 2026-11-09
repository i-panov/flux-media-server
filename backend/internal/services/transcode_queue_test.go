package services

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
)

// fakeTranscodeRunner — раннер без ffmpeg: пишет маркерные файлы,
// отдаёт canned-probe, считает вызовы под мьютексом (воркер в другой
// горутине — без синхронизации стрельнет -race).
type fakeTranscodeRunner struct {
	mu             sync.Mutex
	probe          ProbeResult
	probeErr       error
	transcodeErr   error
	remuxErr       error
	subsErr        error
	transcodeCalls int
	remuxCalls     int
	fixAudioCalls  int
	subsCalls      int
	progressSteps  []ProgressUpdate
}

func (f *fakeTranscodeRunner) Probe(_ context.Context, path string) (ProbeResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.probeErr != nil {
		return ProbeResult{}, f.probeErr
	}
	probe := f.probe
	probe.Filename = path
	return probe, nil
}

func (f *fakeTranscodeRunner) TranscodeVideo(ctx context.Context, _, dst string, _ NormalizePlan, _ TranscodeOptions, progress func(ProgressUpdate)) error {
	f.mu.Lock()
	f.transcodeCalls++
	steps := f.progressSteps
	f.mu.Unlock()
	if f.transcodeErr != nil {
		return f.transcodeErr
	}
	if err := os.WriteFile(dst, []byte("fake-video-content"), 0644); err != nil {
		return err
	}
	for _, step := range steps {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		progress(step)
	}
	return nil
}

func (f *fakeTranscodeRunner) RemuxCopy(_ context.Context, src, dst string, _ NormalizePlan) error {
	f.mu.Lock()
	f.remuxCalls++
	f.mu.Unlock()
	if f.remuxErr != nil {
		return f.remuxErr
	}
	content, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, content, 0644)
}

func (f *fakeTranscodeRunner) FixAudio(ctx context.Context, src, dst string, plan NormalizePlan, _ time.Duration, progress func(ProgressUpdate)) error {
	f.mu.Lock()
	f.fixAudioCalls++
	steps := f.progressSteps
	f.mu.Unlock()
	if err := os.WriteFile(dst, []byte("fake-audiofixed-content"), 0644); err != nil {
		return err
	}
	for _, step := range steps {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		progress(step)
	}
	return nil
}

func (f *fakeTranscodeRunner) ExtractSubtitles(_ context.Context, _ string, _ SubTrack, output string) error {
	f.mu.Lock()
	f.subsCalls++
	f.mu.Unlock()
	if f.subsErr != nil {
		return f.subsErr
	}
	return os.WriteFile(output, []byte("WEBVTT\n\n"), 0644)
}

func (f *fakeTranscodeRunner) counts() (transcode, remux, fixAudio, subs int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.transcodeCalls, f.remuxCalls, f.fixAudioCalls, f.subsCalls
}

// transcodeTestDB — файловая БД (не :memory:): воркер ходит в БД из
// своей горутины, а у :memory: каждое соединение пула — своя пустая копия.
func transcodeTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	db, err := repository.InitDB(filepath.Join(t.TempDir(), "test.db"))
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	sqlDB, err := db.DB()
	require.NoError(t, err)
	t.Cleanup(func() { sqlDB.Close() })
	return db
}

type transcodeTestEnv struct {
	db      *gorm.DB
	queue   *TranscodeQueue
	media   repository.MediaRepository
	tasks   repository.TranscodeTaskRepository
	library string
	quar    string
	tmp     string
}

func setupTranscodeTest(t *testing.T, runner FFmpegRunner, autoCleanup bool) *transcodeTestEnv {
	t.Helper()
	db := transcodeTestDB(t)
	mediaRepo := repository.NewMediaRepository(db)
	taskRepo := repository.NewTranscodeTaskRepository(db)
	subRepo := repository.NewSubtitleRepository(db)
	thumbSvc := NewThumbnailService(filepath.Join(t.TempDir(), "thumbs"))

	base := t.TempDir()
	env := &transcodeTestEnv{
		db:      db,
		media:   mediaRepo,
		tasks:   taskRepo,
		library: filepath.Join(base, "library"),
		quar:    filepath.Join(base, "quar"),
		tmp:     filepath.Join(base, "tmp"),
	}
	for _, dir := range []string{env.library, env.quar, env.tmp} {
		require.NoError(t, os.MkdirAll(dir, 0755))
	}
	env.queue = NewTranscodeQueue(context.Background(), TranscodeWorkerConfig{
		MaxAttempts:     1,
		LibraryVideoDir: env.library,
		OriginalsDir:    env.quar,
		TempDir:         env.tmp,
		AutoCleanup:     autoCleanup,
	}, taskRepo, mediaRepo, subRepo, thumbSvc, runner)
	t.Cleanup(env.queue.Stop)
	return env
}

func writeSource(t *testing.T, dir, name, content string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	require.NoError(t, os.WriteFile(path, []byte(content), 0644))
	return path
}

func waitForTask(t *testing.T, q *TranscodeQueue, id uint64, terminal ...string) TranscodeJobStatus {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		st, ok := q.Get(id)
		require.True(t, ok, "task %d disappeared", id)
		for _, want := range terminal {
			if st.Status == want {
				return st
			}
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("task %d did not reach %v within timeout", id, terminal)
	return TranscodeJobStatus{}
}

func TestTranscodeDirectFlow(t *testing.T) {
	runner := &fakeTranscodeRunner{probe: ProbeResult{
		Container: "mov,mp4,m4a", HasVideo: true, VideoCodec: "h264", PixFmt: "yuv420p",
		Width: 1280, Height: 720, HasAudio: true, DurationSec: 60,
	}}
	env := setupTranscodeTest(t, runner, false)

	src := writeSource(t, env.quar, "film.mp4", "fake-original-content")
	id, err := env.queue.Enqueue(src, "film.mp4")
	require.NoError(t, err)

	st := waitForTask(t, env.queue, id, TranscodeTaskDone)
	assert.Equal(t, 100, st.Progress)
	require.NotZero(t, st.MediaID)

	// Direct перемещает файл в библиотеку: потерь нет, копию в карантине
	// не держим (иначе каждый файл лежал бы дважды).
	_, err = os.Stat(src)
	require.True(t, os.IsNotExist(err), "direct must move, not copy")

	media, err := env.media.FindByID(context.Background(), st.MediaID)
	require.NoError(t, err)
	assert.Equal(t, "film.mp4", media.Filename)
	assert.NotEmpty(t, media.FileHash)
	assert.NotEmpty(t, media.SourceHash)
	assert.Equal(t, uint64(0), media.ViewCount)
	assert.Equal(t, 720, media.Height)

	transcode, remux, _, _ := runner.counts()
	assert.Equal(t, 0, transcode)
	assert.Equal(t, 0, remux)
}

func TestTranscodeRemuxFlow(t *testing.T) {
	runner := &fakeTranscodeRunner{probe: ProbeResult{
		Container: "matroska,webm", HasVideo: true, VideoCodec: "h264", PixFmt: "yuv420p",
		Width: 1920, Height: 1080, HasAudio: true, DurationSec: 120,
		TextSubs: []SubTrack{{Index: 2, Codec: "subrip", Lang: "rus"}},
	}}
	env := setupTranscodeTest(t, runner, false)

	src := writeSource(t, env.quar, "film.mkv", "fake-mkv-content")
	id, err := env.queue.Enqueue(src, "film.mkv")
	require.NoError(t, err)

	st := waitForTask(t, env.queue, id, TranscodeTaskDone)
	media, err := env.media.FindByID(context.Background(), st.MediaID)
	require.NoError(t, err)
	assert.Equal(t, "film.mp4", media.Filename)

	// Ремукс без потерь — исходник не храним.
	_, err = os.Stat(src)
	require.True(t, os.IsNotExist(err), "remux source must not stay in quarantine")

	// VTT-сайдкар рядом с результатом и строка в БД.
	subs, err := env.queue.subs.ListByMedia(context.Background(), media.ID)
	require.NoError(t, err)
	require.Len(t, subs, 1)
	assert.Equal(t, "rus", subs[0].Lang)
	_, err = os.Stat(subs[0].Path)
	require.NoError(t, err)

	_, remux, _, subsCalls := runner.counts()
	assert.Equal(t, 1, remux)
	assert.Equal(t, 1, subsCalls)
}

func TestTranscodeFullFlowProgress(t *testing.T) {
	runner := &fakeTranscodeRunner{
		probe: ProbeResult{
			Container: "matroska,webm", HasVideo: true, VideoCodec: "hevc",
			Width: 1920, Height: 1080, DurationSec: 100,
		},
		progressSteps: []ProgressUpdate{
			{Percent: 10, Speed: 2},
			{Percent: 50, Speed: 2},
			{Percent: 90, Speed: 2},
		},
	}
	env := setupTranscodeTest(t, runner, false)

	src := writeSource(t, env.quar, "film-hevc.mkv", "fake-hevc-content")
	id, err := env.queue.Enqueue(src, "film-hevc.mkv")
	require.NoError(t, err)

	st := waitForTask(t, env.queue, id, TranscodeTaskDone)
	assert.Equal(t, 100, st.Progress)

	// Lossy-транскод: оригинал остаётся в карантине.
	_, err = os.Stat(src)
	require.NoError(t, err, "transcoded original must stay in quarantine")

	transcode, _, _, _ := runner.counts()
	assert.Equal(t, 1, transcode)
}

func TestTranscodeFailureKeepsOriginal(t *testing.T) {
	runner := &fakeTranscodeRunner{
		probe:        ProbeResult{Container: "matroska,webm", HasVideo: true, VideoCodec: "hevc", Width: 1920, Height: 1080, DurationSec: 100},
		transcodeErr: errFakeFFmpeg,
	}
	env := setupTranscodeTest(t, runner, false)

	src := writeSource(t, env.quar, "broken.mkv", "fake-content")
	id, err := env.queue.Enqueue(src, "broken.mkv")
	require.NoError(t, err)

	st := waitForTask(t, env.queue, id, TranscodeTaskError)
	assert.NotEmpty(t, st.Error)
	assert.Zero(t, st.MediaID)

	// Оригинал цел (нужен ретраю и админу), temp прибран.
	_, err = os.Stat(src)
	require.NoError(t, err, "original must survive failure")
	entries, err := os.ReadDir(env.tmp)
	require.NoError(t, err)
	assert.Empty(t, entries, "temp must be cleaned")
}

func TestTranscodeDuplicateByContent(t *testing.T) {
	runner := &fakeTranscodeRunner{probe: ProbeResult{
		Container: "mov,mp4,m4a", HasVideo: true, VideoCodec: "h264", PixFmt: "yuv420p",
		Width: 640, Height: 480, DurationSec: 10,
	}}
	env := setupTranscodeTest(t, runner, false)

	first := writeSource(t, env.quar, "a.mp4", "same-content")
	id1, err := env.queue.Enqueue(first, "a.mp4")
	require.NoError(t, err)
	waitForTask(t, env.queue, id1, TranscodeTaskDone)

	second := writeSource(t, env.quar, "b.mp4", "same-content")
	id2, err := env.queue.Enqueue(second, "b.mp4")
	require.NoError(t, err)
	st := waitForTask(t, env.queue, id2, TranscodeTaskError)
	assert.Equal(t, "File already exists", st.Error)
	// Дубль удалён из карантина сразу.
	_, err = os.Stat(second)
	require.True(t, os.IsNotExist(err))

	// Вторая запись Media не создана.
	all, _, err := env.media.FindAll(context.Background(), repository.MediaFilters{}, 100, 0)
	require.NoError(t, err)
	assert.Len(t, all, 1)
}

func TestTranscodeRequeueInterrupted(t *testing.T) {
	runner := &fakeTranscodeRunner{}
	env := setupTranscodeTest(t, runner, false)
	env.queue.Stop()

	task := &models.TranscodeTask{SourcePath: "/gone/missing.mp4", Filename: "missing.mp4", Status: TranscodeTaskProcessing}
	require.NoError(t, env.tasks.Create(context.Background(), task))

	n, err := env.queue.RequeueInterrupted(context.Background())
	require.NoError(t, err)
	assert.Equal(t, int64(1), n)

	got, err := env.tasks.Get(context.Background(), task.ID)
	require.NoError(t, err)
	assert.Equal(t, TranscodeTaskQueued, got.Status)
}

func TestTranscodeCancelQueued(t *testing.T) {
	runner := &fakeTranscodeRunner{}
	env := setupTranscodeTest(t, runner, false)
	env.queue.Stop()

	src := writeSource(t, env.quar, "cancel.mp4", "data")
	id, err := env.queue.Enqueue(src, "cancel.mp4")
	require.NoError(t, err)

	require.NoError(t, env.queue.Cancel(id))
	st, ok := env.queue.Get(id)
	require.True(t, ok)
	assert.Equal(t, TranscodeTaskCancelled, st.Status)
	_, err = os.Stat(src)
	require.True(t, os.IsNotExist(err), "cancelled queued task removes source")

	require.ErrorIs(t, env.queue.Cancel(999999), ErrTranscodeJobNotFound)
}

func TestTranscodeRetry(t *testing.T) {
	runner := &fakeTranscodeRunner{
		probe:        ProbeResult{Container: "matroska,webm", HasVideo: true, VideoCodec: "hevc", Width: 1280, Height: 720, DurationSec: 30},
		transcodeErr: errFakeFFmpeg,
	}
	env := setupTranscodeTest(t, runner, false)

	src := writeSource(t, env.quar, "retry.mkv", "data")
	id, err := env.queue.Enqueue(src, "retry.mkv")
	require.NoError(t, err)
	waitForTask(t, env.queue, id, TranscodeTaskError)

	// Чиним раннер и ретраим вручную: задание должно дойти.
	runner.transcodeErr = nil
	require.NoError(t, env.queue.Retry(id))
	st := waitForTask(t, env.queue, id, TranscodeTaskDone)
	require.NotZero(t, st.MediaID)

	require.ErrorIs(t, env.queue.Retry(id), ErrTranscodeJobDone)
}

func TestTranscodeAutoCleanupOrder(t *testing.T) {
	runner := &fakeTranscodeRunner{}
	env := setupTranscodeTest(t, runner, true)

	// Три готовых оригинала: A (0 просмотров), B (5), C (0 просмотров, меньше).
	mkDone := func(name, content string, views uint64) {
		src := writeSource(t, env.quar, name, content)
		// Файл копии обязан существовать, иначе оригинал — orphaned,
		// а не кандидат на чистку.
		resultPath := filepath.Join(env.library, name)
		require.NoError(t, os.WriteFile(resultPath, []byte("result"), 0644))
		media := &models.Media{Title: name, Type: models.MediaTypeVideo, FilePath: resultPath, FileHash: "h-" + name}
		require.NoError(t, env.media.Create(context.Background(), media))
		for i := uint64(0); i < views; i++ {
			require.NoError(t, env.media.IncrementViews(context.Background(), media.ID))
		}
		require.NoError(t, env.tasks.Create(context.Background(), &models.TranscodeTask{
			SourcePath: src, Filename: name, Status: TranscodeTaskDone, MediaID: media.ID,
		}))
	}
	mkDone("a.mp4", "aaa", 0)
	mkDone("b.mp4", "bbb", 5)
	mkDone("c.mp4", "c", 0)

	// Свободно 100, нужно 500, после первого удаления — 600: уйти должен
	// ровно один, самый несмотримый и большой (a.mp4, не c.mp4).
	calls := 0
	env.queue.freeBytes = func(string) int64 {
		calls++
		if calls == 1 {
			return 100
		}
		return 600
	}
	require.NoError(t, env.queue.EnsureSpaceForUpload(500))

	_, err := os.Stat(filepath.Join(env.quar, "a.mp4"))
	require.True(t, os.IsNotExist(err), "least watched biggest must go first")
	_, err = os.Stat(filepath.Join(env.quar, "b.mp4"))
	require.NoError(t, err)
	_, err = os.Stat(filepath.Join(env.quar, "c.mp4"))
	require.NoError(t, err)
}

func TestTranscodeNoSpaceWithoutCleanup(t *testing.T) {
	runner := &fakeTranscodeRunner{}
	env := setupTranscodeTest(t, runner, false)

	env.queue.freeBytes = func(string) int64 { return 10 }
	err := env.queue.EnsureSpaceForUpload(500)
	require.ErrorIs(t, err, ErrInsufficientSpace)
}

func TestEstimateSeconds(t *testing.T) {
	assert.Equal(t, int64(25), estimateSeconds(&models.TranscodeTask{Progress: 50, Speed: 2, DurationSecs: 100}))
	assert.Equal(t, int64(0), estimateSeconds(&models.TranscodeTask{Progress: 100, Speed: 2, DurationSecs: 100}))
	assert.Equal(t, int64(0), estimateSeconds(&models.TranscodeTask{Progress: 10, Speed: 0, DurationSecs: 100}))
	assert.Equal(t, int64(0), estimateSeconds(nil))
}

func TestTranscodeAudioFixFlow(t *testing.T) {
	// Видео в порядке, аудио DTS: чинится только аудио, libx264 не вызывается.
	runner := &fakeTranscodeRunner{probe: ProbeResult{
		Container: "mov,mp4,m4a", HasVideo: true, VideoCodec: "h264", PixFmt: "yuv420p",
		VideoIndex: 0, Width: 1920, Height: 1080,
		HasAudio: true, AudioCodecs: []string{"dts"}, DurationSec: 90,
	}}
	env := setupTranscodeTest(t, runner, false)

	src := writeSource(t, env.quar, "film-dts.mp4", "fake-content")
	id, err := env.queue.Enqueue(src, "film-dts.mp4")
	require.NoError(t, err)

	st := waitForTask(t, env.queue, id, TranscodeTaskDone)
	require.NotZero(t, st.MediaID)

	transcode, _, fixAudio, _ := runner.counts()
	assert.Equal(t, 0, transcode, "video must be copied, not re-encoded")
	assert.Equal(t, 1, fixAudio)
}

func TestTranscodeMultiSubFlow(t *testing.T) {
	// Две дорожки одного языка: два отдельных вызова, два файла.
	runner := &fakeTranscodeRunner{probe: ProbeResult{
		Container: "matroska,webm", HasVideo: true, VideoCodec: "h264", PixFmt: "yuv420p",
		VideoIndex: 0, Width: 1280, Height: 720, HasAudio: true,
		AudioCodecs: []string{"aac"}, DurationSec: 60,
		TextSubs: []SubTrack{
			{Index: 2, Codec: "subrip", Lang: "eng"},
			{Index: 3, Codec: "ass", Lang: "eng"},
		},
	}}
	env := setupTranscodeTest(t, runner, false)

	src := writeSource(t, env.quar, "film.mkv", "fake-content")
	id, err := env.queue.Enqueue(src, "film.mkv")
	require.NoError(t, err)

	st := waitForTask(t, env.queue, id, TranscodeTaskDone)
	_, _, _, subsCalls := runner.counts()
	assert.Equal(t, 2, subsCalls)

	subs, err := env.queue.subs.ListByMedia(context.Background(), st.MediaID)
	require.NoError(t, err)
	require.Len(t, subs, 2)
	assert.Equal(t, "eng", subs[0].Lang)
	assert.Equal(t, "eng2", subs[1].Lang)
	for _, sub := range subs {
		_, err := os.Stat(sub.Path)
		require.NoError(t, err, "sidecar must exist")
	}
}

func TestTranscodeCancelDuringProcessing(t *testing.T) {
	// Фейк висит внутри TranscodeVideo, пока тест не отменит задание:
	// строка обязана остаться cancelled, исходник и temp — удалены,
	// поздние записи прогресса её не воскрешают.
	release := make(chan struct{})
	runner := &fakeTranscodeRunner{
		probe: ProbeResult{
			Container: "matroska,webm", HasVideo: true, VideoCodec: "hevc",
			VideoIndex: 0, Width: 1280, Height: 720, DurationSec: 600,
		},
	}
	runnerBlocking := &blockingRunner{inner: runner, release: release}
	env := setupTranscodeTest(t, runnerBlocking, false)

	src := writeSource(t, env.quar, "long.mkv", "fake-content")
	id, err := env.queue.Enqueue(src, "long.mkv")
	require.NoError(t, err)

	// Ждём, пока воркер войдёт в ffmpeg (progress-статус или processing).
	deadline := time.Now().Add(10 * time.Second)
	for {
		st, ok := env.queue.Get(id)
		require.True(t, ok)
		if st.Status == TranscodeTaskProcessing {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("task did not start processing")
		}
		time.Sleep(20 * time.Millisecond)
	}

	require.NoError(t, env.queue.Cancel(id))
	close(release)

	// Даём воркеру завершиться и проверяем конечное состояние.
	deadline = time.Now().Add(10 * time.Second)
	for {
		st, ok := env.queue.Get(id)
		require.True(t, ok)
		if st.Status == TranscodeTaskCancelled {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("task did not stay cancelled, status=%s", st.Status)
		}
		time.Sleep(20 * time.Millisecond)
	}

	st, _ := env.queue.Get(id)
	assert.Equal(t, TranscodeTaskCancelled, st.Status)
	assert.Zero(t, st.MediaID)
	// Чистку делает асинхронный воркер уже после пометки cancelled:
	// ждём исчезновения файла, а не проверяем мгновенно.
	deadline = time.Now().Add(10 * time.Second)
	for {
		_, err = os.Stat(src)
		if os.IsNotExist(err) {
			break
		}
		require.NoError(t, err)
		if time.Now().After(deadline) {
			t.Fatal("source was not removed on cancel")
		}
		time.Sleep(20 * time.Millisecond)
	}
	entries, err := os.ReadDir(env.tmp)
	require.NoError(t, err)
	assert.Empty(t, entries, "temp must be cleaned")
}

// blockingRunner оборачивает фейк: TranscodeVideo пишет результат
// и ждёт release (или отмены контекста) — эмуляция долгого счёта.
type blockingRunner struct {
	inner   *fakeTranscodeRunner
	release chan struct{}
}

func (b *blockingRunner) Probe(ctx context.Context, path string) (ProbeResult, error) {
	return b.inner.Probe(ctx, path)
}

func (b *blockingRunner) TranscodeVideo(ctx context.Context, src, dst string, plan NormalizePlan, opts TranscodeOptions, progress func(ProgressUpdate)) error {
	b.inner.mu.Lock()
	b.inner.transcodeCalls++
	b.inner.mu.Unlock()
	if b.inner.transcodeErr != nil {
		return b.inner.transcodeErr
	}
	if err := os.WriteFile(dst, []byte("fake-video-content"), 0644); err != nil {
		return err
	}
	select {
	case <-b.release:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (b *blockingRunner) RemuxCopy(ctx context.Context, src, dst string, plan NormalizePlan) error {
	return b.inner.RemuxCopy(ctx, src, dst, plan)
}

func (b *blockingRunner) FixAudio(ctx context.Context, src, dst string, plan NormalizePlan, timeoutCap time.Duration, progress func(ProgressUpdate)) error {
	return b.inner.FixAudio(ctx, src, dst, plan, timeoutCap, progress)
}

func (b *blockingRunner) ExtractSubtitles(ctx context.Context, src string, sub SubTrack, output string) error {
	return b.inner.ExtractSubtitles(ctx, src, sub, output)
}

func TestTranscodeSweepKeepsLinkedDone(t *testing.T) {
	runner := &fakeTranscodeRunner{}
	env := setupTranscodeTest(t, runner, false)
	env.queue.Stop()
	ctx := context.Background()

	// Старое done-задание с живым исходником — sweep не трогает.
	src := writeSource(t, env.quar, "old.mkv", "data")
	old := &models.TranscodeTask{SourcePath: src, Filename: "old.mkv", Status: TranscodeTaskDone, MediaID: 99}
	require.NoError(t, env.tasks.Create(ctx, old))
	backdateTask(t, env, old.ID, 8*24*time.Hour)

	// Старое done без исходника — уходит.
	gone := &models.TranscodeTask{SourcePath: filepath.Join(env.quar, "gone.mkv"), Filename: "gone.mkv", Status: TranscodeTaskDone}
	require.NoError(t, env.tasks.Create(ctx, gone))
	backdateTask(t, env, gone.ID, 8*24*time.Hour)

	env.queue.sweepTerminal()

	_, err := env.tasks.Get(ctx, old.ID)
	require.NoError(t, err, "done with existing source must survive sweep")
	_, err = env.tasks.Get(ctx, gone.ID)
	require.Error(t, err, "done without source must be swept")
}

func backdateTask(t *testing.T, env *transcodeTestEnv, id uint, age time.Duration) {
	t.Helper()
	// Напрямую мимо GORM-хуков: Save перезаписал бы updated_at текущим.
	require.NoError(t, env.db.Model(&models.TranscodeTask{}).Where("id = ?", id).UpdateColumn("updated_at", time.Now().Add(-age)).Error)
}

func TestTranscodeOrphanedNotEvicted(t *testing.T) {
	runner := &fakeTranscodeRunner{}
	env := setupTranscodeTest(t, runner, true)
	env.queue.freeBytes = func(string) int64 { return 0 }

	// Оригинал есть, а Media удалена навсегда — evict запрещён.
	src := writeSource(t, env.quar, "orphan.mkv", "data")
	require.NoError(t, env.tasks.Create(context.Background(), &models.TranscodeTask{
		SourcePath: src, Filename: "orphan.mkv", Status: TranscodeTaskDone, MediaID: 4242,
	}))

	infos, err := env.queue.OriginalsStatus()
	require.NoError(t, err)
	require.Len(t, infos, 1)
	assert.Equal(t, "orphaned", infos[0].Status)

	err = env.queue.EnsureSpaceForUpload(1 << 30)
	require.ErrorIs(t, err, ErrInsufficientSpace)
	_, err = os.Stat(src)
	require.NoError(t, err, "orphaned original must not be evicted")
}

func TestTranscodeUpdateIfStatus(t *testing.T) {
	db := transcodeTestDB(t)
	repo := repository.NewTranscodeTaskRepository(db)
	ctx := context.Background()

	task := &models.TranscodeTask{SourcePath: "/q/x.mkv", Status: TranscodeTaskProcessing, Progress: 10}
	require.NoError(t, repo.Create(ctx, task))

	task.Progress = 50
	ok, err := repo.UpdateIfStatus(ctx, task, TranscodeTaskProcessing)
	require.NoError(t, err)
	assert.True(t, ok)

	// Гонка: строка в БД уже cancelled (Cancel выиграл) — поздняя
	// запись воркера обязана потеряться, а не воскресить строку.
	require.NoError(t, db.Model(&models.TranscodeTask{}).Where("id = ?", task.ID).UpdateColumn("status", TranscodeTaskCancelled).Error)
	task.Status = TranscodeTaskDone
	task.Progress = 100
	ok, err = repo.UpdateIfStatus(ctx, task, TranscodeTaskProcessing)
	require.NoError(t, err)
	assert.False(t, ok)
	got, err := repo.Get(ctx, task.ID)
	require.NoError(t, err)
	assert.Equal(t, TranscodeTaskCancelled, got.Status)
	assert.Equal(t, 50, got.Progress)
}

var errFakeFFmpeg = errors.New("ffmpeg fake failure")

func TestTranscodeTrashedMissingFileProcessesAsNew(t *testing.T) {
	// Trashed-запись, чей файл уже удалён: восстанавливать нечего —
	// исходник НЕ удаляется, задание обрабатывается как новая загрузка.
	runner := &fakeTranscodeRunner{probe: ProbeResult{
		Container: "mov,mp4,m4a", HasVideo: true, VideoCodec: "h264", PixFmt: "yuv420p",
		VideoIndex: 0, Width: 640, Height: 480, DurationSec: 10,
	}}
	env := setupTranscodeTest(t, runner, false)
	ctx := context.Background()

	src := writeSource(t, env.quar, "ghost-new.mp4", "ghost-content")
	h, err := HashFileContext(ctx, src)
	require.NoError(t, err)
	ghost := &models.Media{
		Title: "Ghost", Type: models.MediaTypeVideo,
		FilePath:   filepath.Join(env.library, "ghost.mp4"),
		SourceHash: h,
	}
	require.NoError(t, env.media.Create(ctx, ghost))
	require.NoError(t, env.media.Delete(ctx, ghost.ID))

	id, err := env.queue.Enqueue(src, "ghost-new.mp4")
	require.NoError(t, err)
	st := waitForTask(t, env.queue, id, TranscodeTaskDone)
	require.NotZero(t, st.MediaID)
	assert.NotEqual(t, ghost.ID, st.MediaID, "битую trashed-запись нельзя воскрешать")

	// Исходник потреблён нормализацией (direct-move), trashed-строка цела.
	_, err = os.Stat(src)
	require.True(t, os.IsNotExist(err))
	_, err = env.media.FindTrashedMedia(ctx, ghost.ID)
	require.NoError(t, err)
}

func TestTranscodeSweepPagesPastKeptDone(t *testing.T) {
	runner := &fakeTranscodeRunner{}
	env := setupTranscodeTest(t, runner, false)
	env.queue.Stop()
	ctx := context.Background()
	old := time.Now().Add(-8 * 24 * time.Hour)

	// 1005 старых done с живыми исходниками (больше батча) + одно старое
	// error с бо́льшим id: sweep обязан дойти до него, а не жевать те же 1000.
	var dones []models.TranscodeTask
	for i := 0; i < 1005; i++ {
		name := "old-" + strconv.Itoa(i) + ".mkv"
		src := writeSource(t, env.quar, name, "data")
		dones = append(dones, models.TranscodeTask{
			SourcePath: src, Filename: name, Status: TranscodeTaskDone,
			CreatedAt: old, UpdatedAt: old,
		})
	}
	require.NoError(t, env.db.Create(&dones).Error)
	failing := &models.TranscodeTask{
		SourcePath: "/q/gone.mkv", Filename: "gone.mkv", Status: TranscodeTaskError,
		CreatedAt: old, UpdatedAt: old,
	}
	require.NoError(t, env.db.Create(failing).Error)

	env.queue.sweepTerminal()

	_, err := env.tasks.Get(ctx, failing.ID)
	require.Error(t, err, "old error beyond kept batch must be swept")
	kept, err := env.tasks.Get(ctx, dones[0].ID)
	require.NoError(t, err)
	assert.Equal(t, TranscodeTaskDone, kept.Status)
	keptLast, err := env.tasks.Get(ctx, dones[len(dones)-1].ID)
	require.NoError(t, err)
	assert.Equal(t, TranscodeTaskDone, keptLast.Status)
}

func TestTranscodeCancelMappings(t *testing.T) {
	runner := &fakeTranscodeRunner{}
	env := setupTranscodeTest(t, runner, false)
	env.queue.Stop()
	ctx := context.Background()

	mkTask := func(status string) uint64 {
		task := &models.TranscodeTask{SourcePath: "/q/x.mkv", Filename: "x.mkv", Status: status}
		require.NoError(t, env.tasks.Create(ctx, task))
		return uint64(task.ID)
	}

	// Done отменять нельзя.
	require.ErrorIs(t, env.queue.Cancel(mkTask(TranscodeTaskDone)), ErrTranscodeJobDone)
	// Cancelled — идемпотентный успех.
	cancelled := mkTask(TranscodeTaskQueued)
	require.NoError(t, env.queue.Cancel(cancelled))
	require.NoError(t, env.queue.Cancel(cancelled))
	// Error — отмена проходит, исходник удаляется (как и для queued:
	// от задания отказываются — файл ему больше не нужен, ретрай
	// после cancel невозможен).
	failedSrc := writeSource(t, env.quar, "failed.mkv", "data")
	failedTask := &models.TranscodeTask{SourcePath: failedSrc, Filename: "failed.mkv", Status: TranscodeTaskError}
	require.NoError(t, env.tasks.Create(ctx, failedTask))
	failed := uint64(failedTask.ID)
	require.NoError(t, env.queue.Cancel(failed))
	got, err := env.tasks.Get(ctx, uint(failed))
	require.NoError(t, err)
	assert.Equal(t, TranscodeTaskCancelled, got.Status)
	_, err = os.Stat(failedSrc)
	require.True(t, os.IsNotExist(err), "cancelled error task source must be removed")
	// Нет задания — NotFound.
	require.ErrorIs(t, env.queue.Cancel(999999), ErrTranscodeJobNotFound)
	// Retry принимает только error.
	require.ErrorIs(t, env.queue.Retry(mkTask(TranscodeTaskQueued)), ErrTranscodeJobNotFailed)
	require.ErrorIs(t, env.queue.Retry(999999), ErrTranscodeJobNotFound)
}

func TestTranscodeSameStemSubsDontClash(t *testing.T) {
	// film.mov и film.mkv оба ремуксятся в mp4 и делят stem "film":
	// сайдкары обязаны разойтись по media ID, а не перезаписать друг друга.
	runner := &fakeTranscodeRunner{}
	env := setupTranscodeTest(t, runner, false)
	runner.probe = ProbeResult{
		Container: "mov,mp4,m4a", HasVideo: true, VideoCodec: "h264", PixFmt: "yuv420p",
		VideoIndex: 0, Width: 1280, Height: 720,
		HasAudio: true, AudioCodecs: []string{"aac"}, DurationSec: 60,
		TextSubs: []SubTrack{{Index: 2, Codec: "subrip", Lang: "eng"}},
	}

	srcA := writeSource(t, env.quar, "film.mov", "content-a")
	idA, err := env.queue.Enqueue(srcA, "film.mov")
	require.NoError(t, err)
	stA := waitForTask(t, env.queue, idA, TranscodeTaskDone)

	runner.probe = ProbeResult{
		Container: "matroska,webm", HasVideo: true, VideoCodec: "h264", PixFmt: "yuv420p",
		VideoIndex: 0, Width: 1280, Height: 720,
		HasAudio: true, AudioCodecs: []string{"aac"}, DurationSec: 60,
		TextSubs: []SubTrack{{Index: 2, Codec: "subrip", Lang: "eng"}},
	}
	srcB := writeSource(t, env.quar, "film.mkv", "content-b")
	idB, err := env.queue.Enqueue(srcB, "film.mkv")
	require.NoError(t, err)
	stB := waitForTask(t, env.queue, idB, TranscodeTaskDone)

	subsA, err := env.queue.subs.ListByMedia(context.Background(), stA.MediaID)
	require.NoError(t, err)
	require.Len(t, subsA, 1)
	subsB, err := env.queue.subs.ListByMedia(context.Background(), stB.MediaID)
	require.NoError(t, err)
	require.Len(t, subsB, 1)
	require.NotEqual(t, subsA[0].Path, subsB[0].Path, "sidecars must not share a path")
	assert.Contains(t, subsA[0].Path, "film")
	assert.Contains(t, subsB[0].Path, "film")
	for _, p := range []string{subsA[0].Path, subsB[0].Path} {
		_, err := os.Stat(p)
		require.NoError(t, err, "both sidecars must exist")
	}
}

func TestTranscodeOrphanedOnMissingResultFile(t *testing.T) {
	runner := &fakeTranscodeRunner{}
	env := setupTranscodeTest(t, runner, true)
	env.queue.freeBytes = func(string) int64 { return 0 }
	ctx := context.Background()

	// Живая строка, но файла копии нет (удалён вручную) — orphaned,
	// авточистка оригинал не трогает.
	media := &models.Media{Title: "V", Type: models.MediaTypeVideo, FilePath: filepath.Join(env.library, "gone.mp4")}
	require.NoError(t, env.media.Create(ctx, media))
	src := writeSource(t, env.quar, "orig.mkv", "data")
	require.NoError(t, env.tasks.Create(ctx, &models.TranscodeTask{
		SourcePath: src, Filename: "orig.mkv", Status: TranscodeTaskDone, MediaID: media.ID,
	}))

	infos, err := env.queue.OriginalsStatus()
	require.NoError(t, err)
	require.Len(t, infos, 1)
	assert.Equal(t, "orphaned", infos[0].Status)

	require.ErrorIs(t, env.queue.EnsureSpaceForUpload(1<<30), ErrInsufficientSpace)
	_, err = os.Stat(src)
	require.NoError(t, err, "original with missing copy must not be evicted")
}

func TestTranscodeEarlyCancelCleansSource(t *testing.T) {
	// Окно между claim и перечитыванием: Cancel уже перевёл строку
	// в cancelled, воркер только стартует — исходник должен удалиться
	// здесь, а не ждать handleCancel (до него дело не дойдёт).
	runner := &fakeTranscodeRunner{}
	env := setupTranscodeTest(t, runner, false)
	env.queue.Stop()
	ctx := context.Background()

	src := writeSource(t, env.quar, "early.mkv", "data")
	task := &models.TranscodeTask{SourcePath: src, Filename: "early.mkv", Status: TranscodeTaskCancelled}
	require.NoError(t, env.tasks.Create(ctx, task))

	env.queue.process(task)

	_, err := os.Stat(src)
	require.True(t, os.IsNotExist(err), "early-cancelled source must be removed")
}

// gateTaskRepo душит записи воркера (payload processing), пропуская
// пользовательские (cancelled/queued/error): Cancel успевает
// закоммититься ровно в окне между чтением и условной записью воркера.
type gateTaskRepo struct {
	repository.TranscodeTaskRepository
	entered chan struct{}
	release chan struct{}
	once    sync.Once
}

func (g *gateTaskRepo) UpdateIfStatus(ctx context.Context, task *models.TranscodeTask, allowed ...string) (bool, error) {
	if task.Status == TranscodeTaskProcessing {
		g.once.Do(func() { close(g.entered) })
		<-g.release
	}
	return g.TranscodeTaskRepository.UpdateIfStatus(ctx, task, allowed...)
}

func TestTranscodeCancelBetweenHashAndSave(t *testing.T) {
	runner := &fakeTranscodeRunner{probe: ProbeResult{
		Container: "mov,mp4,m4a", HasVideo: true, VideoCodec: "h264",
		VideoIndex: 0, PixFmt: "yuv420p", Width: 1280, Height: 720,
		HasAudio: true, AudioCodecs: []string{"aac"}, DurationSec: 60,
	}}
	db := transcodeTestDB(t)
	mediaRepo := repository.NewMediaRepository(db)
	taskRepo := repository.NewTranscodeTaskRepository(db)
	subRepo := repository.NewSubtitleRepository(db)
	thumbSvc := NewThumbnailService(filepath.Join(t.TempDir(), "thumbs"))
	base := t.TempDir()
	quar := filepath.Join(base, "quar")
	library := filepath.Join(base, "library")
	tmp := filepath.Join(base, "tmp")
	for _, dir := range []string{quar, library, tmp} {
		require.NoError(t, os.MkdirAll(dir, 0755))
	}
	gate := &gateTaskRepo{
		TranscodeTaskRepository: taskRepo,
		entered:                 make(chan struct{}),
		release:                 make(chan struct{}),
	}
	queue := NewTranscodeQueue(context.Background(), TranscodeWorkerConfig{
		LibraryVideoDir: library,
		OriginalsDir:    quar,
		TempDir:         tmp,
	}, gate, mediaRepo, subRepo, thumbSvc, runner)
	t.Cleanup(queue.Stop)

	src := writeSource(t, quar, "race.mp4", "fake-content")
	id, err := queue.Enqueue(src, "race.mp4")
	require.NoError(t, err)

	// Воркер висит внутри первой условной записи — Cancel выигрывает окно.
	<-gate.entered
	require.NoError(t, queue.Cancel(id))
	close(gate.release)

	// Воркер просыпается, его запись проигрывает, исходник чистится.
	deadline := time.Now().Add(10 * time.Second)
	for {
		_, err := os.Stat(src)
		if os.IsNotExist(err) {
			break
		}
		require.NoError(t, err)
		if time.Now().After(deadline) {
			t.Fatal("source was not removed after lost race")
		}
		time.Sleep(20 * time.Millisecond)
	}

	task, err := taskRepo.Get(context.Background(), uint(id))
	require.NoError(t, err)
	assert.Equal(t, TranscodeTaskCancelled, task.Status)
	assert.Equal(t, 0, task.Attempts, "no spurious requeue after lost race")
}

// TestTranscodeRequeueInterruptedWakesWorker: после подбора зависших
// processing-заданий очередь будит воркера — обработка начинается сразу,
// а не через transcodePollInterval.
func TestTranscodeRequeueInterruptedWakesWorker(t *testing.T) {
	runner := &fakeTranscodeRunner{}
	env := setupTranscodeTest(t, runner, false)
	env.queue.Stop()
	// Сливаем возможные pending-сигналы, чтобы assert ниже видел
	// именно сигнал RequeueInterrupted.
	select {
	case <-env.queue.wake:
	default:
	}

	task := &models.TranscodeTask{SourcePath: "/gone/missing.mp4", Filename: "missing.mp4", Status: TranscodeTaskProcessing}
	require.NoError(t, env.tasks.Create(context.Background(), task))

	n, err := env.queue.RequeueInterrupted(context.Background())
	require.NoError(t, err)
	assert.Equal(t, int64(1), n)

	select {
	case <-env.queue.wake:
	default:
		t.Fatal("RequeueInterrupted обязан будить воркера")
	}
}

// TestTranscodeRequeueInterruptedNoWakeWhenEmpty: без зависших заданий
// будить некого — лишнего сигнала в канале нет.
func TestTranscodeRequeueInterruptedNoWakeWhenEmpty(t *testing.T) {
	runner := &fakeTranscodeRunner{}
	env := setupTranscodeTest(t, runner, false)
	env.queue.Stop()
	select {
	case <-env.queue.wake:
	default:
	}

	n, err := env.queue.RequeueInterrupted(context.Background())
	require.NoError(t, err)
	assert.Equal(t, int64(0), n)

	select {
	case <-env.queue.wake:
		t.Fatal("без зависших заданий wake-сигнала быть не должно")
	default:
	}
}
