//go:build unix

package services

import (
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
	return int64(stat.Bavail) * int64(stat.Bsize)
}
