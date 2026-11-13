package handlers

import (
	"github.com/gofiber/fiber/v2"

	"flux/internal/response"
)

// sendFile не отдаёт клиенту текст ошибки fasthttp: он содержит путь ФС.
func sendFile(c *fiber.Ctx, path, message string) error {
	if err := c.SendFile(path); err != nil {
		return response.Error(c, fiber.StatusNotFound, message)
	}
	return nil
}
