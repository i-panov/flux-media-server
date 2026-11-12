import { apiFetch, type Media } from "@flux/shared";
import { useEventListener } from "expo";
import type { AudioMetadata, AudioPlayer, AudioStatus } from "expo-audio";
import { useCallback, useEffect, useRef, useState } from "react";
import { type AuthSource, authSource, streamPath } from "../media/source";
import { lockScreenArtwork } from "./lockScreenArtwork";

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
	/** Меняется на каждую загрузку/reload источника, даже с тем же mediaId. */
	generation: number;
	load: (media: Media, options: AudioSourceOptions) => void;
	recover: (media: Media, options: AudioSourceOptions) => void;
	unload: () => void;
	isLoaded: (mediaId: number) => boolean;
}

interface PendingSeek {
	mediaId: number;
	position: number;
	/** Намерение на момент flush: пользователь мог поставить паузу. */
	play: () => boolean;
}

// После seek проверяем фактическую позицию: нативный плеер может вернуть
// promise раньше, чем источник реально перемотался.
const SEEK_VERIFY_TOLERANCE_SECONDS = 1.5;

export function audioMetadataFor(media: Media): AudioMetadata {
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

function validSeekPosition(position: number | undefined): number | null {
	if (position === undefined || !Number.isFinite(position) || position <= 0) {
		return null;
	}
	return position;
}

async function trySeek(
	player: AudioPlayer,
	position: number,
): Promise<boolean> {
	try {
		await player.seekTo(position);
		const current = Number.isFinite(player.currentTime)
			? player.currentTime
			: 0;
		return Math.abs(current - position) <= SEEK_VERIFY_TOLERANCE_SECONDS;
	} catch {
		return false;
	}
}

// Локальный файл имеет приоритет над сетью; резолвер принимает mediaId,
// потому что current в changeTrack ещё указывает на предыдущий трек.
async function audioSourceFor(
	mediaId: number,
	getDownloadedPath: (mediaId: number) => string | null,
): Promise<AuthSource | null> {
	const downloadedPath = getDownloadedPath(mediaId);
	if (downloadedPath !== null) {
		return { uri: downloadedPath, headers: {} };
	}
	try {
		return await authSource(streamPath(mediaId));
	} catch {
		return null;
	}
}

function playIfWanted(player: AudioPlayer, wanted: () => boolean): void {
	try {
		if (wanted()) {
			player.play();
		}
	} catch {
		// Нативный плеер уже мог освободиться — ошибку покажет status.
	}
}

// Источник аудио живёт отдельно от очереди: replace меняет трек, а 401
// обрабатывается одним preflight-запросом.
// eslint-disable-next-line max-lines-per-function -- источник, preflight и restore позиции.
export function useAudioSource(
	player: AudioPlayer,
	getDownloadedPath: (mediaId: number) => string | null = () => null,
): AudioSourceController {
	const [failed, setFailed] = useState(false);
	const [loading, setLoading] = useState(false);
	const [generation, setGeneration] = useState(0);
	const mountedRef = useRef(true);
	const tokenRef = useRef(0);
	const loadedIdRef = useRef<number | null>(null);
	const retriedForRef = useRef<number | null>(null);
	const recoveringRef = useRef(false);
	// replace() может отклонить seek до загрузки: 401-позицию довозим позже.
	const pendingSeekRef = useRef<PendingSeek | null>(null);

	useEffect(() => {
		mountedRef.current = true;
		return () => {
			mountedRef.current = false;
			tokenRef.current += 1;
		};
	}, []);

	const apply = useCallback(
		async (
			media: Media,
			options: AudioSourceOptions,
			resetRetry: boolean,
			expectedLoadedId?: number,
		) => {
			// Guard внутри apply: recover мог доехать после смены трека и не
			// должен перетирать уже загруженный новый источник.
			if (
				expectedLoadedId !== undefined &&
				loadedIdRef.current !== expectedLoadedId
			) {
				return;
			}
			const token = ++tokenRef.current;
			pendingSeekRef.current = null;
			setGeneration((value) => value + 1);
			if (resetRetry) {
				retriedForRef.current = null;
			}
			setFailed(false);
			setLoading(true);
			const source = await audioSourceFor(media.id, getDownloadedPath);
			if (!mountedRef.current || token !== tokenRef.current) {
				return;
			}
			if (source === null) {
				setFailed(true);
				setLoading(false);
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
				const artwork = await lockScreenArtwork(media);
				player.setActiveForLockScreen(
					true,
					{
						...audioMetadataFor(media),
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
				// Играем без lock screen.
			}
			// Позицию (401/retry) не применяем до play: pending flush делает
			// status-listener после loading=false. Иначе звук стартовал бы с 0.
			const position = validSeekPosition(options.position);
			if (position !== null) {
				pendingSeekRef.current = {
					mediaId: media.id,
					position,
					play: options.play,
				};
			}
			if (mountedRef.current && token === tokenRef.current) {
				setLoading(false);
			}
			if (position === null) {
				playIfWanted(player, options.play);
			}
		},
		[getDownloadedPath, player],
	);

	// Flush pending seek после loading=false: если ждать только status,
	// загрузка на паузе могла бы не прислать следующий тик, и play завис бы.
	const flushPendingSeek = useCallback(
		(status: AudioStatus) => {
			const pending = pendingSeekRef.current;
			if (pending === null || !status.isLoaded) {
				return;
			}
			if (loadedIdRef.current !== pending.mediaId) {
				pendingSeekRef.current = null;
				return;
			}
			pendingSeekRef.current = null;
			if (status.duration <= 0) {
				// Live-поток без длительности: seek бессмыслен, play не теряем.
				playIfWanted(player, pending.play);
				return;
			}
			const target = Math.min(pending.position, status.duration);
			void (async () => {
				// Повторяем один раз: currentTime у нативного плеера может
				// обновиться с задержкой после resolve seekTo.
				if (!(await trySeek(player, target))) {
					await trySeek(player, target);
				}
				if (loadedIdRef.current !== pending.mediaId) {
					return;
				}
				playIfWanted(player, pending.play);
			})();
		},
		[player],
	);

	useEventListener(player, "playbackStatusUpdate", (status) => {
		if (loading || !status.isLoaded) {
			return;
		}
		flushPendingSeek(status);
	});

	useEffect(() => {
		if (loading || pendingSeekRef.current === null) {
			return;
		}
		flushPendingSeek(player.currentStatus);
	}, [flushPendingSeek, loading, player]);

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
			const loadedId = loadedIdRef.current;
			if (loadedId === null) {
				return;
			}
			retriedForRef.current = media.id;
			recoveringRef.current = true;
			// Preflight — часть загрузки: пауза, нажатая во время него,
			// должна отменить авто-возобновление после refresh.
			setLoading(true);
			// Токен и загруженный трек фиксируем до preflight: пока он идёт,
			// пользователь мог выбрать другой трек или очистить очередь.
			const token = tokenRef.current;
			void (async () => {
				try {
					await apiFetch<unknown>(`/media/${media.id}`);
					if (
						!mountedRef.current ||
						token !== tokenRef.current ||
						loadedIdRef.current !== loadedId
					) {
						return;
					}
					await apply(media, options, false, loadedId);
				} catch {
					if (
						mountedRef.current &&
						token === tokenRef.current &&
						loadedIdRef.current === loadedId
					) {
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
		pendingSeekRef.current = null;
		setGeneration((value) => value + 1);
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

	return { failed, loading, generation, load, recover, unload, isLoaded };
}
