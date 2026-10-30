package models

import "time"

// UploadTask — персистентная строка задания загрузки.
// In-memory очередь (services.UploadQueue) держала джобы только в
// карте: рестарт сервера молча терял летящие задания, клиент получал
// 404 на статусе. Теперь незавершённые строки переживают рестарт
// и перевыставляются в очередь при старте.
//
// Статусы — те же строки, что у in-memory джобов (queued/processing/
// done/error/duplicate); cancelled в БД не пишется (отмена удаляет
// строку). FileHash заполняется после хэширования и нужен для дедупа
// параллельных заливок одного контента; Force переживает рестарт,
// чтобы подтверждение пользователя не терялось.
type UploadTask struct {
	ID        uint64    `gorm:"primaryKey" json:"id"`
	FilePath  string    `gorm:"index" json:"file_path"`
	Filename  string    `json:"filename"`
	MediaType MediaType `gorm:"index;type:text" json:"media_type"`
	Status    string    `gorm:"index" json:"status"`
	Error     string    `json:"error,omitempty"`
	// MediaID — созданная запись, 0 пока не готова.
	MediaID uint `gorm:"index" json:"media_id,omitempty"`
	// FileHash — sha256 файла, заполняется после хэширования.
	// По нему ловится повторная заливка того же контента, пока
	// задание ещё активно.
	FileHash string `gorm:"index" json:"-"`
	// Force — пропустить проверку похожих картинок (подтверждено
	// пользователем). Точный хэш всё равно проверяется.
	Force bool `json:"-"`
	// Duplicate-инфо для статуса duplicate: id и название похожего мема.
	DuplicateMediaID uint      `json:"duplicate_media_id,omitempty"`
	DuplicateTitle   string    `json:"duplicate_title,omitempty"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}
