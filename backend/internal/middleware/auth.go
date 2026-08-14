package middleware

import (
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/response"
	"flux/internal/services"
)

// Ключи Locals, в которых AuthMiddleware сохраняет данные аутентифицированного
// пользователя. Типизированные ключи исключают опечатки в магических строках.
const (
	LocalsUserID    = "user_id"
	LocalsUserEmail = "user_email"
)

// GetUserID возвращает ID аутентифицированного пользователя из Locals.
func GetUserID(c *fiber.Ctx) (uint, bool) {
	userID, ok := c.Locals(LocalsUserID).(uint)
	return userID, ok
}

// GetUserEmail возвращает email аутентифицированного пользователя из Locals.
func GetUserEmail(c *fiber.Ctx) (string, bool) {
	email, ok := c.Locals(LocalsUserEmail).(string)
	return email, ok
}

func AuthMiddleware(jwtService services.JWTService) fiber.Handler {
	return func(c *fiber.Ctx) error {
		authHeader := c.Get("Authorization")
		if authHeader == "" {
			return response.Error(c, fiber.StatusUnauthorized, "Missing authorization header")
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			return response.Error(c, fiber.StatusUnauthorized, "Invalid authorization header format")
		}

		claims, err := jwtService.ValidateToken(parts[1])
		if err != nil {
			return response.Error(c, fiber.StatusUnauthorized, "Invalid or expired token")
		}

		c.Locals(LocalsUserID, claims.UserID)
		c.Locals(LocalsUserEmail, claims.Email)

		return c.Next()
	}
}
