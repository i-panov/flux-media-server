package handlers

import (
	"errors"
	"log"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/response"
)

// parseIDParam парсит идентификатор из параметра пути. Отрицательные
// значения отклоняются — иначе uint(id) превратил бы -1 в огромное число.
func parseIDParam(c *fiber.Ctx, name string) (uint, error) {
	v, err := c.ParamsInt(name)
	if err != nil || v < 0 {
		return 0, errors.New("invalid id")
	}
	return uint(v), nil
}

// repoError отвечает 404 для gorm.ErrRecordNotFound и 500 для прочих
// сбоев БД — иначе неполадки хранилища маскируются под «не найдено».
func repoError(c *fiber.Ctx, err error, notFoundMsg, serverMsg string) error {
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return response.Error(c, fiber.StatusNotFound, notFoundMsg)
	}
	log.Printf("%s: %v", notFoundMsg, err)
	return response.Error(c, fiber.StatusInternalServerError, serverMsg)
}
