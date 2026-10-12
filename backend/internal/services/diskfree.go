package services

import (
	"fmt"
	"path/filepath"
)

// checkDiskSpace — best-effort проверка места перед ffmpeg: результат
// (особенно FLAC) может весить сравнимо с исходником. needBytes <= 0
// или неизвестный остаток (-1) — пропуск без ошибки.
func checkDiskSpace(dir string, needBytes int64) error {
	if needBytes <= 0 {
		return nil
	}
	abs, err := filepath.Abs(dir)
	if err != nil {
		return nil
	}
	free := diskFreeBytes(abs)
	if free < 0 {
		return nil
	}
	// Запас 2x: FLAC-фолбэк раздувает результат относительно copy.
	if free < needBytes*2 {
		return fmt.Errorf("not enough disk space in %s", dir)
	}
	return nil
}
