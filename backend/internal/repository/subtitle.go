package repository

import (
	"context"

	"flux/internal/models"

	"gorm.io/gorm"
)

type SubtitleStore struct {
	db *gorm.DB
}

func NewSubtitleRepository(db *gorm.DB) *SubtitleStore {
	return &SubtitleStore{db: db}
}

func (r *SubtitleStore) ListByMedia(ctx context.Context, mediaID uint) ([]models.Subtitle, error) {
	var subs []models.Subtitle
	err := r.db.WithContext(ctx).Where("media_id = ?", mediaID).Order("lang").Find(&subs).Error
	return subs, err
}

// ReplaceForMedia заменяет набор дорожек медиа целиком: старые строки
// удаляются, новые создаются в одной транзакции. Пустой список —
// просто очистка (файл без текстовых субтитров).
func (r *SubtitleStore) ReplaceForMedia(ctx context.Context, mediaID uint, subs []models.Subtitle) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("media_id = ?", mediaID).Delete(&models.Subtitle{}).Error; err != nil {
			return err
		}
		for i := range subs {
			subs[i].MediaID = mediaID
			if err := tx.Create(&subs[i]).Error; err != nil {
				return err
			}
		}
		return nil
	})
}

func (r *SubtitleStore) DeleteByMedia(ctx context.Context, mediaID uint) error {
	return r.db.WithContext(ctx).Where("media_id = ?", mediaID).Delete(&models.Subtitle{}).Error
}
