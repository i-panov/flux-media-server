package handlers

import "strings"

// deviceLabelFromUserAgent даёт человекочитаемое имя браузера/ОС для
// списка устройств. Без сторонних библиотек: пользователю важно увидеть
// «Chrome · Windows», а не «Unknown».
func deviceLabelFromUserAgent(ua string) (name, platform string) {
	u := strings.ToLower(ua)
	browser := ""
	switch {
	case strings.Contains(u, "edg/"):
		browser = "Edge"
	case strings.Contains(u, "opr/") || strings.Contains(u, "opera"):
		browser = "Opera"
	case strings.Contains(u, "samsungbrowser"):
		browser = "Samsung Internet"
	case strings.Contains(u, "yabrowser"):
		browser = "Yandex"
	case strings.Contains(u, "firefox"):
		browser = "Firefox"
	case strings.Contains(u, "chrome") || strings.Contains(u, "crios"):
		browser = "Chrome"
	case strings.Contains(u, "safari"):
		browser = "Safari"
	}

	osName := ""
	switch {
	case strings.Contains(u, "android tv") || strings.Contains(u, "googletv"):
		osName = "Android TV"
		platform = "androidtv"
	case strings.Contains(u, "tizen"):
		osName = "Tizen"
		platform = "tizen"
	case strings.Contains(u, "web0s") || strings.Contains(u, "webos"):
		osName = "webOS"
		platform = "webos"
	case strings.Contains(u, "windows"):
		osName = "Windows"
		platform = "windows"
	case strings.Contains(u, "iphone") || strings.Contains(u, "ipad"):
		osName = "iOS"
		platform = "ios"
	case strings.Contains(u, "mac os") || strings.Contains(u, "macintosh"):
		osName = "macOS"
		platform = "macos"
	case strings.Contains(u, "android"):
		osName = "Android"
		platform = "android"
	case strings.Contains(u, "linux"):
		osName = "Linux"
		platform = "linux"
	}
	if platform == "" {
		platform = "web"
	}
	switch {
	case browser != "" && osName != "":
		name = browser + " · " + osName
	case browser != "":
		name = browser
	case osName != "":
		name = osName
	default:
		name = "Браузер"
	}
	return name, platform
}
