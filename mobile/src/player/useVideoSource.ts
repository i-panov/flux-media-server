import { apiFetch } from "@flux/shared";
import { useEventListener } from "expo";
import type { VideoPlayer as NativeVideoPlayer } from "expo-video";
import { useCallback, useEffect, useRef, useState } from "react";
import { useDownloadedPath } from "../downloads/DownloadProvider";
import { type AuthSource, authSource, streamPath } from "../media/source";
import { clampSeek, seekPlayer, updatePlaybackRate } from "./videoControls";

interface ResumeState {
	mediaId: number;
	position: number;
	playing: boolean;
	rate: number;
}

interface UseVideoSourceOptions {
	mediaId: number;
	player: NativeVideoPlayer;
	/** Сброс позиции/первого кадра при установке нового источника. */
	onSourceReset: () => void;
	/** Вернуть восстановленную после 401 позицию в UI. */
	onPositionRestored: (seconds: number) => void;
	/** Сообщить, что после 401 playback восстановлен (для hasStarted). */
	onPlaybackRestored: (playing: boolean) => void;
}

interface VideoSourceState {
	sourceReady: boolean;
	failed: boolean;
	retry: () => void;
}

// Источник живёт отдельно от UI, чтобы не раздувать VideoPlayer: здесь
// загрузка authSource, replaceAsync, восстановление после 401 и одноразовый
// ретрай. Плеер всегда создаётся без source, потому что после refresh токена
// uri/заголовки могут не измениться и авто-замена из хука не сработает.
export function useVideoSource({
	mediaId,
	player,
	onSourceReset,
	onPositionRestored,
	onPlaybackRestored,
}: UseVideoSourceOptions): VideoSourceState {
	const mountedRef = useRef(true);
	// Один автоповтор на video id: ключ не даёт зациклиться на повторных error.
	const retriedFor = useRef<number | null>(null);
	const resumeRef = useRef<ResumeState | null>(null);
	// Новый loadSource отменяет результат предыдущего (retry/смена медиа).
	const loadToken = useRef(0);
	const downloadedPath = useDownloadedPath(mediaId);
	// Ref, а не зависимость loadSource: завершение скачивания во время
	// playback не должно перезагружать уже играющий источник.
	const downloadedPathRef = useRef(downloadedPath);
	// Какой источник реально ушёл в player: нужен, чтобы не перезагружать
	// уже играющий локальный файл и поймать позднюю гидратацию индекса.
	const appliedPathRef = useRef<string | null>(null);
	const [sourceReady, setSourceReady] = useState(false);
	const [sourceFailed, setSourceFailed] = useState(false);
	const [playerFailed, setPlayerFailed] = useState(false);

	useEffect(() => {
		downloadedPathRef.current = downloadedPath;
	}, [downloadedPath]);

	useEffect(() => {
		mountedRef.current = true;
		return () => {
			mountedRef.current = false;
		};
	}, []);

	const applySource = useCallback(
		async (next: AuthSource) => {
			if (!mountedRef.current) {
				return;
			}
			onSourceReset();
			setSourceFailed(false);
			setPlayerFailed(false);
			setSourceReady(false);
			try {
				await player.replaceAsync(next);
				if (!mountedRef.current) {
					return;
				}
				const resume = resumeRef.current;
				resumeRef.current = null;
				if (resume !== null && resume.mediaId === mediaId) {
					const target = clampSeek(resume.position, 0, player.duration);
					seekPlayer(player, target);
					onPositionRestored(target);
					// iOS может запустить playback от смены rate — возвращаем паузу,
					// если до ошибки видео было на паузе.
					updatePlaybackRate(player, resume.rate, resume.playing);
					if (resume.playing) {
						player.play();
					}
					onPlaybackRestored(resume.playing);
				}
				setSourceReady(true);
			} catch {
				if (mountedRef.current) {
					setPlayerFailed(true);
				}
			}
		},
		[mediaId, onPlaybackRestored, onPositionRestored, onSourceReset, player],
	);

	const loadSource = useCallback(async () => {
		const token = ++loadToken.current;
		// Скачанный файл играем напрямую с диска: офлайн-режим и отсутствие
		// сетевых заголовков. Иначе authSource перечитывает SecureStore:
		// после refresh токена запрос уходит с новым Bearer.
		const localPath = downloadedPathRef.current;
		appliedPathRef.current = localPath;
		const next =
			localPath === null
				? await authSource(streamPath(mediaId)).catch(() => null)
				: { uri: localPath, headers: {} };
		if (!mountedRef.current || token !== loadToken.current) {
			return;
		}
		if (next === null) {
			setSourceFailed(true);
			return;
		}
		await applySource(next);
	}, [applySource, mediaId]);

	const reloadSource = useCallback(() => {
		if (!mountedRef.current) {
			return;
		}
		setSourceReady(false);
		setSourceFailed(false);
		void loadSource();
	}, [loadSource]);

	useEffect(() => {
		void loadSource();
	}, [loadSource]);

	// Офлайн-старт: индекс мог прочитаться после первой сетевой попытки.
	// Переключаемся на файл, только пока playback не начался, — иначе
	// завершение скачивания рвало бы уже идущий просмотр.
	useEffect(() => {
		if (
			downloadedPath === null ||
			downloadedPath === appliedPathRef.current ||
			sourceReady ||
			player.playing
		) {
			return;
		}
		reloadSource();
	}, [downloadedPath, player, reloadSource, sourceReady]);

	const retry = useCallback(() => {
		retriedFor.current = null;
		resumeRef.current = null;
		reloadSource();
	}, [reloadSource]);

	// На первую ошибку плеера не полагаемся на текст (iOS может не отдать 401):
	// один раз бьём preflight в общий слой. apiFetch сам обновит токен на 401,
	// после чего перечитываем source с актуальным Bearer. Второй error на то же
	// видео уходит в error-оверлей — цикла нет.
	const recoverFromPlayerError = useCallback(async () => {
		if (retriedFor.current === mediaId) {
			setPlayerFailed(true);
			return;
		}
		retriedFor.current = mediaId;
		resumeRef.current = {
			mediaId,
			position: Number.isFinite(player.currentTime) ? player.currentTime : 0,
			playing: player.playing,
			rate: player.playbackRate,
		};
		setSourceReady(false);
		try {
			await apiFetch<unknown>(`/media/${mediaId}`);
			if (mountedRef.current) {
				reloadSource();
			}
		} catch {
			if (mountedRef.current) {
				setPlayerFailed(true);
			}
		}
	}, [mediaId, player, reloadSource]);

	useEventListener(player, "statusChange", ({ status }) => {
		if (status === "readyToPlay") {
			setPlayerFailed(false);
			return;
		}
		if (status === "error") {
			void recoverFromPlayerError();
		}
	});

	return {
		sourceReady,
		failed: sourceFailed || playerFailed,
		retry,
	};
}
