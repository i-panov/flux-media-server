package handlers

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"flux/internal/services"
)

// Внутренние тесты неэкспортируемых проверок имён (паттерн — как
// upload_queue_internal_test.go): уровень HTTP нормализует .. до
// хендлера, эти рубежи ловят прямые вызовы.
func TestCleanOriginalName(t *testing.T) {
	ok, valid := cleanOriginalName("film.mkv")
	assert.True(t, valid)
	assert.Equal(t, "film.mkv", ok)

	// Бэкслэш — легальный символ имени на Linux (не разделитель),
	// поэтому здесь допустим: имена из загрузок всё равно проходят
	// SanitizeFilename, а IsSubPath держит путь внутри карантина.
	for _, bad := range []string{"", ".", "..", "a/b", "/abs", "../x"} {
		_, valid := cleanOriginalName(bad)
		assert.False(t, valid, bad)
	}
}

func TestLangParamPattern(t *testing.T) {
	// Единое правило services.ValidSubtitleLang (им же пользуется
	// sanitizeLang при генерации имён): дубли языков и многосегментные
	// теги валидны, иначе ListSubs отдавал бы нерабочие URL.
	for _, good := range []string{"rus", "eng", "pt-br", "zh-hant", "rus2", "sr-latn-rs"} {
		assert.True(t, services.ValidSubtitleLang(good), good)
	}
	for _, bad := range []string{"", "e", "toolonglanguage", "../x", "EN", "en_US", "--", "a-"} {
		assert.False(t, services.ValidSubtitleLang(bad), bad)
	}
}
