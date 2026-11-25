//go:build unix

package services

import (
	"os"
	"syscall"
)

// diskFreeBytes возвращает свободные байты ФС для path или -1,
// если узнать нельзя. Отдельный файл с тегом unix: структура
// syscall.Statfs различается между ОС.
func diskFreeBytes(path string) int64 {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return -1
	}
	// #nosec G115 -- Statfs values не превышают int64 на поддерживаемых ФС.
	return int64(stat.Bavail) * int64(stat.Bsize)
}

// diskTotalBytes возвращает полный размер ФС для path или -1.
func diskTotalBytes(path string) int64 {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return -1
	}
	// #nosec G115 -- Statfs values не превышают int64 на поддерживаемых ФС.
	return int64(stat.Blocks) * int64(stat.Bsize)
}

// sameFilesystem сообщает, лежат ли два пути на одной ФС: только тогда
// удаление из одного каталога освобождает место в другом.
func sameFilesystem(a, b string) bool {
	ai, err := os.Stat(a)
	if err != nil {
		return false
	}
	bi, err := os.Stat(b)
	if err != nil {
		return false
	}
	as, ok := ai.Sys().(*syscall.Stat_t)
	if !ok {
		return false
	}
	bs, ok := bi.Sys().(*syscall.Stat_t)
	if !ok {
		return false
	}
	return as.Dev == bs.Dev
}
