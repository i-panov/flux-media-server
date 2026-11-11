package models

import "time"

// Setting — персистентная настройка уровня инстанса (key/value).
// В отличие от конфига YAML, меняется из админки без рестарта сервера.
type Setting struct {
	Key       string    `gorm:"primaryKey;size:255" json:"key"`
	Value     string    `json:"value"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (Setting) TableName() string {
	return "settings"
}
