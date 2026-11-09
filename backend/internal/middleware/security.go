package middleware

import "github.com/gofiber/fiber/v2"

// SecurityHeaders добавляет базовые заголовки безопасности.
func SecurityHeaders() fiber.Handler {
	return func(c *fiber.Ctx) error {
		c.Set("X-Content-Type-Options", "nosniff")
		c.Set("X-Frame-Options", "DENY")
		c.Set("Referrer-Policy", "no-referrer")
		c.Set("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
		// HSTS только на HTTPS (в т.ч. за прокси с X-Forwarded-Proto):
		// на HTTP-инсталляции заголовок бессмыслен и опасен.
		if c.Protocol() == "https" || c.Get("X-Forwarded-Proto") == "https" {
			c.Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		return c.Next()
	}
}
