package services

import (
	"context"
	"fmt"
	"log"

	"flux/internal/repository"
)

const thumbnailBackfillBatch = 100
const thumbnailBackfillMaxBatches = 20

// BackfillAudioCovers извлекает встроенные обложки у старых аудиофайлов.
// cover_attempted не даёт повторять ffmpeg на каждом старте.
func BackfillAudioCovers(ctx context.Context, mediaRepo repository.MediaRepository, thumbSvc *ThumbnailService) int {
	generated := 0
	for batch := 0; batch < thumbnailBackfillMaxBatches; batch++ {
		if ctx.Err() != nil {
			return generated
		}
		rows, err := mediaRepo.FindAudioMissingCover(ctx, thumbnailBackfillBatch)
		if err != nil {
			log.Printf("cover backfill: list: %v", err)
			return generated
		}
		if len(rows) == 0 {
			return generated
		}
		for _, media := range rows {
			if ctx.Err() != nil {
				return generated
			}
			if thumbSvc.ExtractCoverContext(ctx, media.ID, media.FilePath) != "" {
				if err := mediaRepo.UpdateCoverURL(ctx, media.ID, fmt.Sprintf("/api/media/%d/cover", media.ID)); err == nil {
					generated++
				}
			}
			if err := mediaRepo.SetCoverAttempted(ctx, media.ID, true); err != nil {
				log.Printf("cover backfill: mark %d: %v", media.ID, err)
			}
		}
		if len(rows) < thumbnailBackfillBatch {
			return generated
		}
	}
	return generated
}

// BackfillThumbnails генерирует недостающие превью для уже существующих
// видео/картинок. Только фоном: ffmpeg на каждый файл не должен
// задерживать старт сервера или HTTP-запросы.
func BackfillThumbnails(ctx context.Context, mediaRepo repository.MediaRepository, thumbSvc *ThumbnailService) int {
	generated := 0
	lastID := uint(0)
	// Без верхнего предела по числу батчей: большие библиотеки должны
	// доходить до конца. Ограничение — контекст (отмена/остановка).
	for {
		if ctx.Err() != nil {
			return generated
		}
		rows, err := mediaRepo.FindThumbnailCandidates(ctx, lastID, thumbnailBackfillBatch)
		if err != nil {
			log.Printf("thumb backfill: list: %v", err)
			return generated
		}
		if len(rows) == 0 {
			return generated
		}
		for _, media := range rows {
			if ctx.Err() != nil {
				return generated
			}
			lastID = media.ID
			// Файл есть, даже если URL потерян — достаточно восстановить URL.
			if thumbSvc.Exists(media.ID) {
				if media.ThumbnailURL == "" {
					if err := mediaRepo.UpdateThumbnailURL(ctx, media.ID,
						fmt.Sprintf("/api/media/%d/thumb", media.ID)); err != nil {
						log.Printf("thumb backfill: restore url %d: %v", media.ID, err)
					}
				}
				continue
			}
			if thumbSvc.GenerateWithContext(ctx, media.ID, media.FilePath) == "" {
				continue
			}
			url := fmt.Sprintf("/api/media/%d/thumb", media.ID)
			if err := mediaRepo.UpdateThumbnailURL(ctx, media.ID, url); err != nil {
				log.Printf("thumb backfill: update %d: %v", media.ID, err)
				continue
			}
			generated++
		}
		if len(rows) < thumbnailBackfillBatch {
			return generated
		}
	}
}
