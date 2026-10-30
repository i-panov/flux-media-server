package models

import "time"

// ExtractTask — персистентная строка задания извлечения аудио.
// In-memory очередь (services.ExtractService) держала джобы только в
// карте: рестарт сервера молча терял летящие задания, клиент вечно
// опрашивал несуществующий id. Теперь незавершённые строки
// переживают рестарт и перевыставляются в очередь при старте.
//
// Статусы — те же строки, что у in-memory джобов (queued/processing/
// done/error); cancelled в БД не пишется (отмена удаляет строку).
type ExtractTask struct {
	ID            uint   `gorm:"primaryKey" json:"id"`
	SourceMediaID uint   `gorm:"index" json:"source_media_id"`
	Status        string `gorm:"index" json:"status"`
	Error         string `json:"error,omitempty"`
	// MediaID — созданный трек, 0 пока не готово.
	MediaID   uint      `gorm:"index" json:"media_id,omitempty"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
