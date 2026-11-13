package services

import (
	"path/filepath"
	"sync"
)

// publishingPaths закрывает окно «файл уже в библиотеке, Media ещё нет»:
// watcher/сканер пропускает путь, который прямо сейчас публикует очередь.
var publishingPaths sync.Map

// ReservePublishingPath помечает путь до создания записи Media. Возвращённая
// функция идемпотентно снимает резерв.
func ReservePublishingPath(path string) func() {
	key := filepath.Clean(path)
	publishingPaths.Store(key, struct{}{})
	return func() { publishingPaths.Delete(key) }
}

func IsPublishingPath(path string) bool {
	_, ok := publishingPaths.Load(filepath.Clean(path))
	return ok
}
