package repository

import (
	"context"
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"

	"gorm.io/gorm"
)

// mkMedia создаёт строку медиа: FK collection_items.media_id иначе
// не даст вставить элемент в тестах.
func mkMedia(t *testing.T, db *gorm.DB, id uint) {
	t.Helper()
	require.NoError(t, db.Create(&models.Media{ID: id, Title: "M"}).Error)
}

// mkCollection создаёт коллекцию и возвращает её ID.
func mkCollection(t *testing.T, store *CollectionStore, ctx context.Context, userID uint, name string) uint {
	t.Helper()
	col := &models.Collection{UserID: userID, Name: name, Type: models.MediaTypeVideo}
	require.NoError(t, store.Create(ctx, col))
	return col.ID
}

func TestCollectionStore_SetParent(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewCollectionRepository(db)
	ctx := context.Background()

	root := mkCollection(t, store, ctx, 1, "Сериал")
	season := mkCollection(t, store, ctx, 1, "Season 01")

	// Обычный перенос под родителя.
	require.NoError(t, store.SetParent(ctx, season, &root))
	found, err := store.FindByID(ctx, season)
	require.NoError(t, err)
	require.NotNil(t, found.ParentID)
	assert.Equal(t, root, *found.ParentID)

	// Дети видны через FindChildren.
	children, err := store.FindChildren(ctx, root)
	require.NoError(t, err)
	require.Len(t, children, 1)
	assert.Equal(t, season, children[0].ID)

	// Возврат в корень.
	require.NoError(t, store.SetParent(ctx, season, nil))
	found, err = store.FindByID(ctx, season)
	require.NoError(t, err)
	assert.Nil(t, found.ParentID)
}

func TestCollectionStore_SetParent_Rejects(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewCollectionRepository(db)
	ctx := context.Background()

	root := mkCollection(t, store, ctx, 1, "Сериал")
	season := mkCollection(t, store, ctx, 1, "Season 01")
	require.NoError(t, store.SetParent(ctx, season, &root))
	alien := mkCollection(t, store, ctx, 2, "Чужой")

	// Сама на себя.
	assert.ErrorIs(t, store.SetParent(ctx, root, &root), ErrCycle)
	// Родитель под своего потомка — цикл.
	assert.ErrorIs(t, store.SetParent(ctx, root, &season), ErrCycle)
	// Родитель чужого пользователя.
	assert.ErrorIs(t, store.SetParent(ctx, season, &alien), ErrCrossUser)

	// Родитель другого типа.
	audio := &models.Collection{UserID: 1, Name: "Музыка", Type: models.MediaTypeAudio}
	require.NoError(t, store.Create(ctx, audio))
	assert.ErrorIs(t, store.SetParent(ctx, season, &audio.ID), ErrCrossType)

	// Несуществующий родитель.
	ghost := uint(9999)
	assert.Error(t, store.SetParent(ctx, season, &ghost))
}

func TestCollectionStore_IsDescendant_DeepChain(t *testing.T) {
	// Цепочка 12 уровней: старый код с лимитом 10 молча разрешал цикл.
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewCollectionRepository(db)
	ctx := context.Background()

	prev := mkCollection(t, store, ctx, 1, "L0")
	root := prev
	for i := 1; i < 12; i++ {
		next := mkCollection(t, store, ctx, 1, "L")
		require.NoError(t, store.SetParent(ctx, next, &prev))
		prev = next
	}
	leaf := prev

	is, err := store.IsDescendant(ctx, root, leaf)
	require.NoError(t, err)
	assert.True(t, is, "потомок на глубине 11 найден")

	assert.ErrorIs(
		t,
		store.SetParent(ctx, root, &leaf),
		ErrCycle,
		"корень под глубокий лист — цикл",
	)
}

