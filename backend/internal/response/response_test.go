package response

import (
	"encoding/json"
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestError(t *testing.T) {
	app := fiber.New()
	app.Get("/test", func(c *fiber.Ctx) error {
		return Error(c, fiber.StatusBadRequest, "invalid input")
	})

	resp, err := app.Test(httptest.NewRequest("GET", "/test", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)

	var body ErrorResponse
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&body))
	assert.Equal(t, "invalid input", body.Error)
	assert.Empty(t, body.Details)
}

func TestClampPage(t *testing.T) {
	limit, offset := ClampPage(0, 0, 50)
	assert.Equal(t, 50, limit)
	assert.Equal(t, 0, offset)

	limit, offset = ClampPage(-5, -1, 20)
	assert.Equal(t, 20, limit)
	assert.Equal(t, 0, offset)

	limit, offset = ClampPage(1000, 10, 20)
	assert.Equal(t, MaxPageSize, limit)
	assert.Equal(t, 10, offset)
}

func TestPaginated(t *testing.T) {
	app := fiber.New()
	app.Get("/test", func(c *fiber.Ctx) error {
		return Paginated(c, []int{1, 2}, int64(2), 50, 0)
	})

	resp, err := app.Test(httptest.NewRequest("GET", "/test", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var body struct {
		Items  []int `json:"items"`
		Total  int64 `json:"total"`
		Limit  int   `json:"limit"`
		Offset int   `json:"offset"`
	}
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&body))
	assert.Equal(t, []int{1, 2}, body.Items)
	assert.Equal(t, int64(2), body.Total)
	assert.Equal(t, 50, body.Limit)
	assert.Equal(t, 0, body.Offset)
}
