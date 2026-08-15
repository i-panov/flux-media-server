package middleware

import "github.com/gofiber/fiber/v2"

// SecurityHeaders добавляет базовые заголовки безопасности.
func SecurityHeaders() fiber.Handler {
	return func(c *fiber.Ctx) error {
		c.Set("X-Content-Type-Options", "nosniff")
		c.Set("X-Frame-Options", "DENY")
		c.Set("Referrer-Policy", "no-referrer")
		return c.Next()
	}
}
