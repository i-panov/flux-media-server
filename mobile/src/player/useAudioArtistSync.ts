import type { AudioQueueState, Media } from "@flux/shared";
import type { AudioPlayer } from "expo-audio";
import { type Dispatch, type SetStateAction, useEffect } from "react";
import { useMediaArtists } from "../api/metadata";
import { lockScreenArtwork } from "./lockScreenArtwork";
import { applyArtistNames } from "./queueArtistNames";
import { audioMetadataFor } from "./useAudioSource";

// Переименование артиста не трогает id в media.artists: обновляем имена
// прямо в очереди (включая сохранённую в AsyncStorage) и метаданные
// lock screen, не перезагружая источник и не теряя позицию.
export function useAudioArtistSync(
	queueState: AudioQueueState,
	setQueueState: Dispatch<SetStateAction<AudioQueueState>>,
	current: Media | null,
	player: AudioPlayer,
	isLoaded: (mediaId: number) => boolean,
): void {
	const artists = useMediaArtists(queueState.items.length > 0);

	useEffect(() => {
		if (artists.data === undefined) {
			return;
		}
		const names = new Map(
			artists.data.map((artist) => [artist.id, artist.name] as const),
		);
		setQueueState((previous) => applyArtistNames(previous, names));
	}, [artists.data, setQueueState]);

	useEffect(() => {
		if (current === null || !isLoaded(current.id)) {
			return;
		}
		void (async () => {
			try {
				const artwork = await lockScreenArtwork(current);
				player.setActiveForLockScreen(
					true,
					{
						...audioMetadataFor(current),
						...(artwork === undefined ? {} : { artworkUrl: artwork }),
					},
					{
						showSeekForward: true,
						showSeekBackward: true,
						seekForwardIntervalSeconds: 10,
						seekBackwardIntervalSeconds: 10,
					},
				);
			} catch {
				// Нет разрешения/платформы — играем без lock screen.
			}
		})();
	}, [current, isLoaded, player]);
}
