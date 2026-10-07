package metadata

import (
	"errors"
	"net/url"
	"strings"
	"unicode"
	"unicode/utf8"
)

// maxSourceURLLen — предел длины ссылки на источник в символах.
const maxSourceURLLen = 2048

var (
	// ErrSourceURLTooLong — ссылка длиннее maxSourceURLLen.
	ErrSourceURLTooLong = errors.New("source_url too long")
	// ErrSourceURLInvalid — не http(s) URL, пустой хост, credentials
	// в адресе или мусор в хосте.
	ErrSourceURLInvalid = errors.New("invalid source_url")
)

// NormalizeSourceURL проверяет ссылку на источник и приводит её к
// каноническому виду (обрезка пробелов). Пустая строка после trim —
// валидное значение «очистить», а не ошибка: очистка идёт через тот же
// PUT /api/metadata/:mediaId, что и установка.
//
// Принимается любой http(s) URL без привязки к хосту (YouTube и прочие),
// включая localhost, приватные IP и link-local (169.254.x.x): ссылка
// нигде не фетчится сервером, а только хранится и отображается, поэтому
// SSRF-риска нет. Это осознанное wontfix, а не недосмотр —
// см. ВАЖНО ниже.
//
// ВАЖНО: если ссылку когда-нибудь начнут фетчить на сервере (превью,
// oEmbed, импорт) — сначала нужен SSRF-гард: запрет приватных,
// link-local и метаданных облаков (169.254.169.254), ограничение
// редиректов и таймауты. Без гарда фетчить нельзя.
func NormalizeSourceURL(raw string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", nil
	}
	if utf8.RuneCountInString(trimmed) > maxSourceURLLen {
		return "", ErrSourceURLTooLong
	}
	parsed, err := url.Parse(trimmed)
	if err != nil {
		return "", ErrSourceURLInvalid
	}
	scheme := strings.ToLower(parsed.Scheme)
	if scheme != "http" && scheme != "https" {
		return "", ErrSourceURLInvalid
	}
	// Credentials в хранимой ссылке недопустимы: пароль утекал бы в логи
	// и JSON всем читателям библиотеки (в normalizeServerUrl userInfo
	// дропают по той же причине).
	if parsed.User != nil {
		return "", ErrSourceURLInvalid
	}
	host := parsed.Hostname()
	if host == "" {
		return "", ErrSourceURLInvalid
	}
	for _, r := range host {
		if unicode.IsSpace(r) || unicode.IsControl(r) {
			return "", ErrSourceURLInvalid
		}
	}
	return trimmed, nil
}
