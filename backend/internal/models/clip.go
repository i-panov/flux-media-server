package models

import "time"

const (
	ClipQueued     = "queued"
	ClipProcessing = "processing"
	ClipDone       = "done"
	ClipError      = "error"
)

// ClipTask — задача обрезки фрагмента медиа. Оригинал не изменяется:
// создаётся новая медиазапись со ссылкой на источник.
type ClipTask struct {
	ID            uint    `gorm:"primaryKey" json:"id"`
	SourceMediaID uint    `gorm:"index;not null" json:"source_media_id"`
	StartSeconds  float64 `json:"start_seconds"`
	EndSeconds    float64 `json:"end_seconds"`
	Title         string  `json:"title"`
	Status        string  `gorm:"index" json:"status"`
	Progress      float64 `json:"progress"`
	Error         string  `json:"error,omitempty"`
	OutputMediaID uint    `json:"output_media_id,omitempty"`
	// ID задач обработки, чтобы отмена останавливала и их, а не только
	// ожидание. Без них transcode/upload продолжали создавать медиа.
	TranscodeJobID uint64    `json:"-"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}
