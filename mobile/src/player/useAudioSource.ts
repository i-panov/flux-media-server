import { apiFetch, type Media } from "@flux/shared";
import type { AudioMetadata, AudioPlayer } from "expo-audio";
import { useCallback, useEffect, useRef, useState } from "react";
import { authSource, streamPath } from "../media/source";

export interface AudioSourceOptions {
	/**
	 * Решение о старте принимается в момент окончания replace: пользователь
	 * мог нажать паузу, пока источник грузился.
	 */
	play: () => boolean;
	position?: number;
}

export interface AudioSourceController {
	failed: boolean;
	loading: boolean;
	load: (media: Media, options: AudioSourceOptions) => void;
	recover: (media: Media, options: AudioSourceOptions) => void;
	unload: () => void;
	isLoaded: (mediaId: number) => boolean;
}

function metadataFor(media: Media): AudioMetadata {
	const artist = media.artists
		.map((entry) => entry.name)
		.filter((name) => name !== "")
		.join(", ");
	// artworkUrl не передаём осознанно: обложка требует Bearer-заголовков,
	// а lock screen их не отправит. Без artwork лучше, чем битая/пустая
	// ссылка; публичный URL появится — можно добавить отдельным условием.
	return {
		title: media.title,
		...(artist === "" ? {} : { artist }),
		...(media.album === "" ? {} : { albumTitle: media.album }),
	};
}

function seekToStart(player: AudioPlayer, position: number | undefined): void {
	if (position === undefined || !Number.isFinite(position) || position <= 0) {
		return;
	}
	player.seekTo(position).catch(() => {
		// Недогруженный источник может отклонить seek — начнём с нуля.
	});
}

// Источник аудио живёт отдельно от очереди: authSource перечитывает токен,
// replace меняет трек, а 401 обрабатывается одним preflight-запросом.
// Плеер создаётся пустым снаружи, поэтому здесь нет нативного конструктора.
export function useAudioSource(player: AudioPlayer): AudioSourceController {
	const [failed, setFailed] = useState(false);
	const [loading, setLoading] = useState(false);
	const mountedRef = useRef(true);
	const tokenRef = useRef(0);
	const loadedIdRef = useRef<number | null>(null);
	const retriedForRef = useRef<number | null>(null);
	const recoveringRef = useRef(false);

	useEffect(() => {
		mountedRef.current = true;
		return () => {
			mountedRef.current = false;
			tokenRef.current += 1;
		};
	}, []);

	const apply = useCallback(
		async (media: Media, options: AudioSourceOptions, resetRetry: boolean) => {
			const token = ++tokenRef.current;
			if (resetRetry) {
				retriedForRef.current = null;
			}
			setFailed(false);
			setLoading(true);
			let source: Awaited<ReturnType<typeof authSource>>;
			try {
				source = await authSource(streamPath(media.id));
			} catch {
				if (mountedRef.current && token === tokenRef.current) {
					setFailed(true);
					setLoading(false);
				}
				return;
			}
			if (!mountedRef.current || token !== tokenRef.current) {
				return;
			}
			try {
				player.replace(source);
				loadedIdRef.current = media.id;
			} catch {
				loadedIdRef.current = null;
				if (mountedRef.current && token === tokenRef.current) {
					setFailed(true);
					setLoading(false);
				}
				return;
			}
			try {
				// Ошибка lock screen (нет разрешения/платформы) не должна
				// помечать источник сломанным: звук при этом уже загружен.
				player.setActiveForLockScreen(true, metadataFor(media));
			} catch {
				// Играем без lock screen.
			}
			seekToStart(player, options.position);
			try {
				if (options.play()) {
					player.play();
				}
			} catch {
				if (mountedRef.current && token === tokenRef.current) {
					loadedIdRef.current = null;
					setFailed(true);
				}
			}
			if (mountedRef.current && token === tokenRef.current) {
				setLoading(false);
			}
		},
		[player],
	);

	const load = useCallback(
		(media: Media, options: AudioSourceOptions) => {
			void apply(media, options, true);
		},
		[apply],
	);

	// Один preflight на трек: apiFetch обновит токен, после чего источник
	// перечитается с новым Bearer. Повторная ошибка того же трека уходит
	// в failed — цикла нет.
	const recover = useCallback(
		(media: Media, options: AudioSourceOptions) => {
			if (recoveringRef.current) {
				return;
			}
			if (retriedForRef.current === media.id) {
				setFailed(true);
				return;
			}
			retriedForRef.current = media.id;
			recoveringRef.current = true;
			// Preflight — часть загрузки: пауза, нажатая во время него,
			// должна отменить авто-возобновление после refresh.
			setLoading(true);
			void (async () => {
				try {
					await apiFetch<unknown>(`/media/${media.id}`);
					if (mountedRef.current) {
						await apply(media, options, false);
					}
				} catch {
					if (mountedRef.current) {
						setFailed(true);
						setLoading(false);
					}
				} finally {
					recoveringRef.current = false;
				}
			})();
		},
		[apply],
	);

	const unload = useCallback(() => {
		tokenRef.current += 1;
		loadedIdRef.current = null;
		retriedForRef.current = null;
		setFailed(false);
		setLoading(false);
		try {
			player.pause();
			player.replace(null);
			player.setActiveForLockScreen(false);
		} catch {
			// Игрок уже освобождён (размонтирование) — чистить нечего.
		}
	}, [player]);

	const isLoaded = useCallback(
		(mediaId: number) => loadedIdRef.current === mediaId,
		[],
	);

	return { failed, loading, load, recover, unload, isLoaded };
}