func TestCollectionStore_IsDescendant(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewCollectionRepository(db)
	ctx := context.Background()

	root := mkCollection(t, store, ctx, 1, "Корень")
	mid := mkCollection(t, store, ctx, 1, "Середина")
	leaf := mkCollection(t, store, ctx, 1, "Лист")
	require.NoError(t, store.SetParent(ctx, mid, &root))
	require.NoError(t, store.SetParent(ctx, leaf, &mid))

	is, err := store.IsDescendant(ctx, root, leaf)
	require.NoError(t, err)
	assert.True(t, is)

	is, err = store.IsDescendant(ctx, leaf, root)
	require.NoError(t, err)
	assert.False(t, is)

	is, err = store.IsDescendant(ctx, root, root)
	require.NoError(t, err)
	assert.False(t, is)
}

func TestCollectionStore_DeleteCascadesSubtree(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewCollectionRepository(db)
	itemStore := NewCollectionItemRepository(db)
	ctx := context.Background()

	root := mkCollection(t, store, ctx, 1, "Сериал")
	season := mkCollection(t, store, ctx, 1, "Season 01")
	require.NoError(t, store.SetParent(ctx, season, &root))

	// Элемент в дочерней коллекции: снос корня должен убрать и его.
	mkMedia(t, db, 42)
	_, err = itemStore.AddItemAtomic(ctx, season, 42)
	require.NoError(t, err)

	require.NoError(t, store.Delete(ctx, root))

	_, err = store.FindByID(ctx, season)
	assert.Error(t, err, "дочерняя коллекция удалена вместе с корнем")
	items, err := itemStore.FindByCollection(ctx, season)
	require.NoError(t, err)
	assert.Empty(t, items, "элементы поддерева удалены")
}

func TestCollectionItemStore_MoveItemAtomic(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	colStore := NewCollectionRepository(db)
	store := NewCollectionItemRepository(db)
	ctx := context.Background()

	source := mkCollection(t, colStore, ctx, 1, "A")
	target := mkCollection(t, colStore, ctx, 1, "B")
	mkMedia(t, db, 7)
	_, err = store.AddItemAtomic(ctx, source, 7)
	require.NoError(t, err)

	moved, err := store.MoveItemAtomic(ctx, source, target, 7)
	require.NoError(t, err)
	assert.Equal(t, target, moved.CollectionID)

	srcItems, err := store.FindByCollection(ctx, source)
	require.NoError(t, err)
	assert.Empty(t, srcItems)
	dstItems, err := store.FindByCollection(ctx, target)
	require.NoError(t, err)
	require.Len(t, dstItems, 1)
	assert.Equal(t, uint(7), dstItems[0].MediaID)
}

func TestCollectionItemStore_MoveItemAtomic_DuplicateKeepsSource(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	colStore := NewCollectionRepository(db)
	store := NewCollectionItemRepository(db)
	ctx := context.Background()

	source := mkCollection(t, colStore, ctx, 1, "A")
	target := mkCollection(t, colStore, ctx, 1, "B")
	mkMedia(t, db, 7)
	_, err = store.AddItemAtomic(ctx, source, 7)
	require.NoError(t, err)
	_, err = store.AddItemAtomic(ctx, target, 7)
	require.NoError(t, err)

	// Дубль в целевой: ошибка, но исходник на месте (INSERT раньше DELETE).
	_, err = store.MoveItemAtomic(ctx, source, target, 7)
	assert.ErrorIs(t, err, ErrDuplicateItem)

	srcItems, err := store.FindByCollection(ctx, source)
	require.NoError(t, err)
	require.Len(t, srcItems, 1, "исходный элемент не потерян")
}

func TestCollectionItemStore_MoveItemAtomic_NotMember(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	colStore := NewCollectionRepository(db)
	store := NewCollectionItemRepository(db)
	ctx := context.Background()

	source := mkCollection(t, colStore, ctx, 1, "A")
	target := mkCollection(t, colStore, ctx, 1, "B")
	mkMedia(t, db, 7)

	// Элемента нет в source: 404-логика, а не молчаливое создание в target.
	_, err = store.MoveItemAtomic(ctx, source, target, 7)
	assert.ErrorIs(t, err, ErrNotMember)

	dstItems, err := store.FindByCollection(ctx, target)
	require.NoError(t, err)
	assert.Empty(t, dstItems, "в целевой ничего не создано")
}

