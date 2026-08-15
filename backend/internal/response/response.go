package response

import "github.com/gofiber/fiber/v2"

// MaxPageSize — верхняя граница размера страницы (DoS-защита).
const MaxPageSize = 200

// ErrorResponse is the standard error envelope for all API responses.
type ErrorResponse struct {
	Error   string `json:"error"`
	Details string `json:"details,omitempty"`
}

// Error sends a JSON error response with the given status code.
func Error(c *fiber.Ctx, status int, message string) error {
	return c.Status(status).JSON(ErrorResponse{Error: message})
}

// ClampPage ограничивает limit/offset допустимыми значениями:
// limit <= 0 заменяется на defLimit, предел сверху — MaxPageSize,
// отрицательный offset обнуляется.
func ClampPage(limit, offset, defLimit int) (int, int) {
	if limit <= 0 {
		limit = defLimit
	}
	if limit > MaxPageSize {
		limit = MaxPageSize
	}
	if offset < 0 {
		offset = 0
	}
	return limit, offset
}

// Paginated — единый формат пагинированного ответа {items, total, limit, offset}.
func Paginated(c *fiber.Ctx, items interface{}, total int64, limit, offset int) error {
	return c.JSON(fiber.Map{
		"items":  items,
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}
