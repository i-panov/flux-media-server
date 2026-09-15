package services_test

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/fsnotify/fsnotify"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/config"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

func setupTestDB(t *testing.T) *repository.MediaStore {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)

	err = repository.AutoMigrate(db)
	require.NoError(t, err)

	return repository.NewMediaRepository(db)
}

func TestScannerFFProbeSingleCall(t *testing.T) {
	mediaRepo := setupTestDB(t)

	tempDir := t.TempDir()
	testFile := filepath.Join(tempDir, "test.mp4")

	err := os.WriteFile(testFile, []byte("fake mp4 content"), 0644)
	require.NoError(t, err)

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}

	scanner := services.NewScannerService(mediaRepo, cfg)

	ctx := context.Background()
	err = scanner.ScanPath(ctx, tempDir)
	require.NoError(t, err)

	media, err := mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)
	assert.Equal(t, testFile, media.FilePath)
	assert.NotEmpty(t, media.FileHash)
}

func TestScannerSweepDeletedMedia(t *testing.T) {
	mediaRepo := setupTestDB(t)

	tempDir := t.TempDir()
	testFile := filepath.Join(tempDir, "test.mp4")
	err := os.WriteFile(testFile, []byte("fake mp4 content"), 0644)
	require.NoError(t, err)

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}

	scanner := services.NewScannerService(mediaRepo, cfg)

	ctx := context.Background()
	err = scanner.ScanPath(ctx, tempDir)
	require.NoError(t, err)

	media, err := mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)
	assert.Equal(t, testFile, media.FilePath)

	err = os.Remove(testFile)
	require.NoError(t, err)

	err = scanner.ScanPath(ctx, tempDir)
	require.NoError(t, err)

	_, err = mediaRepo.FindByPath(ctx, testFile)
	assert.Error(t, err)
}

// TestScannerSweepDeletedKeysetNoSkips: больше pageSize (200) записей без
// файлов на диске — sweep обязан удалить ВСЕ. Offset-пагинация с удалением
// в цикле сдвигала окно и пропускала записи (регрессия).
func TestScannerSweepDeletedKeysetNoSkips(t *testing.T) {
	mediaRepo := setupTestDB(t)
	tempDir := t.TempDir()
	ctx := context.Background()

	const count = 450 // > pageSize в sweepDeleted (200)
	for i := 0; i < count; i++ {
		media := &models.Media{
			Title:    fmt.Sprintf("m%d", i),
			Filename: fmt.Sprintf("f%d.mp4", i),
			FilePath: filepath.Join(tempDir, fmt.Sprintf("f%d.mp4", i)),
			FileSize: 100,
			Type:     models.MediaTypeVideo,
		}
		require.NoError(t, mediaRepo.Create(ctx, media))
	}

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}
	scanner := services.NewScannerService(mediaRepo, cfg)

	require.NoError(t, scanner.ScanPath(ctx, tempDir))

	_, total, err := mediaRepo.FindAll(ctx, repository.MediaFilters{}, 0, 0)
	require.NoError(t, err)
	assert.Zero(t, total, "sweep должен удалить все записи без файлов, без пропусков")
}

// TestScannerContextCancellation: отмена контекста прерывает скан.
func TestScannerContextCancellation(t *testing.T) {
	mediaRepo := setupTestDB(t)
	tempDir := t.TempDir()

	testFile := filepath.Join(tempDir, "cancel.mp4")
	err := os.WriteFile(testFile, bytes.Repeat([]byte{0x11}, 1024), 0644)
	require.NoError(t, err)

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}
	scanner := services.NewScannerService(mediaRepo, cfg)

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	err = scanner.ScanPath(ctx, tempDir)
	assert.ErrorIs(t, err, context.Canceled)

	// После отмены статус скана должен быть сброшен: повторный скан не
	// должен возвращать ErrScanInProgress.
	err = scanner.ScanPath(context.Background(), tempDir)
	require.NoError(t, err)
}

