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

// Имена сессионных кук для веб-клиента. Мобильные клиенты ходят
// по Bearer-токенам из JSON, веб — по httpOnly-кукам; middleware
// принимает оба варианта, заголовок в приоритете.
const (
	CookieAccessToken  = "flux_access"
	CookieRefreshToken = "flux_refresh"
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
		token := ""
		if authHeader := c.Get("Authorization"); authHeader != "" {
			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
				return response.Error(c, fiber.StatusUnauthorized, "Invalid authorization header format")
			}
			token = parts[1]
		} else {
			// Заголовка нет — веб-клиент присылает access-токен в httpOnly-куке.
			token = c.Cookies(CookieAccessToken)
			if token == "" {
				return response.Error(c, fiber.StatusUnauthorized, "Missing authorization header")
			}
		}

		claims, err := jwtService.ValidateToken(token)
		if err != nil {
			return response.Error(c, fiber.StatusUnauthorized, "Invalid or expired token")
		}

		c.Locals(LocalsUserID, claims.UserID)
		c.Locals(LocalsUserEmail, claims.Email)

		return c.Next()
	}
}
