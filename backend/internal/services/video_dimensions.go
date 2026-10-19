package services

import (
	"context"
	"log"
	"os"
	"time"

	"flux/internal/models"
	"flux/internal/repository"
)

// Видео без размеров кадра заполняется сразу при скане и загрузке, но
// записи, созданные до появления колонок width/height, остаются с нулями
// навсегда: их файлы не менялись, поэтому обычный скан по quick-hash их
// пропускает. Клиенту размеры нужны до старта воспроизведения (по ним
// выбирается ориентация fullscreen и пропорции превью), поэтому при старте
// сервера делается один проход ffprobe по таким записям.
const (
	// dimensionsBackfillBatch — размер порции выборки: держим БД-курсор
	// коротким, чтобы отмена по ctx не держала в памяти всю выборку.
	dimensionsBackfillBatch = 50
	// dimensionsBackfillTimeout на весь проход. На каждый файл уходит
	// ProbeURL со своим 10-секундным таймаутом внутри экстрактора, здесь
	// нужен общий предел: старт сервера не должен висеть из-за одного
	// подвисшего ffprobe.
	dimensionsBackfillTimeout = 10 * time.Minute
	// dimensionsProbeTimeout на один файл.
	dimensionsProbeTimeout = 15 * time.Second
)

// BackfillVideoDimensions однократно добирает width/height для видео,
// где они ещё не записаны, и возвращает число обновлённых записей.
//
// Идемпотентен и безопасен для повторного вызова: записи с уже
// проставленными размерами не трогаются, а файлы, которые ffprobe не смог
// прочитать, остаются с нулями и просто переспрашиваются при следующем
// старте. Ошибки отдельных файлов не прерывают проход.
func BackfillVideoDimensions(ctx context.Context, mediaRepo repository.MediaRepository) int {
	ctx, cancel := context.WithTimeout(ctx, dimensionsBackfillTimeout)
	defer cancel()

	extract := NewMetadataExtractor()
	updated := 0

	for {
		media, err := mediaRepo.FindVideosMissingDimensions(ctx, dimensionsBackfillBatch)
		if err != nil {
			if ctx.Err() == nil {
				log.Printf("dimensions: выборка не разобранных записей: %v", err)
			}
			return updated
		}
		if len(media) == 0 {
			return updated
		}

		batchUpdated := 0
		for i := range media {
			if ctx.Err() != nil {
				log.Printf("dimensions: бэкфилл прерван после %d записей: %v", updated, ctx.Err())
				return updated
			}
			if backfillOne(ctx, &media[i], mediaRepo, extract) {
				updated++
				batchUpdated++
			}
		}

		// Порция ничего не обновила — дальше идти незачем: нечитаемые
		// файлы остаются нечитаемыми, и следующая выборка вернёт тот же
		// набор ID. Без этой проверки полный батч битых файлов крутил бы
		// цикл до истечения общего таймаута.
		if batchUpdated == 0 {
			log.Printf("dimensions: порция из %d записей не разобрана ffprobe, "+
				"останавливаюсь (залито всего %d)", len(media), updated)
			return updated
		}
	}
}

// backfillOne заполняет размеры одной записи. Отсутствующий файл и
// нечитаемый контейнер — не ошибка прохода: запись просто остаётся
// незаполненной до следующего запуска.
func backfillOne(
	ctx context.Context,
	media *models.Media,
	mediaRepo repository.MediaRepository,
	extract *MetadataExtractor,
) bool {
	if _, err := os.Stat(media.FilePath); err != nil {
		return false
	}

	// Probe наследует отмену общего контекста: остановка сервера или
	// истечение общего таймаута прерывают текущий файл, а не дожидаются
	// его конца. Собственный таймаут короче общего — «висящий» ffprobe
	// не должен съедать весь бюджет прохода.
	probeCtx, cancel := context.WithTimeout(ctx, dimensionsProbeTimeout)
	defer cancel()

	meta := extract.ExtractFromFileContext(probeCtx, media.FilePath)
	if meta == nil || meta.Width <= 0 || meta.Height <= 0 {
		return false
	}

	// Пишем ТОЛЬКО размеры (UpdateDimensions), а не через общий
	// Update: Update работает с ассоциациями артистов, а эта запись
	// прочитана без Preload — связи видео с артистами стёрлись бы.
	//
	// Контекст записи — общий, не probeCtx: probe уже отработал, и его
	// собственный таймаут мог истечь ровно в этот момент, сорвав
	// короткую запись в SQLite.
	if err := mediaRepo.UpdateDimensions(
		ctx, media.ID, meta.Width, meta.Height,
	); err != nil {
		log.Printf("dimensions: не сохранил %d (%s): %v", media.ID, media.FilePath, err)
		return false
	}
	return true
}
