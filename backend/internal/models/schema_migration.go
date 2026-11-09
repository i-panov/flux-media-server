package models

import "time"

// SchemaMigration фиксирует применённые версии ad-hoc миграций.
// AutoMigrate создаёт структуру таблиц, а версия защищает от повторного
// выполнения неидемпотентных шагов после отката/обрыва.
type SchemaMigration struct {
	Version   uint      `gorm:"primaryKey" json:"version"`
	AppliedAt time.Time `json:"applied_at"`
}