// TestScannerUpdateKeepsManualEdits: при пересканировании изменённого файла
// ручные правки Title/Year не затираются тегами/именем файла (регрессия).
func TestScannerUpdateKeepsManualEdits(t *testing.T) {
	mediaRepo := setupTestDB(t)
	tempDir := t.TempDir()
	ctx := context.Background()

	testFile := filepath.Join(tempDir, "test.mp4")
	content := bytes.Repeat([]byte{0x42}, 1500*1024)
	require.NoError(t, os.WriteFile(testFile, content, 0644))

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}
	scanner := services.NewScannerService(mediaRepo, cfg)

	require.NoError(t, scanner.ScanPath(ctx, tempDir))

	media, err := mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)
	oldQuickHash := media.QuickHash

	// Ручная правка пользователя.
	media.Title = "Ручной заголовок"
	media.Year = 1999
	require.NoError(t, mediaRepo.Update(ctx, media))

	// Изменяем содержимое файла (тот же размер — quick hash детектирует
	// по изменению хвоста).
	modified := make([]byte, len(content))
	copy(modified, content)
	modified[len(modified)-1024] = 0x99
	require.NoError(t, os.WriteFile(testFile, modified, 0644))

	require.NoError(t, scanner.ScanPath(ctx, tempDir))

	after, err := mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)
	assert.Equal(t, "Ручной заголовок", after.Title, "ручная правка Title не должна затираться")
	assert.Equal(t, 1999, after.Year, "ручная правка Year не должна затираться")
	assert.NotEqual(t, oldQuickHash, after.QuickHash, "quick hash изменившегося файла должен обновиться")
}

// errorHashRepo — обёртка над MediaStore, которая проваливает FindByHash
// любой ошибкой, не являющейся gorm.ErrRecordNotFound.
type errorHashRepo struct {
	*repository.MediaStore
	findByHashErr error
}

func (r *errorHashRepo) FindByHash(ctx context.Context, hash string) (*models.Media, error) {
	return nil, r.findByHashErr
}

// TestScannerFindByHashDBError: реальная ошибка БД при проверке дубликатов
// не должна трактоваться как «дубликата нет» — файл не должен создаваться
// (раньше err проглатывался и Create мог создать дубликат).
func TestScannerFindByHashDBError(t *testing.T) {
	mediaRepo := setupTestDB(t)
	repo := &errorHashRepo{MediaStore: mediaRepo, findByHashErr: errors.New("db is down")}

	tempDir := t.TempDir()
	testFile := filepath.Join(tempDir, "test.mp4")
	err := os.WriteFile(testFile, []byte("fake mp4 content"), 0644)
	require.NoError(t, err)

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}
	scanner := services.NewScannerService(repo, cfg)

	ctx := context.Background()
	err = scanner.ScanPath(ctx, tempDir)
	require.NoError(t, err, "скан должен завершиться без паники, файл просто пропускается")

	// Никаких записей создано быть не должно — реальная ошибка БД.
	_, total, err := repo.FindAll(ctx, repository.MediaFilters{}, 0, 0)
	require.NoError(t, err)
	assert.Zero(t, total, "файл не должен создаваться при сбое FindByHash")

	_, err = repo.FindByPath(ctx, testFile)
	assert.Error(t, err, "медиа для файла не должно существовать")
}

// TestHandleFSEventsCreate: событие Create → запись медиа создаётся
// инкрементально, без полного прохода по библиотеке.
func TestHandleFSEventsCreate(t *testing.T) {
	mediaRepo := setupTestDB(t)
	tempDir := t.TempDir()
	ctx := context.Background()

	testFile := filepath.Join(tempDir, "watched.mp4")
	require.NoError(t, os.WriteFile(testFile, []byte("fake mp4 content"), 0644))

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}
	scanner := services.NewScannerService(mediaRepo, cfg)

	scanner.HandleFSEvents(ctx, []services.FSEvent{
		{Path: testFile, Op: fsnotify.Create},
	})

	media, err := mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)
	assert.Equal(t, testFile, media.FilePath)
	assert.NotEmpty(t, media.FileHash)
}

// TestHandleFSEventsRemove: событие Remove → запись и миниатюра удаляются.
func TestHandleFSEventsRemove(t *testing.T) {
	mediaRepo := setupTestDB(t)
	tempDir := t.TempDir()
	ctx := context.Background()

	testFile := filepath.Join(tempDir, "watched.mp4")
	require.NoError(t, os.WriteFile(testFile, []byte("fake mp4 content"), 0644))

	thumbDir := t.TempDir()
	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: thumbDir,
			VideoPath:     tempDir,
		},
	}
	scanner := services.NewScannerService(mediaRepo, cfg)

	// Первичное создание записи (полный скан).
	require.NoError(t, scanner.ScanPath(ctx, tempDir))

	media, err := mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)

	// Имитируем существующую миниатюру.
	thumbPath := filepath.Join(thumbDir, fmt.Sprintf("%d.jpg", media.ID))
	require.NoError(t, os.WriteFile(thumbPath, []byte("fake thumb"), 0644))

	// Файл исчез с диска.
	require.NoError(t, os.Remove(testFile))

	scanner.HandleFSEvents(ctx, []services.FSEvent{
		{Path: testFile, Op: fsnotify.Remove},
	})

	_, err = mediaRepo.FindByPath(ctx, testFile)
	assert.Error(t, err, "запись должна быть удалена после Remove-события")

	_, statErr := os.Stat(thumbPath)
	assert.True(t, os.IsNotExist(statErr), "миниатюра должна быть удалена вместе с записью")
}