func TestCollectionItemStore_MoveItemAtomic_SameCollection(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	colStore := NewCollectionRepository(db)
	store := NewCollectionItemRepository(db)
	ctx := context.Background()

	source := mkCollection(t, colStore, ctx, 1, "A")
	mkMedia(t, db, 7)
	_, err = store.AddItemAtomic(ctx, source, 7)
	require.NoError(t, err)

	_, err = store.MoveItemAtomic(ctx, source, source, 7)
	assert.ErrorIs(t, err, ErrSameCollection)
}

func TestCollectionStore_Patch_TypeChangeBlocked(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewCollectionRepository(db)
	itemStore := NewCollectionItemRepository(db)
	ctx := context.Background()

	// С детьми — блок.
	root := mkCollection(t, store, ctx, 1, "Сериал")
	season := mkCollection(t, store, ctx, 1, "S01")
	require.NoError(t, store.SetParent(ctx, season, &root))
	audio := models.MediaTypeAudio
	_, err = store.Patch(ctx, root, CollectionPatch{Type: &audio})
	assert.ErrorIs(t, err, ErrTypeChangeBlocked)

	// С элементами — блок.
	solo := mkCollection(t, store, ctx, 1, "Соло")
	mkMedia(t, db, 9)
	_, err = itemStore.AddItemAtomic(ctx, solo, 9)
	require.NoError(t, err)
	_, err = store.Patch(ctx, solo, CollectionPatch{Type: &audio})
	assert.ErrorIs(t, err, ErrTypeChangeBlocked)

	// Пустая — можно.
	empty := mkCollection(t, store, ctx, 1, "Пустая")
	patched, err := store.Patch(ctx, empty, CollectionPatch{Type: &audio})
	require.NoError(t, err)
	assert.Equal(t, models.MediaTypeAudio, patched.Type)
}

func TestCollectionStore_DeleteThreeLevels(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewCollectionRepository(db)
	ctx := context.Background()

	root := mkCollection(t, store, ctx, 1, "L0")
	mid := mkCollection(t, store, ctx, 1, "L1")
	leaf := mkCollection(t, store, ctx, 1, "L2")
	require.NoError(t, store.SetParent(ctx, mid, &root))
	require.NoError(t, store.SetParent(ctx, leaf, &mid))

	require.NoError(t, store.Delete(ctx, root))

	cols, err := store.FindByUser(ctx, 1)
	require.NoError(t, err)
	assert.Empty(t, cols, "все три уровня удалены одним CTE")
}

func TestCollectionStore_MigrateOldDB(t *testing.T) {
	// Старая БД без parent_id: таблица вручную, строка данных,
	// затем AutoMigrate — данные целы, родитель NULL, индекс именован.
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, db.Exec(`
		CREATE TABLE collections (
			id INTEGER PRIMARY KEY,
			user_id INTEGER,
			name TEXT,
			type TEXT,
			created_at DATETIME,
			updated_at DATETIME
		)`).Error)
	require.NoError(t, db.Exec(
		`INSERT INTO collections (user_id, name, type) VALUES (1, 'Старая', 'video')`,
	).Error)

	require.NoError(t, AutoMigrate(db))

	store := NewCollectionRepository(db)
	ctx := context.Background()
	cols, err := store.FindByUser(ctx, 1)
	require.NoError(t, err)
	require.Len(t, cols, 1, "строка старой БД пережила миграцию")
	assert.Equal(t, "Старая", cols[0].Name)
	assert.Nil(t, cols[0].ParentID)

	var indexName string
	require.NoError(t, db.Raw(
		`SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'collections' AND name = 'idx_collections_parent'`,
	).Scan(&indexName).Error)
	assert.Equal(t, "idx_collections_parent", indexName)

	// Новые операции на мигрированной строке работают.
	child := &models.Collection{UserID: 1, Name: "Дитя", Type: models.MediaTypeVideo}
	require.NoError(t, store.Create(ctx, child))
	require.NoError(t, store.SetParent(ctx, child.ID, &cols[0].ID))
}

