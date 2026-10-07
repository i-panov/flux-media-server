package metadata

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNormalizeSourceURL(t *testing.T) {
	valid := map[string]string{
		"https://www.youtube.com/watch?v=abc": "https://www.youtube.com/watch?v=abc",
		"https://youtu.be/abc":                "https://youtu.be/abc",
		"  https://example.com/x  ":           "https://example.com/x",
		"HTTP://EXAMPLE.COM":                  "HTTP://EXAMPLE.COM",
		"http://localhost:8080/a":             "http://localhost:8080/a",
		"http://192.168.1.10:8080/a":          "http://192.168.1.10:8080/a",
		"http://169.254.169.254/":             "http://169.254.169.254/",
	}
	for raw, want := range valid {
		got, err := NormalizeSourceURL(raw)
		require.NoError(t, err, "raw %q must be valid", raw)
		assert.Equal(t, want, got)
	}

	t.Run("empty means clear", func(t *testing.T) {
		for _, raw := range []string{"", "   "} {
			got, err := NormalizeSourceURL(raw)
			require.NoError(t, err, "raw %q", raw)
			assert.Equal(t, "", got)
		}
	})

	t.Run("not a URL", func(t *testing.T) {
		for _, raw := range []string{
			"not a url",
			"ftp://example.com/x",
			"javascript:alert(1)",
			"//example.com/no-scheme",
			"https://",
			"http://",
			"http://exam ple.com/",
			"http://example.com/a\nb",
		} {
			_, err := NormalizeSourceURL(raw)
			assert.ErrorIs(t, err, ErrSourceURLInvalid, "raw %q", raw)
		}
	})

	t.Run("credentials rejected", func(t *testing.T) {
		for _, raw := range []string{
			"http://user:pass@example.com/",
			"https://user@example.com/",
		} {
			_, err := NormalizeSourceURL(raw)
			assert.ErrorIs(t, err, ErrSourceURLInvalid, "raw %q", raw)
		}
	})

	t.Run("length boundary", func(t *testing.T) {
		// Ровно лимит с валидным хостом — проходит, лимит+1 — нет.
		// Прошлый тест проверял 2049 без схемы и ловил ветку схемы,
		// а не лимита.
		base := "https://example.com/"
		okRaw := base + strings.Repeat("a", 2048-len(base))
		got, err := NormalizeSourceURL(okRaw)
		require.NoError(t, err)
		assert.Equal(t, okRaw, got)

		_, err = NormalizeSourceURL(base + strings.Repeat("a", 2049-len(base)))
		assert.ErrorIs(t, err, ErrSourceURLTooLong)

		// Длинная, но невалидная по схеме — побеждает лимит (проверка
		// длины идёт первой, сообщение «too long», а не «not a URL»).
		_, err = NormalizeSourceURL(strings.Repeat("a", 2049))
		assert.ErrorIs(t, err, ErrSourceURLTooLong)
	})
}
