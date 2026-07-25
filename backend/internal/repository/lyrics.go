package repository

import (
	"context"

	"flux/internal/models"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type LyricsStore struct {
	db *gorm.DB
}

func NewLyricsRepository(db *gorm.DB) *LyricsStore {
	return &LyricsStore{db: db}
}

func (r *LyricsStore) FindByMediaID(ctx context.Context, mediaID uint) (*models.Lyrics, error) {
	var lyrics models.Lyrics
	err := r.db.WithContext(ctx).Where("media_id = ?", mediaID).First(&lyrics).Error
	return &lyrics, err
}

func (r *LyricsStore) Upsert(ctx context.Context, lyrics *models.Lyrics) error {
	return r.db.WithContext(ctx).Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "media_id"}},
		DoUpdates: clause.AssignmentColumns([]string{"lyrics_text", "translation", "sync_data", "source", "updated_at"}),
	}).Create(lyrics).Error
}

func (r *LyricsStore) Delete(ctx context.Context, mediaID uint) error {
	return r.db.WithContext(ctx).Where("media_id = ?", mediaID).Delete(&models.Lyrics{}).Error
}