func TestCollectionItemStore_MoveItemAtomic_Concurrent(t *testing.T) {
	// Встречные переносы разных медиа в одну цель: позиции обязаны
	// разойтись (ретрай на коллизии), дубликатов позиций нет.
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	// :memory: — одна БД на коннект пула: параллельные горутины без
	// этого получали бы пустые базы. Жмём пул в один коннект.
	sqlDB, err := db.DB()
	require.NoError(t, err)
	sqlDB.SetMaxOpenConns(1)

	colStore := NewCollectionRepository(db)
	store := NewCollectionItemRepository(db)
	ctx := context.Background()

	source := mkCollection(t, colStore, ctx, 1, "A")
	target := mkCollection(t, colStore, ctx, 1, "B")
	for _, id := range []uint{1, 2, 3, 4} {
		mkMedia(t, db, id)
		_, err = store.AddItemAtomic(ctx, source, id)
		require.NoError(t, err)
	}

	var wg sync.WaitGroup
	errs := make([]error, 4)
	for i, id := range []uint{1, 2, 3, 4} {
		wg.Add(1)
		go func(i int, id uint) {
			defer wg.Done()
			_, errs[i] = store.MoveItemAtomic(ctx, source, target, id)
		}(i, id)
	}
	wg.Wait()
	for _, err := range errs {
		require.NoError(t, err)
	}

	dstItems, err := store.FindByCollection(ctx, target)
	require.NoError(t, err)
	require.Len(t, dstItems, 4)
	positions := map[int]bool{}
	for _, it := range dstItems {
		require.False(t, positions[it.Position], "позиция %d продублирована", it.Position)
		positions[it.Position] = true
	}
	srcItems, err := store.FindByCollection(ctx, source)
	require.NoError(t, err)
	assert.Empty(t, srcItems)
}

func TestCollectionItemStore_MoveItemAtomic_Opposite(t *testing.T) {
	// Встречные переносы: медиа 1 A→B и медиа 2 B→A параллельно.
	// Разные строки — обе транзакции обязаны успеть, элементы
	// меняются местами без потерь и дублей позиций.
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	sqlDB, err := db.DB()
	require.NoError(t, err)
	sqlDB.SetMaxOpenConns(1)

	colStore := NewCollectionRepository(db)
	store := NewCollectionItemRepository(db)
	ctx := context.Background()

	a := mkCollection(t, colStore, ctx, 1, "A")
	b := mkCollection(t, colStore, ctx, 1, "B")
	mkMedia(t, db, 1)
	mkMedia(t, db, 2)
	_, err = store.AddItemAtomic(ctx, a, 1)
	require.NoError(t, err)
	_, err = store.AddItemAtomic(ctx, b, 2)
	require.NoError(t, err)

	var wg sync.WaitGroup
	errs := make([]error, 2)
	wg.Add(2)
	go func() {
		defer wg.Done()
		_, errs[0] = store.MoveItemAtomic(ctx, a, b, 1)
	}()
	go func() {
		defer wg.Done()
		_, errs[1] = store.MoveItemAtomic(ctx, b, a, 2)
	}()
	wg.Wait()
	require.NoError(t, errs[0])
	require.NoError(t, errs[1])

	aItems, err := store.FindByCollection(ctx, a)
	require.NoError(t, err)
	require.Len(t, aItems, 1)
	assert.Equal(t, uint(2), aItems[0].MediaID)
	bItems, err := store.FindByCollection(ctx, b)
	require.NoError(t, err)
	require.Len(t, bItems, 1)
	assert.Equal(t, uint(1), bItems[0].MediaID)
}
