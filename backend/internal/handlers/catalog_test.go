package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/require"
	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
)

func catalogTestApp(t *testing.T) (*fiber.App, *gorm.DB) {
	t.Helper()
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	h := NewCatalogHandler(repository.NewWorkRepository(db), repository.NewFranchiseRepository(db))
	app := fiber.New()
	app.Get("/works", h.ListWorks)
	app.Post("/works", h.CreateWork)
	app.Get("/works/:id", h.GetWork)
	app.Put("/works/:id", h.UpdateWork)
	app.Delete("/works/:id", h.DeleteWork)
	app.Post("/works/:id/seasons", h.CreateSeason)
	app.Put("/works/:id/seasons/order", h.ReorderSeasons)
	app.Post("/works/:id/items", h.AddFilm)
	app.Delete("/works/:id/items/:mediaId", h.RemoveFilm)
	app.Put("/works/:id/items/order", h.ReorderFilmItems)
	app.Put("/seasons/:id", h.UpdateSeason)
	app.Delete("/seasons/:id", h.DeleteSeason)
	app.Post("/seasons/:id/items", h.AddEpisode)
	app.Delete("/seasons/:id/items/:mediaId", h.RemoveEpisode)
	app.Put("/seasons/:id/items/order", h.ReorderEpisodes)
	app.Get("/franchises", h.ListFranchises)
	app.Post("/franchises", h.CreateFranchise)
	app.Get("/franchises/:id", h.GetFranchise)
	app.Put("/franchises/:id", h.UpdateFranchise)
	app.Delete("/franchises/:id", h.DeleteFranchise)
	app.Post("/franchises/:id/entries", h.AddFranchiseEntry)
	app.Delete("/franchises/:id/entries/:entryId", h.RemoveFranchiseEntry)
	app.Put("/franchises/:id/entries/order", h.ReorderFranchiseEntries)
	return app, db
}

func catalogRequest(t *testing.T, app *fiber.App, method, path string, body any) (int, []byte) {
	t.Helper()
	var reader *bytes.Reader
	if body == nil {
		reader = bytes.NewReader(nil)
	} else {
		raw, err := json.Marshal(body)
		require.NoError(t, err)
		reader = bytes.NewReader(raw)
	}
	req := httptest.NewRequest(method, path, reader)
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	defer resp.Body.Close()
	var buf bytes.Buffer
	_, err = buf.ReadFrom(resp.Body)
	require.NoError(t, err)
	return resp.StatusCode, buf.Bytes()
}

func TestCatalogHandlerSeriesLifecycle(t *testing.T) {
	app, db := catalogTestApp(t)
	status, body := catalogRequest(t, app, "POST", "/works", map[string]any{
		"kind": "series", "title": "Show",
	})
	require.Equal(t, fiber.StatusCreated, status, string(body))
	var created models.Work
	require.NoError(t, json.Unmarshal(body, &created))
	require.Len(t, created.Seasons, 1)

	media := models.Media{Title: "Episode", Type: models.MediaTypeVideo, FilePath: "/e.mp4"}
	require.NoError(t, db.Create(&media).Error)
	status, body = catalogRequest(t, app, "POST",
		fmt.Sprintf("/seasons/%d/items", created.Seasons[0].ID),
		map[string]any{"media_id": media.ID, "episode_number": 1})
	require.Equal(t, fiber.StatusCreated, status, string(body))
	var added models.WorkItem
	require.NoError(t, json.Unmarshal(body, &added))
	require.NotNil(t, added.Media)
	require.Equal(t, media.ID, added.Media.ID)

	status, body = catalogRequest(t, app, "GET", fmt.Sprintf("/works/%d", created.ID), nil)
	require.Equal(t, fiber.StatusOK, status, string(body))
	var got models.Work
	require.NoError(t, json.Unmarshal(body, &got))
	require.Len(t, got.Seasons, 1)
	require.Len(t, got.Seasons[0].Items, 1)
	require.NotNil(t, got.Seasons[0].Items[0].Media)
	require.Equal(t, media.ID, got.Seasons[0].Items[0].Media.ID)

	status, body = catalogRequest(t, app, "PUT",
		fmt.Sprintf("/seasons/%d", created.Seasons[0].ID), map[string]any{"title": "Renamed"})
	require.Equal(t, fiber.StatusOK, status, string(body))
	var updated models.Season
	require.NoError(t, json.Unmarshal(body, &updated))
	require.Len(t, updated.Items, 1)
	require.NotNil(t, updated.Items[0].Media)
}

