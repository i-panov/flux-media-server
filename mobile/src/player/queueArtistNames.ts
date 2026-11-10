import type { AudioQueueState } from "@flux/shared";

// Переименование артиста не меняет id в media.artists, поэтому очередь
// можно обновить без перезагрузки треков: имя подставляется по artist_id.
// Возвращаем тот же объект, если менять нечего — иначе эффект в
// AudioProvider зациклил бы запись очереди в AsyncStorage.
export function applyArtistNames(
	state: AudioQueueState,
	names: ReadonlyMap<number, string>,
): AudioQueueState {
	let stateChanged = false;
	const items = state.items.map((media) => {
		let mediaChanged = false;
		const artists = media.artists.map((artist) => {
			const name = names.get(artist.id);
			if (name === undefined || name === artist.name) {
				return artist;
			}
			mediaChanged = true;
			return { ...artist, name };
		});
		if (!mediaChanged) {
			return media;
		}
		stateChanged = true;
		return { ...media, artists };
	});
	return stateChanged ? { ...state, items } : state;
}
