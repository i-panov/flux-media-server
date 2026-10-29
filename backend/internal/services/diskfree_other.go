//go:build !unix

package services

// diskFreeBytes — заглушка для ОС без unix-statfs: проверка места
// пропускается (см. checkDiskSpace).
func diskFreeBytes(path string) int64 {
	return -1
}

// diskTotalBytes — заглушка для ОС без unix-statfs.
func diskTotalBytes(path string) int64 {
	return -1
}
