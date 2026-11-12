// Строки офлайн-скачиваний Task 21. Вынесены из index.ts, чтобы общий
// файл не превышал max-lines; английский объект типизирован по ключам
// русского, поэтому пропущенный перевод не соберётся.
export const downloadsRu = {
	"downloads.title": "Скачивания",
	"downloads.subtitle": "Видео, аудио и изображения без сети",
	"downloads.empty": "Пока ничего не скачано",
	"downloads.emptyHint":
		"Скачайте видео или трек — они останутся на устройстве и будут доступны офлайн.",
	"downloads.download": "В офлайн",
	"downloads.downloading": "Сохранение…",
	"downloads.downloadingPercent": "{{percent}}%",
	"downloads.downloaded": "В офлайн",
	"downloads.retry": "Повторить",
	"downloads.cancel": "Отменить",
	"downloads.delete": "Удалить",
	"downloads.deleteTitle": "Удалить файл?",
	"downloads.deleteConfirm":
		"Файл будет удалён с устройства. Идущее воспроизведение может прерваться.",
	"downloads.errorNetwork":
		"Не удалось скачать файл. Проверьте сеть и повторите.",
	"downloads.errorStatus": "Сервер отклонил скачивание.",
	"downloads.errorSize": "Размер файла не совпал с ответом сервера.",
	"downloads.errorStorage": "Не удалось сохранить файл на устройстве.",
	"downloads.errorTimeout": "Скачивание прервано по таймауту.",
	"downloads.errorUnknown": "Не удалось скачать файл.",
	"downloads.errorTitle": "Не удалось скачать",
	"downloads.activeTitle": "Скачивается",
	"downloads.doneTitle": "На устройстве",
	"downloads.summary": "Файлов: {{count}} · {{size}}",
	"downloads.entryCount": "{{count}}",
	"downloads.dismiss": "Убрать",
	"downloads.typeVideo": "Видео",
	"downloads.typeAudio": "Аудио",
	"downloads.typeImage": "Изображение",
	"downloads.progressLabel": "Прогресс скачивания",
	"downloads.back": "Назад",
	"downloads.export": "Экспорт",
	"downloads.exportItem": "Экспорт: {{title}}",
	"downloads.deleteItem": "Удалить: {{title}}",
	// biome-ignore lint/security/noSecrets: текст интерфейса, не секрет.
	"downloads.exportHint": "Откроется системное меню «Поделиться»",
	"downloads.exportDialog": "Поделиться файлом",
	"downloads.exportUnavailableTitle": "Экспорт недоступен",
	"downloads.exportUnavailable":
		// biome-ignore lint/security/noSecrets: текст интерфейса, не секрет.
		"Системное меню «Поделиться» недоступно на этом устройстве.",
	"downloads.exportMissingTitle": "Файл не найден",
	"downloads.exportMissing":
		"Файла нет на устройстве. Удалите запись и скачайте заново.",
	"downloads.exportErrorTitle": "Не удалось экспортировать",
	"downloads.exportError":
		"Не удалось открыть системное меню. Попробуйте ещё раз.",
} as const;

export const downloadsEn: Record<keyof typeof downloadsRu, string> = {
	"downloads.title": "Downloads",
	"downloads.subtitle": "Video, audio and images without a network",
	"downloads.empty": "Nothing downloaded yet",
	"downloads.emptyHint":
		"Download a video or track — it will stay on the device and work offline.",
	"downloads.download": "Save offline",
	"downloads.downloading": "Saving…",
	"downloads.downloadingPercent": "{{percent}}%",
	"downloads.downloaded": "Offline",
	"downloads.retry": "Retry",
	"downloads.cancel": "Cancel",
	"downloads.delete": "Delete",
	"downloads.deleteTitle": "Delete file?",
	"downloads.deleteConfirm":
		"The file will be removed from the device. Playback in progress may be interrupted.",
	"downloads.errorNetwork":
		"Could not download the file. Check your network and retry.",
	"downloads.errorStatus": "The server rejected the download.",
	"downloads.errorSize": "The file size does not match the server response.",
	"downloads.errorStorage": "Could not save the file on the device.",
	"downloads.errorTimeout": "The download timed out.",
	"downloads.errorUnknown": "Could not download the file.",
	"downloads.errorTitle": "Download failed",
	"downloads.activeTitle": "Downloading",
	"downloads.doneTitle": "On device",
	"downloads.summary": "Files: {{count}} · {{size}}",
	"downloads.entryCount": "{{count}}",
	"downloads.dismiss": "Dismiss",
	"downloads.typeVideo": "Video",
	"downloads.typeAudio": "Audio",
	"downloads.typeImage": "Image",
	"downloads.progressLabel": "Download progress",
	"downloads.back": "Back",
	"downloads.export": "Export",
	"downloads.exportItem": "Export: {{title}}",
	"downloads.deleteItem": "Delete: {{title}}",
	"downloads.exportHint": "Opens the system share sheet",
	"downloads.exportDialog": "Share file",
	"downloads.exportUnavailableTitle": "Export unavailable",
	"downloads.exportUnavailable":
		"The system share sheet is not available on this device.",
	"downloads.exportMissingTitle": "File not found",
	"downloads.exportMissing":
		"The file is no longer on the device. Delete the entry and download it again.",
	"downloads.exportErrorTitle": "Could not export",
	"downloads.exportError": "The share sheet could not be opened. Try again.",
};
