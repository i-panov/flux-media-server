package services

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"flux/internal/models"
	"flux/internal/repository"
)

// ClipService режет фрагмент из медиа и создаёт новую запись. Оригинал
// не изменяется, поэтому пользователь может отменить эксперимент.
type ClipService struct {
	clips     *repository.ClipStore
	media     repository.MediaRepository
	originals string
	transcode transcodeEnqueuer
	upload    uploadEnqueuer

	// slots ограничивает одновременные ffmpeg: без него серия запросов
	// запускала N кодировщиков и выедала CPU/диск.
	slots chan struct{}

	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup

	mu      sync.Mutex
	running map[uint]context.CancelFunc
}

// ErrClipBusy — уже идёт максимальное число нарезок: новая получает 429,
// а не встаёт в бесконечную очередь фоновых ffmpeg.
var ErrClipBusy = errors.New("clip queue is busy")

// Ошибки валидации: их текст безопасно отдавать клиенту.
var (
	ErrClipInvalidRange = errors.New("invalid clip range")
	ErrClipUnsupported  = errors.New("only video and audio can be trimmed")
)

const maxConcurrentClips = 1

func NewClipService(clips *repository.ClipStore, media repository.MediaRepository, originals string, transcode transcodeEnqueuer, upload uploadEnqueuer) *ClipService {
	ctx, cancel := context.WithCancel(context.Background())
	return &ClipService{
		clips: clips, media: media, originals: originals,
		transcode: transcode, upload: upload,
		slots:   make(chan struct{}, maxConcurrentClips),
		running: make(map[uint]context.CancelFunc),
		ctx:     ctx,
		cancel:  cancel,
	}
}

// Stop отменяет активные нарезки, ждёт их завершения и чистит временные
// файлы. Без этого Shutdown закрывал БД под работающим ffmpeg.
func (s *ClipService) Stop() {
	s.cancel()
	s.wg.Wait()
	s.removeTempFiles()
}

func (s *ClipService) removeTempFiles() {
	entries, err := os.ReadDir(s.originals)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasPrefix(entry.Name(), ".clip-") {
			continue
		}
		_ = os.Remove(filepath.Join(s.originals, entry.Name()))
	}
}

const (
	minClipSeconds = 0.5
	maxClipSeconds = 6 * 3600
)

func (s *ClipService) Start(ctx context.Context, mediaID uint, start, end float64, title string) (*models.ClipTask, error) {
	if start < 0 || end <= start {
		return nil, fmt.Errorf("%w: end must be after start", ErrClipInvalidRange)
	}
	if end-start < minClipSeconds {
		return nil, fmt.Errorf("%w: clip is too short", ErrClipInvalidRange)
	}
	if end-start > maxClipSeconds {
		return nil, fmt.Errorf("%w: clip is too long", ErrClipInvalidRange)
	}
	source, err := s.media.FindByID(ctx, mediaID)
	if err != nil {
		return nil, err
	}
	if source.Type != models.MediaTypeVideo && source.Type != models.MediaTypeAudio {
		return nil, ErrClipUnsupported
	}
	if source.Duration > 0 && end > float64(source.Duration)+1 {
		return nil, fmt.Errorf("%w: clip is outside the media duration", ErrClipInvalidRange)
	}
	if strings.TrimSpace(title) == "" {
		title = fmt.Sprintf("%s — фрагмент", source.Title)
	}
	// Занимаем слот до создания задачи: лишний запрос не должен оставлять
	// в БД queued-строку, которую некому обработать.
	select {
	case s.slots <- struct{}{}:
	default:
		return nil, ErrClipBusy
	}
	acquired := true
	defer func() {
		if acquired {
			<-s.slots
		}
	}()
	task := &models.ClipTask{
		SourceMediaID: mediaID,
		StartSeconds:  start,
		EndSeconds:    end,
		Title:         strings.TrimSpace(title),
		Status:        models.ClipQueued,
	}
	if err := s.clips.Create(ctx, task); err != nil {
		return nil, err
	}
	// Задача переживает HTTP-запрос: отмена — только через Cancel() или Stop().
	runCtx, cancel := context.WithCancel(s.ctx)
	s.mu.Lock()
	s.running[task.ID] = cancel
	s.mu.Unlock()
	s.wg.Add(1)
	//nolint:gosec // фоновая задача пишет статус через отдельный контекст.
	go func() {
		defer s.wg.Done()
		s.run(runCtx, task, source)
	}()
	acquired = false
	return task, nil
}

