package models

import (
	"time"
)

// TranscodeTask — задание нормализации видео из карантина в библиотеку.
// В отличие от in-memory очередей загрузок/извлечения, строка живёт в БД:
// транскод идёт часами, и рестарт сервера не должен терять задание —
// зависшие в processing возвращаются в queued при старте.
//
// Значения Status — константы TranscodeTask* из services (модели не
// импортируют services во избежание цикла).
type TranscodeTask struct {
	ID         uint   `gorm:"primaryKey" json:"id"`
	SourcePath string `gorm:"index" json:"-"`
	Filename   string `json:"filename"`
	// SourceHash — sha256 исходника, заполняется после хэширования.
	// По нему ловится повторная заливка того же файла, пока задание
	// ещё активно (у результата хэш уже другой).
	SourceHash string `gorm:"index" json:"-"`
	Status     string `gorm:"index" json:"status"`
	// Progress — 0..100, Speed — последний множитель скорости ffmpeg.
	Progress int     `json:"progress"`
	Speed    float64 `json:"speed"`
	// ErrorMsg — хвост stderr ffmpeg для диагностики в админке.
	// Пути ФС в API не уходят: сообщение формируется без них.
	ErrorMsg string `gorm:"type:text" json:"error,omitempty"`
	Attempts int    `json:"attempts"`
	// MediaID — созданная запись результата, 0 пока не готово.
	MediaID uint `gorm:"index" json:"media_id,omitempty"`
	// DurationSecs — длительность из probe, нужна для процентов и ETA.
	DurationSecs float64   `json:"-"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}