// TestHandleFSEventsRemoveUnknownPath: удаление файла без записи — не ошибка.
func TestHandleFSEventsRemoveUnknownPath(t *testing.T) {
	mediaRepo := setupTestDB(t)
	tempDir := t.TempDir()

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}
	scanner := services.NewScannerService(mediaRepo, cfg)

	// Не должно паниковать и не должно ничего удалить.
	scanner.HandleFSEvents(context.Background(), []services.FSEvent{
		{Path: filepath.Join(tempDir, "never-existed.mp4"), Op: fsnotify.Remove},
	})
}

// TestHandleFSEventsWriteUpdates: повторное событие Write по изменившемуся
// файлу обновляет запись, по неизменённому — не трогает.
func TestHandleFSEventsWriteUpdates(t *testing.T) {
	mediaRepo := setupTestDB(t)
	tempDir := t.TempDir()
	ctx := context.Background()

	testFile := filepath.Join(tempDir, "watched.mp4")
	content := bytes.Repeat([]byte{0x42}, 1500*1024)
	require.NoError(t, os.WriteFile(testFile, content, 0644))

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}
	scanner := services.NewScannerService(mediaRepo, cfg)

	scanner.HandleFSEvents(ctx, []services.FSEvent{
		{Path: testFile, Op: fsnotify.Create},
	})

	media, err := mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)
	oldQuickHash := media.QuickHash

	// Write по неизменённому файлу — quick hash совпадает, запись нетронута.
	scanner.HandleFSEvents(ctx, []services.FSEvent{
		{Path: testFile, Op: fsnotify.Write},
	})
	after, err := mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)
	assert.Equal(t, oldQuickHash, after.QuickHash)

	// Изменяем хвост файла — Write должен обновить quick hash.
	modified := make([]byte, len(content))
	copy(modified, content)
	modified[len(modified)-1024] = 0x99
	require.NoError(t, os.WriteFile(testFile, modified, 0644))

	scanner.HandleFSEvents(ctx, []services.FSEvent{
		{Path: testFile, Op: fsnotify.Write},
	})
	after, err = mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)
	assert.NotEqual(t, oldQuickHash, after.QuickHash, "изменившийся файл должен получить новый quick hash")
}

// TestHandleFSEventsEmptyFileSkipped: пустой файл (ещё пишется) — запись
// не создаётся и существующая не удаляется.
func TestHandleFSEventsEmptyFileSkipped(t *testing.T) {
	mediaRepo := setupTestDB(t)
	tempDir := t.TempDir()
	ctx := context.Background()

	testFile := filepath.Join(tempDir, "empty.mp4")
	require.NoError(t, os.WriteFile(testFile, []byte{}, 0644))

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}
	scanner := services.NewScannerService(mediaRepo, cfg)

	scanner.HandleFSEvents(ctx, []services.FSEvent{
		{Path: testFile, Op: fsnotify.Create},
	})

	_, total, err := mediaRepo.FindAll(ctx, repository.MediaFilters{}, 0, 0)
	require.NoError(t, err)
	assert.Zero(t, total, "запись для пустого файла не должна создаваться")
}

// TestHandleFSEventsContextCancelled: отмена контекста останавливает
// обработку пачки.
func TestHandleFSEventsContextCancelled(t *testing.T) {
	mediaRepo := setupTestDB(t)
	tempDir := t.TempDir()

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}
	scanner := services.NewScannerService(mediaRepo, cfg)

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	// Не должно паниковать; записи не создаются.
	scanner.HandleFSEvents(ctx, []services.FSEvent{
		{Path: filepath.Join(tempDir, "a.mp4"), Op: fsnotify.Create},
		{Path: filepath.Join(tempDir, "b.mp4"), Op: fsnotify.Create},
	})
}
