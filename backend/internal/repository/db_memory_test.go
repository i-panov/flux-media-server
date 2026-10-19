package repository

import (
	"context"
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

// Регрессия: фоновые задачи при старте приложения (бэкфилл размеров кадра,
// чистка refresh-токенов) ходили в БД из горутин. На `:memory:` каждое
// НОВОЕ соединение пула получает свою пустую базу, поэтому фоновая задача
// видела «no such table: …» — и, главное, ломала соседние тесты, потому
// что запрос уводил пул на пустую копию. Одно соединение на всю in-memory
// базу решает это.
func TestInitDB_MemorySharesOneDatabase(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	repo := NewMediaRepository(db)
	ctx := context.Background()
	require.NoError(t, repo.Create(ctx, &models.Media{
		Title: "Only one", Type: models.MediaTypeVideo, FilePath: "/a.mkv",
	}))

	// Несколько конкурентных читателей подряд: при общем пуле каждый
	// второй-третий запрос ушёл бы в пустую копию базы.
	const readers = 8
	var wg sync.WaitGroup
	results := make([]int, readers)
	for i := 0; i < readers; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			var found []models.Media
			err := db.WithContext(ctx).Find(&found).Error
			if err != nil {
				results[idx] = -1
				return
			}
			results[idx] = len(found)
		}(i)
	}
	wg.Wait()

	for i, got := range results {
		assert.GreaterOrEqual(t, got, 1, "читатель %d увидел пустую базу", i)
	}
}

// Файловая база ограничения не получает: там несколько соединений полезны,
// иначе параллельные записи выстроились бы в очередь.
func TestIsMemoryPath(t *testing.T) {
	assert.True(t, isMemoryPath(":memory:"))
	assert.True(t, isMemoryPath("file:test?mode=memory&cache=shared"))
	assert.False(t, isMemoryPath("/var/lib/flux/flux.db"))
	assert.False(t, isMemoryPath("./data/flux.db"))
}
