package services

import (
	"context"
	"fmt"
	"log"

	"flux/internal/repository"
)

const thumbnailBackfillBatch = 100
const thumbnailBackfillMaxBatches = 20

// BackfillThumbnails генерирует недостающие превью для уже существующих
// видео/картинок. Только фоном: ffmpeg на каждый файл не должен
// задерживать старт сервера или HTTP-запросы.
func BackfillThumbnails(ctx context.Context, mediaRepo repository.MediaRepository, thumbSvc *ThumbnailService) int {
	generated := 0
	seen := map[uint]bool{}
	for batch := 0; batch < thumbnailBackfillMaxBatches; batch++ {
		if ctx.Err() != nil {
			return generated
		}
		rows, err := mediaRepo.FindMissingThumbnails(ctx, thumbnailBackfillBatch)
		if err != nil {
			log.Printf("thumb backfill: list: %v", err)
			return generated
		}
		if len(rows) == 0 {
			return generated
		}
		newInBatch := 0
		for _, media := range rows {
			if ctx.Err() != nil {
				return generated
			}
			if seen[media.ID] {
				continue
			}
			seen[media.ID] = true
			newInBatch++
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
		if len(rows) < thumbnailBackfillBatch || newInBatch == 0 {
			return generated
		}
	}
	return generated
}
