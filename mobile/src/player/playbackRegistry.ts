// Кто сейчас загружен в аудио/видео плеер. Нужен квоте скачиваний, чтобы
// не вытеснить файл, который прямо сейчас воспроизводится.
let playingMediaId: number | null = null;

export function setPlayingMediaId(id: number | null): void {
	playingMediaId = id;
}

export function getPlayingMediaId(): number | null {
	return playingMediaId;
}
