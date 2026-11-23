package models

import "time"

const (
	ThumbnailTaskQueued     = "queued"
	ThumbnailTaskProcessing = "processing"
	ThumbnailTaskDone       = "done"
	ThumbnailTaskError      = "error"

	ThumbnailKindThumb = "thumbnail"
	ThumbnailKindCover = "cover"
)

// ThumbnailTask — постоянная очередь генерации превью и обложек: задача
// переживает рестарт и продолжается воркером.
type ThumbnailTask struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	MediaID   uint      `gorm:"not null;uniqueIndex:idx_thumbnail_task" json:"media_id"`
	Kind      string    `gorm:"not null;uniqueIndex:idx_thumbnail_task" json:"kind"`
	Status    string    `gorm:"index;not null" json:"status"`
	Error     string    `json:"error,omitempty"`
	Attempts  int       `json:"attempts"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
