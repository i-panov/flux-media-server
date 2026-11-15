package models

import (
	"time"
)

// Subtitle — текстовая субтитровая дорожка (WebVTT-сайдкар рядом
// с файлом). Bitmap-дорожки (PGS/VobSub) здесь не хранятся: браузер
// их не показывает, они остаются внутри контейнера для VLC/скачивания.
type Subtitle struct {
	ID      uint   `gorm:"primaryKey" json:"id"`
	MediaID uint   `gorm:"index;uniqueIndex:idx_subtitles_media_lang" json:"media_id"`
	Lang    string `gorm:"uniqueIndex:idx_subtitles_media_lang" json:"lang"`
	Path    string `json:"-"`
	// FK-ассоциация с каскадным удалением, как у Lyrics.
	Media     *Media    `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