func TestCatalogHandlerFilmSeriesAndFranchise(t *testing.T) {
	app, db := catalogTestApp(t)
	status, body := catalogRequest(t, app, "POST", "/works", map[string]any{
		"kind": "film_series", "title": "Films",
	})
	require.Equal(t, fiber.StatusCreated, status, string(body))
	var films models.Work
	require.NoError(t, json.Unmarshal(body, &films))
	require.Empty(t, films.Seasons)

	movie := models.Media{Title: "Movie", Type: models.MediaTypeVideo, FilePath: "/f.mp4"}
	require.NoError(t, db.Create(&movie).Error)
	status, body = catalogRequest(t, app, "POST", fmt.Sprintf("/works/%d/items", films.ID),
		map[string]any{"media_id": movie.ID})
	require.Equal(t, fiber.StatusCreated, status, string(body))
	var filmItem models.WorkItem
	require.NoError(t, json.Unmarshal(body, &filmItem))
	require.NotNil(t, filmItem.Media)

	status, body = catalogRequest(t, app, "POST", "/franchises", map[string]any{"name": "Universe"})
	require.Equal(t, fiber.StatusCreated, status, string(body))
	var franchise models.Franchise
	require.NoError(t, json.Unmarshal(body, &franchise))
	status, body = catalogRequest(t, app, "POST",
		fmt.Sprintf("/franchises/%d/entries", franchise.ID), map[string]any{"work_id": films.ID})
	require.Equal(t, fiber.StatusCreated, status, string(body))
	var workEntry models.FranchiseEntry
	require.NoError(t, json.Unmarshal(body, &workEntry))
	require.NotNil(t, workEntry.Work)
	status, body = catalogRequest(t, app, "POST",
		fmt.Sprintf("/franchises/%d/entries", franchise.ID), map[string]any{"media_id": movie.ID})
	require.Equal(t, fiber.StatusConflict, status, string(body), "movie inside film_series must be rejected")

	status, body = catalogRequest(t, app, "GET", fmt.Sprintf("/franchises/%d", franchise.ID), nil)
	require.Equal(t, fiber.StatusOK, status, string(body))
	var got models.Franchise
	require.NoError(t, json.Unmarshal(body, &got))
	require.Len(t, got.Entries, 1)
	require.NotNil(t, got.Entries[0].Work)
}

func TestCatalogHandlerValidationAndNotFound(t *testing.T) {
	app, _ := catalogTestApp(t)
	status, _ := catalogRequest(t, app, "POST", "/works", map[string]any{"kind": "bogus", "title": "X"})
	require.Equal(t, fiber.StatusBadRequest, status)
	status, _ = catalogRequest(t, app, "GET", "/works/999", nil)
	require.Equal(t, fiber.StatusNotFound, status)
	status, _ = catalogRequest(t, app, "POST", "/works", map[string]any{"kind": "series", "title": ""})
	require.Equal(t, fiber.StatusBadRequest, status)
	status, _ = catalogRequest(t, app, "POST", "/franchises", map[string]any{"name": ""})
	require.Equal(t, fiber.StatusBadRequest, status)
	status, _ = catalogRequest(t, app, "POST", "/seasons/1/items", map[string]any{})
	require.Equal(t, fiber.StatusBadRequest, status)
	status, _ = catalogRequest(t, app, "POST", "/works/1/items", map[string]any{})
	require.Equal(t, fiber.StatusBadRequest, status)
	status, _ = catalogRequest(t, app, "POST", "/franchises/1/entries", map[string]any{})
	require.Equal(t, fiber.StatusBadRequest, status)
	negative := -1
	status, _ = catalogRequest(t, app, "POST", "/seasons/1/items", map[string]any{"media_id": 1, "episode_number": negative})
	require.Equal(t, fiber.StatusBadRequest, status)
}

func TestRemoveFranchiseEntryRejectsForeignFranchise(t *testing.T) {
	app, db := catalogTestApp(t)
	first := models.Franchise{Name: "First"}
	second := models.Franchise{Name: "Second"}
	require.NoError(t, db.Create(&first).Error)
	require.NoError(t, db.Create(&second).Error)
	work := models.Work{Kind: models.WorkKindFilmSeries, Title: "Films"}
	require.NoError(t, db.Create(&work).Error)
	entry := models.FranchiseEntry{FranchiseID: second.ID, WorkID: &work.ID}
	require.NoError(t, db.Create(&entry).Error)

	status, _ := catalogRequest(t, app, "DELETE",
		fmt.Sprintf("/franchises/%d/entries/%d", first.ID, entry.ID), nil)
	require.Equal(t, fiber.StatusNotFound, status)
	var count int64
	require.NoError(t, db.Model(&models.FranchiseEntry{}).Where("id = ?", entry.ID).Count(&count).Error)
	require.Equal(t, int64(1), count)
	status, _ = catalogRequest(t, app, "DELETE",
		fmt.Sprintf("/franchises/%d/entries/%d", second.ID, entry.ID), nil)
	require.Equal(t, fiber.StatusNoContent, status)
}
