package middleware

import (
	"net"

	"github.com/gofiber/fiber/v2"
)

// SecurityHeaders добавляет базовые заголовки безопасности.
// trustedPeers — сети прокси: только от них принимается X-Forwarded-Proto,
// иначе HSTS можно навязать прямым HTTP-запросом.
func SecurityHeaders(trustedPeers []*net.IPNet) fiber.Handler {
	return func(c *fiber.Ctx) error {
		c.Set("X-Content-Type-Options", "nosniff")
		c.Set("X-Frame-Options", "DENY")
		c.Set("Referrer-Policy", "no-referrer")
		c.Set("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
		// Inline нужен теме/Mantine и boot-скрипту; внешних скриптов нет.
		c.Set("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' blob:; connect-src 'self'; font-src 'self' data:; worker-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'")
		// HSTS только на HTTPS (в т.ч. за доверенным прокси с
		// X-Forwarded-Proto): на HTTP-инсталляции заголовок опасен.
		if c.Protocol() == "https" ||
			(peerTrusted(c, trustedPeers) && c.Get("X-Forwarded-Proto") == "https") {
			c.Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		return c.Next()
	}
}

func peerTrusted(c *fiber.Ctx, trusted []*net.IPNet) bool {
	if len(trusted) == 0 {
		return false
	}
	ip := net.ParseIP(c.IP())
	if ip == nil {
		return false
	}
	for _, network := range trusted {
		if network.Contains(ip) {
			return true
		}
	}
	return false
}
