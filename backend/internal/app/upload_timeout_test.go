package app

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

// Регрессия: глобальный ReadTimeout 10 с рвал чтение тела больших
// загрузок (клиент видел Connection reset by peer / Write failed).
// Upload-роуты обязаны получать время, достаточное для прокачки
// MaxUploadSize на минимальной скорости.
func TestUploadReadTimeout(t *testing.T) {
	// 2 ГБ при 50 КБ/с — ~11.6 часов; таймаут обязан это покрыть.
	twoGB := int64(2) << 30
	assert.Greater(
		t,
		uploadReadTimeout(twoGB),
		time.Duration(10)*time.Hour,
		"2 GB must fit the upload window",
	)

	// Крошечный/нулевой лимит — минимум 10 минут.
	assert.Equal(t, 10*time.Minute, uploadReadTimeout(0))
	assert.Equal(t, 10*time.Minute, uploadReadTimeout(1024))

	// Формула: размер/пол + минута запаса.
	assert.Equal(
		t,
		time.Duration((100<<20)/(50<<10)+60)*time.Second,
		uploadReadTimeout(100<<20),
	)
}
