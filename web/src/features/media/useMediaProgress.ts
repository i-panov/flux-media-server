import { useCallback, useEffect, useRef, useState } from "react";
import {
	useDeleteProgress,
	useProgress,
	useSaveProgress,
} from "../../api/progress";

// Позиция уходит на сервер не чаще раза в столько секунд воспроизведения.
const SAVE_EVERY_SECONDS = 10;
// Ближе этого к концу считаем просмотр завершённым.
const COMPLETED_TAIL_SECONDS = 5;

// Общий прогресс для видео и аудио: HTMLMediaElement, поэтому тип элемента
// задаёт вызывающий (HTMLVideoElement / HTMLAudioElement).
//
// restoreDriftSeconds — допуск дрейфа автоплея при восстановлении: аудио
// стартует раньше, чем приходит сохранённая позиция, и набежавшие доли
// секунды — не «пользователь уже смотрит». У видео автоплея нет, поэтому
// там допуск нулевой: ручной старт в первые секунды позиция не перекрывает.
//
export function useMediaProgress<E extends HTMLMediaElement>(
	mediaId: number,
	mediaRef: React.RefObject<E | null>,
	enabled = true,
	restoreDriftSeconds = 0,
) {
	// Состояние живёт в refs: объект результата useMutation — новый на каждом
	const progressQuery = useProgress(enabled ? mediaId : 0, enabled);
	const { mutate } = useSaveProgress();
	const { mutate: remove } = useDeleteProgress();
	// Готовность метаданных привязана к mediaId: при смене id она сама
	// становится ложной, без setState в эффекте.
	const [metadataFor, setMetadataFor] = useState<number | null>(null);
	const metadataReady = metadataFor === mediaId;

	// Последняя известная позиция переживает открепление рефа при
	// размонтировании: cleanup эффекта не может прочитать DOM.
	const lastPosition = useRef(0);
	const lastDuration = useRef(0);
	// Флаг «реально измерялась ненулевая позиция»: отличает сброс
	// пользователем (отмотка в начало после просмотра) от нуля
	// неизмеренного элемента (ошибка потока, уход до старта) — во втором
	// случае DELETE стёр бы восстановленную серверную запись.
	const playedOnce = useRef(false);
	// -1: ещё ничего не отправляли, первая позиция уйдёт всегда.
	const savedPosition = useRef(-1);
	const restored = useRef(false);

	// mutate из useMutation стабилен, но храним его в ref, чтобы ни один
	// обработчик не зависел от объекта мутации.
	const send = useRef(mutate);
	const drop = useRef(remove);
	useEffect(() => {
		send.current = mutate;
	}, [mutate]);
	useEffect(() => {
		drop.current = remove;
	}, [remove]);

	const flush = useCallback(
		(id: number, position: number, duration: number) => {
			const pos = Math.max(Math.floor(position), 0);
			const dur = Math.max(Math.floor(duration), 0);
			// Позиция за пределами длительности — испорченный элемент.
			if (dur > 0 && pos > dur) {
				return;
			}
			// Ноль — не «нечего сохранять», а сброс в начало: серверная
			// запись удаляется, переоткрытие стартует с 0. Но только если
			// в этой сессии реально играло (см. playedOnce): иначе ошибка
			// потока или уход до старта стёрли бы восстановленную позицию.
			if (pos === 0) {
				if (!playedOnce.current) {
					return;
				}
				if (savedPosition.current === 0) {
					return;
				}
				savedPosition.current = 0;
				drop.current(id);
				return;
			}
			if (pos === savedPosition.current) {
				return;
			}
			savedPosition.current = pos;
			send.current({
				mediaId: id,
				position: pos,
				duration: dur,
				completed: dur > 0 && pos >= dur - COMPLETED_TAIL_SECONDS,
			});
		},
		[],
	);

	// Сброс при смене mediaId; cleanup эффекта сохранения ниже выполняется
	// раньше и успевает записать позицию под старым id.
	// biome-ignore lint/correctness/useExhaustiveDependencies: mediaId — триггер сброса, в теле эффекта не читается.
	useEffect(() => {
		restored.current = false;
		lastPosition.current = 0;
		lastDuration.current = 0;
		playedOnce.current = false;
		savedPosition.current = -1;
	}, [mediaId]);

	const readElement = useCallback((el: E) => {
		const current = Math.floor(el.currentTime);
		if (current >= 0) {
			lastPosition.current = current;
		}
		if (current > 0) {
			playedOnce.current = true;
		}
		if (Number.isFinite(el.duration) && el.duration > 0) {
			lastDuration.current = Math.floor(el.duration);
		}
	}, []);

	const handleLoadedMetadata = useCallback(() => {
		const el = mediaRef.current;
		if (el === null) {
			return;
		}
		readElement(el);
		setMetadataFor(mediaId);
	}, [mediaId, readElement, mediaRef]);

	const handleTimeUpdate = useCallback(() => {
		const el = mediaRef.current;
		if (el === null) {
			return;
		}
		readElement(el);
		const current = lastPosition.current;
		if (
			current > 0 &&
			current % SAVE_EVERY_SECONDS === 0 &&
			current !== savedPosition.current
		) {
			flush(mediaId, current, lastDuration.current);
		}
	}, [flush, mediaId, readElement, mediaRef]);

	const handlePause = useCallback(() => {
		const el = mediaRef.current;
		if (el !== null) {
			readElement(el);
		}
		flush(mediaId, lastPosition.current, lastDuration.current);
	}, [flush, mediaId, readElement, mediaRef]);

	const handleEnded = useCallback(() => {
		const el = mediaRef.current;
		if (el !== null) {
			readElement(el);
		}
		flush(mediaId, lastPosition.current, lastDuration.current);
	}, [flush, mediaId, readElement, mediaRef]);

	// Восстановление запускается и по приходу данных, и по готовности
	// метаданных: порядок этих событий не определён. Флаг restored
	// выставляется только когда решение действительно принято.
	useEffect(() => {
		if (!enabled || !metadataReady || restored.current) {
			return;
		}
		const data = progressQuery.data;
		if (data === undefined) {
			return;
		}
		restored.current = true;
		const el = mediaRef.current;
		if (el === null) {
			return;
		}
		const position = data?.position ?? 0;
		const duration = Number.isFinite(el.duration) ? el.duration : 0;
		if (position <= 0 || (duration > 0 && position > duration)) {
			return;
		}
		if (el.currentTime > restoreDriftSeconds) {
			return;
		}
		el.currentTime = position;
		lastPosition.current = position;
		if (duration > 0) {
			lastDuration.current = Math.floor(duration);
		}
		savedPosition.current = position;
	}, [
		enabled,
		metadataReady,
		progressQuery.data,
		mediaRef,
		restoreDriftSeconds,
	]);

	// Сохранение при уходе со страницы и при смене mediaId. Слушатели
	// пересоздаются вместе с id, а cleanup попадает в замыкание со старым
	// mediaId — успевшая накопиться позиция уходит под правильным id.
	useEffect(() => {
		const saveNow = () => {
			flush(mediaId, lastPosition.current, lastDuration.current);
		};
		const onVisibility = () => {
			if (document.visibilityState === "hidden") {
				saveNow();
			}
		};
		document.addEventListener("visibilitychange", onVisibility);
		window.addEventListener("beforeunload", saveNow);
		return () => {
			saveNow();
			document.removeEventListener("visibilitychange", onVisibility);
			window.removeEventListener("beforeunload", saveNow);
		};
	}, [flush, mediaId]);

	return {
		handleLoadedMetadata,
		handlePause,
		handleTimeUpdate,
		handleEnded,
	};
}