// RecoverStale помечает незавершённые задачи ошибкой после рестарта.
func (s *ClipService) RecoverStale(ctx context.Context) error {
	// Временные файлы прошлого процесса продолжать некому.
	s.removeTempFiles()
	tasks, err := s.clips.ListActive(ctx)
	if err != nil {
		return err
	}
	for _, task := range tasks {
		if task.Status == models.ClipQueued || task.Status == models.ClipProcessing {
			// Дочерняя задача transcode/upload могла пережить рестарт —
			// её результат останется сиротой без записи клипа.
			if task.TranscodeJobID != 0 {
				if source, err := s.media.FindByID(ctx, task.SourceMediaID); err == nil {
					if source.Type == models.MediaTypeVideo {
						_ = s.transcode.Cancel(task.TranscodeJobID)
					} else {
						_ = s.upload.Cancel(task.TranscodeJobID)
					}
				}
			}
			if err := s.clips.Update(ctx, task.ID, map[string]any{
				"status": models.ClipError, "error": "прервано перезапуском сервера",
			}); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *ClipService) Cancel(id uint) bool {
	s.mu.Lock()
	cancel, running := s.running[id]
	s.mu.Unlock()
	if running {
		cancel()
	}
	task, err := s.clips.Get(context.Background(), id)
	if err != nil {
		return false
	}
	cancelled, err := s.clips.CancelActive(context.Background(), id)
	if err != nil {
		// Не маскируем сбой БД под «задача не найдена».
		return false
	}
	if !cancelled && task.Status != models.ClipError {
		// Задача уже завершилась (done) — отменять нечего.
		return false
	}
	if !cancelled && task.Error != "cancelled" {
		// Ошибка не из-за отмены — не выдаём её за успешную отмену.
		return false
	}
	// Даже если run уже записал cancelled, обработку ниже всё равно
	// останавливаем: иначе transcode/upload продолжат создавать медиа.
	task, err = s.clips.Get(context.Background(), id)
	if err != nil {
		return true
	}
	if task.TranscodeJobID != 0 {
		if source, err := s.media.FindByID(context.Background(), task.SourceMediaID); err == nil {
			if source.Type == models.MediaTypeVideo {
				_ = s.transcode.Cancel(task.TranscodeJobID)
			} else {
				_ = s.upload.Cancel(task.TranscodeJobID)
			}
		}
	}
	return true
}

func (s *ClipService) run(ctx context.Context, task *models.ClipTask, source *models.Media) {
	defer func() {
		<-s.slots
		s.mu.Lock()
		delete(s.running, task.ID)
		s.mu.Unlock()
	}()
	_ = s.clips.Update(ctx, task.ID, map[string]any{
		"status": models.ClipProcessing, "progress": 10,
	})
	if err := os.MkdirAll(s.originals, 0o750); err != nil {
		s.fail(task, err)
		return
	}
	ext := ".mp4"
	if source.Type == models.MediaTypeAudio {
		ext = ".m4a"
	}
	tmp, err := os.CreateTemp(s.originals, ".clip-*"+ext)
	if err != nil {
		s.fail(task, err)
		return
	}
	outPath := tmp.Name()
	_ = tmp.Close()

	args := s.ffmpegArgs(source, task, outPath)
	// Таймаут пропорционален длине фрагмента: зависший ffmpeg не держит
	// слот вечно, но длинный фрагмент успевает обработаться.
	ffmpegTimeout := time.Duration(task.EndSeconds-task.StartSeconds)*time.Second*3 + 5*time.Minute
	ffmpegCtx, cancelFFmpeg := context.WithTimeout(ctx, ffmpegTimeout)
	defer cancelFFmpeg()
	cmd := exec.CommandContext(ffmpegCtx, "ffmpeg", args...)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		_ = os.Remove(outPath)
		if ctx.Err() != nil {
			_ = s.clips.Update(context.Background(), task.ID, map[string]any{
				"status": models.ClipError, "error": "cancelled",
			})
			return
		}
		s.fail(task, fmt.Errorf("ffmpeg: %s", tail(stderr.String(), 400)))
		return
	}
	_ = s.clips.Update(ctx, task.ID, map[string]any{"progress": 60})

	finalName := safeClipFilename(task.Title, ext)
	finalPath := uniqueLoaderPath(s.originals, finalName)
	if err := os.Rename(outPath, finalPath); err != nil {
		_ = os.Remove(outPath)
		s.fail(task, err)
		return
	}

	var mediaID uint
	if source.Type == models.MediaTypeVideo {
		jobID, err := s.transcode.Enqueue(finalPath, filepath.Base(finalPath))
		if err != nil {
			_ = os.Remove(finalPath)
			s.fail(task, err)
			return
		}
		_ = s.clips.Update(ctx, task.ID, map[string]any{"transcode_job_id": jobID})
		task.TranscodeJobID = jobID
		if ctx.Err() != nil {
			_ = s.transcode.Cancel(jobID)
			return
		}
		mediaID = s.waitTranscode(ctx, jobID)
	} else {
		jobID, err := s.upload.Enqueue(UploadJobInput{
			FilePath: finalPath, Filename: filepath.Base(finalPath),
			MediaType: models.MediaTypeAudio,
		})
		if err != nil {
			_ = os.Remove(finalPath)
			s.fail(task, err)
			return
		}
		_ = s.clips.Update(ctx, task.ID, map[string]any{"transcode_job_id": jobID})
		task.TranscodeJobID = jobID
		if ctx.Err() != nil {
			_ = s.upload.Cancel(jobID)
			return
		}
		mediaID = s.waitUpload(ctx, jobID)
	}
	if mediaID == 0 {
		if ctx.Err() != nil {
			_ = s.clips.Update(context.Background(), task.ID, map[string]any{
				"status": models.ClipError, "error": "cancelled",
			})
			return
		}
		s.fail(task, fmt.Errorf("media was not created"))
		return
	}
	_ = s.media.SetClipSourceMediaID(context.Background(), mediaID, source.ID)
	_, _ = s.media.PatchMetadata(context.Background(), mediaID, repository.MetadataPatch{
		Title: &task.Title,
	})
	_ = s.clips.Update(context.Background(), task.ID, map[string]any{
		"status": models.ClipDone, "progress": 100, "output_media_id": mediaID,
	})
}

func (s *ClipService) ffmpegArgs(source *models.Media, task *models.ClipTask, out string) []string {
	duration := task.EndSeconds - task.StartSeconds
	args := []string{"-y", "-ss", fmt.Sprintf("%.3f", task.StartSeconds), "-i", source.FilePath,
		"-t", fmt.Sprintf("%.3f", duration)}
	if source.Type == models.MediaTypeAudio {
		if strings.EqualFold(filepath.Ext(source.FilePath), ".mp3") {
			args = append(args, "-vn", "-c:a", "copy", out)
		} else {
			args = append(args, "-vn", "-c:a", "aac", "-b:a", "192k", out)
		}
		return args
	}
	args = append(args, "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
		"-c:a", "aac", "-movflags", "+faststart", out)
	return args
}

func (s *ClipService) waitTranscode(ctx context.Context, id uint64) uint {
	deadline := time.Now().Add(2 * time.Hour)
	for time.Now().Before(deadline) {
		if ctx.Err() != nil {
			return 0
		}
		if snap, ok := s.transcode.Get(id); ok {
			switch snap.Status {
			case TranscodeTaskDone:
				return snap.MediaID
			case TranscodeTaskError, TranscodeTaskCancelled:
				return 0
			}
		}
		time.Sleep(2 * time.Second)
	}
	return 0
}

func (s *ClipService) waitUpload(ctx context.Context, id uint64) uint {
	deadline := time.Now().Add(30 * time.Minute)
	for time.Now().Before(deadline) {
		if ctx.Err() != nil {
			return 0
		}
		if snap, ok := s.upload.Status(id); ok {
			switch snap.Status {
			case UploadJobDone:
				return snap.MediaID
			case UploadJobError, UploadJobDuplicate:
				return 0
			}
		}
		time.Sleep(time.Second)
	}
	return 0
}

func (s *ClipService) fail(task *models.ClipTask, err error) {
	log.Printf("clip %d: %v", task.ID, err)
	_ = s.clips.Update(context.Background(), task.ID, map[string]any{
		"status": models.ClipError, "error": err.Error(),
	})
}

func safeClipFilename(title, ext string) string {
	title = strings.TrimSpace(title)
	if title == "" {
		title = "clip"
	}
	replacer := strings.NewReplacer("/", "-", "\\", "-", ":", "-", "\x00", "")
	title = replacer.Replace(title)
	// Обрезаем по рунам: байтовый срез мог разрезать UTF-8 и оставить
	// битое имя в файловой системе и JSON.
	if runes := []rune(title); len(runes) > 120 {
		title = string(runes[:120])
	}
	return fmt.Sprintf("%s-%d%s", title, time.Now().UnixNano(), ext)
}

func tail(s string, limit int) string {
	s = strings.TrimSpace(s)
	if len(s) <= limit {
		return s
	}
	return s[len(s)-limit:]
}
