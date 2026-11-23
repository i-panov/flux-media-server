package services

import (
	"context"
	"log"
	"strconv"

	"flux/internal/models"
	"flux/internal/repository"
)

// ThumbnailQueueService — постоянная очередь превью и обложек.
// Задания лежат в БД, поэтому рестарт не теряет очередь: при старте
// приложения незавершённые задачи продолжаются тем же воркером.
type ThumbnailQueueService struct {
	tasks *repository.ThumbnailStore
	media repository.MediaRepository
	thumb *ThumbnailService
}

func NewThumbnailQueueService(tasks *repository.ThumbnailStore, media repository.MediaRepository, thumb *ThumbnailService) *ThumbnailQueueService {
	return &ThumbnailQueueService{tasks: tasks, media: media, thumb: thumb}
}

// EnqueueMissing ставит в очередь всё, чему не хватает превью или обложки.
func (s *ThumbnailQueueService) EnqueueMissing(ctx context.Context, kind string) error {
	if err := s.tasks.ResetFinished(ctx, kind); err != nil {
		return err
	}
	if kind == models.ThumbnailKindCover {
		for {
			rows, err := s.media.FindAudioMissingCover(ctx, thumbnailBackfillBatch)
			if err != nil {
				return err
			}
			if len(rows) == 0 {
				return nil
			}
			for _, media := range rows {
				if err := s.tasks.Enqueue(ctx, media.ID, kind); err != nil {
					return err
				}
			}
			if len(rows) < thumbnailBackfillBatch {
				return nil
			}
		}
	}
	lastID := uint(0)
	for {
		rows, err := s.media.FindThumbnailCandidates(ctx, lastID, thumbnailBackfillBatch)
		if err != nil {
			return err
		}
		if len(rows) == 0 {
			return nil
		}
		for _, media := range rows {
			lastID = media.ID
			if err := s.tasks.Enqueue(ctx, media.ID, kind); err != nil {
				return err
			}
		}
		if len(rows) < thumbnailBackfillBatch {
			return nil
		}
	}
}

// Run обрабатывает очередь до конца и возвращает счётчики.
func (s *ThumbnailQueueService) Run(ctx context.Context, kind string) (int, int) {
	generated, failed := 0, 0
	for {
		if ctx.Err() != nil {
			return generated, failed
		}
		task, err := s.tasks.NextQueued(ctx)
		if err != nil {
			return generated, failed
		}
		if task.Kind != kind {
			// Чужая очередь (превью vs обложки): возвращаем и выходим,
			// следующий запуск продолжит свою.
			_ = s.tasks.Finish(ctx, task.ID, models.ThumbnailTaskQueued, "")
			return generated, failed
		}
		media, err := s.media.FindByID(ctx, task.MediaID)
		if err != nil {
			failed++
			_ = s.tasks.Finish(ctx, task.ID, models.ThumbnailTaskError, "media not found")
			continue
		}
		ok := false
		if kind == models.ThumbnailKindThumb {
			ok = s.processThumbnail(ctx, media)
		} else {
			ok = s.processCover(ctx, media)
		}
		if ok {
			generated++
			_ = s.tasks.Finish(ctx, task.ID, models.ThumbnailTaskDone, "")
		} else {
			failed++
			_ = s.tasks.Finish(ctx, task.ID, models.ThumbnailTaskError, "generation failed")
		}
	}
}

func (s *ThumbnailQueueService) processThumbnail(ctx context.Context, media *models.Media) bool {
	if s.thumb.Exists(media.ID) {
		return true
	}
	url := s.thumb.GenerateWithContext(ctx, media.ID, media.FilePath)
	if url == "" {
		log.Printf("thumbnail queue: generation failed for %d", media.ID)
		return false
	}
	if err := s.media.UpdateThumbnailURL(ctx, media.ID, url); err != nil {
		log.Printf("thumbnail queue: save url for %d: %v", media.ID, err)
		return false
	}
	return true
}

func (s *ThumbnailQueueService) processCover(ctx context.Context, media *models.Media) bool {
	if s.thumb.ExtractCoverContext(ctx, media.ID, media.FilePath) == "" {
		_ = s.media.SetCoverAttempted(ctx, media.ID, true)
		return false
	}
	if err := s.media.UpdateCoverURL(ctx, media.ID, "/api/media/"+strconv.FormatUint(uint64(media.ID), 10)+"/cover"); err != nil {
		return false
	}
	_ = s.media.SetCoverAttempted(ctx, media.ID, true)
	return true
}

// Resume продолжает незавершённые задачи обоих видов после рестарта.
func (s *ThumbnailQueueService) Resume(ctx context.Context) {
	for _, kind := range []string{models.ThumbnailKindThumb, models.ThumbnailKindCover} {
		pending, err := s.tasks.Pending(ctx, kind)
		if err != nil || pending == 0 {
			continue
		}
		log.Printf("thumbnail queue: resuming %d %s tasks", pending, kind)
		s.Run(ctx, kind)
	}
}
