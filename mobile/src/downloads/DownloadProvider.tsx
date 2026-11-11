import { getApiConfig, type Media } from "@flux/shared";
import AsyncStorage from "@react-native-async-storage/async-storage";
import * as FileSystem from "expo-file-system/legacy";
import {
	createContext,
	type ReactNode,
	useCallback,
	useContext,
	useEffect,
	useMemo,
	useRef,
	useState,
} from "react";
import { useLocalReset } from "../auth/reset";
import {
	clearDownloadDirectory,
	hydrateDownloads,
	removeFile,
	runDownload,
} from "./downloadRunner";
import {
	DOWNLOAD_INDEX_KEY,
	type DownloadEntry,
	type DownloadFailure,
	type DownloadRemovalPlan,
	findDownloadEntry,
	planDownloadRemoval,
	resolveDownloadedPath,
	serializeDownloadIndex,
} from "./downloadStore";

export interface ActiveDownload {
	readonly media: Media;
	readonly status: "downloading" | "error";
	/** Доля 0..1; null — сервер не прислал Content-Length. */
	readonly progress: number | null;
	readonly failure: DownloadFailure | null;
}

export interface DownloadState {
	/** AsyncStorage-индекс прочитан: до этого local path ещё неизвестен. */
	readonly hydrated: boolean;
	readonly entries: readonly DownloadEntry[];
	readonly active: readonly ActiveDownload[];
}

export type DownloadIndicatorStatus = "downloading" | "downloaded" | "error";

export interface DownloadIndicatorState {
	readonly status: DownloadIndicatorStatus;
	readonly progress: number | null;
}

export interface DownloadActions {
	start: (media: Media) => void;
	cancel: (mediaId: number) => void;
	retry: (media: Media) => void;
	remove: (mediaId: number) => void;
	/** Смена сервера: старые файлы и индекс больше не принадлежат origin. */
	clearAll: () => void;
}

const DownloadStateContext = createContext<DownloadState | null>(null);
const DownloadActionsContext = createContext<DownloadActions | null>(null);
const DownloadLookupContext = createContext<
	((mediaId: number) => string | null) | null
>(null);

export function useDownloadState(): DownloadState {
	const value = useContext(DownloadStateContext);
	if (value === null) {
		throw new Error("useDownloadState must be used inside DownloadProvider");
	}
	return value;
}

export function useDownloadActions(): DownloadActions {
	const value = useContext(DownloadActionsContext);
	if (value === null) {
		throw new Error("useDownloadActions must be used inside DownloadProvider");
	}
	return value;
}

// Индикатор для карточек и кнопок: активная загрузка важнее завершённой
// записи (при повторном скачивании поверх старого файла).
export function useDownloadIndicator(
	mediaId: number,
): DownloadIndicatorState | null {
	const { active, entries, hydrated } = useDownloadState();
	if (!hydrated) {
		return null;
	}
	const activeItem = active.find((item) => item.media.id === mediaId);
	if (activeItem !== undefined) {
		return activeItem.status === "downloading"
			? { status: "downloading", progress: activeItem.progress }
			: { status: "error", progress: null };
	}
	if (findDownloadEntry(entries, mediaId) !== null) {
		return { status: "downloaded", progress: null };
	}
	return null;
}

// Локальный источник для плеера: пока индекс не прочитан, null — экран
// успеет начать сетевую загрузку, а после рестарта файл найдётся.
export function useDownloadedPath(mediaId: number): string | null {
	const { hydrated, entries } = useDownloadState();
	return resolveDownloadedPath(
		entries,
		hydrated,
		mediaId,
		FileSystem.documentDirectory,
	);
}

// Императивный резолвер для плеера: вызывается внутри loadSource с id
// нового трека. State-хук здесь не подходит — при changeTrack замыкание
// ещё видит previous current и мог бы подсунуть чужой скачанный файл.
export function useDownloadedPathResolver(): (
	mediaId: number,
) => string | null {
	const value = useContext(DownloadLookupContext);
	if (value === null) {
		throw new Error(
			"useDownloadedPathResolver must be used inside DownloadProvider",
		);
	}
	return value;
}

interface ClearDownloadsContext {
	readonly tokens: Map<number, number>;
	readonly bumpToken: (mediaId: number) => number;
	readonly tasks: Map<number, FileSystem.DownloadResumable>;
	readonly partPaths: Map<number, string>;
	readonly setActive: (next: ActiveDownload[]) => void;
	readonly setEntries: (next: DownloadEntry[]) => void;
	readonly persist: (next: readonly DownloadEntry[]) => void;
}

function clearAllDownloads(context: ClearDownloadsContext): void {
	for (const mediaId of [...context.tokens.keys()]) {
		context.bumpToken(mediaId);
	}
	for (const task of context.tasks.values()) {
		void task.cancelAsync().catch(() => undefined);
	}
	context.tasks.clear();
	context.partPaths.clear();
	context.setActive([]);
	context.setEntries([]);
	context.persist([]);
	void clearDownloadDirectory();
}

// Отмена нативной задачи и удаление .part не должны блокировать UI:
// запускаем в фоне, ошибки уже завершившейся задачи игнорируем.
function disposeTask(
	task: FileSystem.DownloadResumable | undefined,
	partPath: string | undefined,
): void {
	if (task === undefined && partPath === undefined) {
		return;
	}
	void (async () => {
		if (task !== undefined) {
			try {
				await task.cancelAsync();
			} catch {
				// Нативная задача уже завершилась.
			}
		}
		if (partPath !== undefined) {
			await removeFile(partPath);
		}
	})();
}

interface MutableRef<T> {
	current: T;
}

// Стабильный резолвер локального пути: читает refs в момент вызова, поэтому
// плеер не получает устаревший снимок индекса после commit/clearAll.
function useStoredDownloadedPath(
	entriesRef: MutableRef<DownloadEntry[]>,
	hydratedRef: MutableRef<boolean>,
): (mediaId: number) => string | null {
	return useCallback(
		(mediaId: number) =>
			resolveDownloadedPath(
				entriesRef.current,
				hydratedRef.current,
				mediaId,
				FileSystem.documentDirectory,
			),
		[entriesRef, hydratedRef],
	);
}

// Индекс и persist — до удаления файла: ошибка FS не должна оставлять
// запись, указывающую на уже удалённый файл.
function applyDownloadRemoval(
	plan: DownloadRemovalPlan,
	setEntries: (entries: DownloadEntry[]) => void,
	persist: (entries: readonly DownloadEntry[]) => void,
): void {
	if (plan.entry === null) {
		return;
	}
	setEntries(plan.next);
	persist(plan.next);
	if (plan.path !== null) {
		void removeFile(plan.path);
	}
}

interface DownloadHydrationOptions {
	readonly setEntries: (entries: DownloadEntry[]) => void;
	readonly setHydrated: (hydrated: boolean) => void;
	readonly persist: (entries: readonly DownloadEntry[]) => void;
	readonly mountedRef: MutableRef<boolean>;
	readonly activeRef: MutableRef<ActiveDownload[]>;
	readonly tasksRef: MutableRef<Map<number, FileSystem.DownloadResumable>>;
	readonly hydratedRef: MutableRef<boolean>;
	readonly resetRef: MutableRef<number>;
}

function useDownloadHydration(options: DownloadHydrationOptions): void {
	const {
		setEntries,
		setHydrated,
		persist,
		mountedRef,
		activeRef,
		tasksRef,
		hydratedRef,
		resetRef,
	} = options;
	useEffect(() => {
		const version = resetRef.current;
		mountedRef.current = true;
		void hydrateDownloads(
			{
				// clearAll (смена сервера) отменяет незавершённую гидратацию:
				// иначе поздний ответ вернул бы записи удалённого origin.
				isMounted: () => mountedRef.current && resetRef.current === version,
				setEntries,
				persist,
				activeCount: () => activeRef.current.length,
			},
			getApiConfig().baseUrl,
		).finally(() => {
			if (mountedRef.current) {
				hydratedRef.current = true;
				setHydrated(true);
			}
		});
		const tasks = tasksRef.current;
		return () => {
			mountedRef.current = false;
			for (const task of tasks.values()) {
				void task.cancelAsync().catch(() => undefined);
			}
			tasks.clear();
		};
	}, [
		activeRef,
		hydratedRef,
		mountedRef,
		persist,
		resetRef,
		setEntries,
		setHydrated,
		tasksRef,
	]);
}

export function DownloadProvider({ children }: { children: ReactNode }) {
	const [entries, setEntriesState] = useState<DownloadEntry[]>([]);
	const [active, setActiveState] = useState<ActiveDownload[]>([]);
	const [hydrated, setHydrated] = useState(false);
	const entriesRef = useRef<DownloadEntry[]>([]);
	const activeRef = useRef<ActiveDownload[]>([]);
	const tasksRef = useRef(new Map<number, FileSystem.DownloadResumable>());
	const partPathsRef = useRef(new Map<number, string>());
	const tokensRef = useRef(new Map<number, number>());
	const persistChain = useRef<Promise<void>>(Promise.resolve());
	const mountedRef = useRef(true);
	const hydratedRef = useRef(false);
	const resetRef = useRef(0);

	const setEntries = useCallback((next: DownloadEntry[]) => {
		entriesRef.current = next;
		setEntriesState(next);
	}, []);

	const setActive = useCallback((next: ActiveDownload[]) => {
		activeRef.current = next;
		setActiveState(next);
	}, []);

	// Записи индекса сериализуем цепочкой: remove и finish могут прийти
	// почти одновременно, а последний setItem должен отражать свежий список.
	const persist = useCallback((next: readonly DownloadEntry[]) => {
		const payload = serializeDownloadIndex(next, getApiConfig().baseUrl);
		persistChain.current = persistChain.current
			.then(() => AsyncStorage.setItem(DOWNLOAD_INDEX_KEY, payload))
			.catch(() => {
				// Недоступное хранилище: файлы останутся, индекс потеряется
				// при рестарте. Скачивание от этого не должно падать.
			});
	}, []);

	const bumpToken = useCallback((mediaId: number): number => {
		const next = (tokensRef.current.get(mediaId) ?? 0) + 1;
		tokensRef.current.set(mediaId, next);
		return next;
	}, []);

	const isCurrent = useCallback(
		(mediaId: number, token: number): boolean =>
			mountedRef.current && tokensRef.current.get(mediaId) === token,
		[],
	);

	const updateActive = useCallback(
		(mediaId: number, patch: { progress: number | null }) => {
			setActive(
				activeRef.current.map((item) => {
					return item.media.id === mediaId ? { ...item, ...patch } : item;
				}),
			);
		},
		[setActive],
	);

	const removeActive = useCallback(
		(mediaId: number) => {
			setActive(activeRef.current.filter((item) => item.media.id !== mediaId));
		},
		[setActive],
	);

	const fail = useCallback(
		(mediaId: number, failure: DownloadFailure) => {
			if (!mountedRef.current) {
				return;
			}
			setActive(
				activeRef.current.map((item) => {
					return item.media.id === mediaId
						? { ...item, status: "error", progress: null, failure }
						: item;
				}),
			);
		},
		[setActive],
	);

	useDownloadHydration({
		setEntries,
		setHydrated,
		persist,
		mountedRef,
		activeRef,
		tasksRef,
		hydratedRef,
		resetRef,
	});

	const startDownload = useCallback(
		(media: Media, token: number): Promise<void> => {
			return runDownload(media, token, {
				isCurrent,
				fail,
				updateActive,
				removeActive,
				setEntries,
				persist,
				tasks: tasksRef.current,
				partPaths: partPathsRef.current,
				entries: () => entriesRef.current,
				active: () => activeRef.current,
			});
		},
		[fail, isCurrent, persist, removeActive, setEntries, updateActive],
	);

	const start = useCallback(
		(media: Media) => {
			if (!mountedRef.current || !hydratedRef.current) {
				return;
			}
			if (findDownloadEntry(entriesRef.current, media.id) !== null) {
				return;
			}
			const busy = activeRef.current.some(
				(item) => item.media.id === media.id && item.status === "downloading",
			);
			if (busy) {
				return;
			}
			const token = bumpToken(media.id);
			setActive([
				...activeRef.current.filter((item) => item.media.id !== media.id),
				{ media, status: "downloading", progress: null, failure: null },
			]);
			void startDownload(media, token);
		},
		[bumpToken, setActive, startDownload],
	);

	const cancel = useCallback(
		(mediaId: number) => {
			bumpToken(mediaId);
			const task = tasksRef.current.get(mediaId);
			tasksRef.current.delete(mediaId);
			const partPath = partPathsRef.current.get(mediaId);
			partPathsRef.current.delete(mediaId);
			removeActive(mediaId);
			disposeTask(task, partPath);
		},
		[bumpToken, removeActive],
	);

	const remove = useCallback(
		(mediaId: number) => {
			// Пока идёт повторная загрузка, удалять готовую запись нельзя:
			// commit мог бы воскресить её после удаления. UI блокирует кнопку,
			// это вторая линия защиты для вызовов вне экрана.
			const downloading = activeRef.current.some((item) => {
				return item.media.id === mediaId && item.status === "downloading";
			});
			if (downloading) {
				return;
			}
			bumpToken(mediaId);
			const task = tasksRef.current.get(mediaId);
			tasksRef.current.delete(mediaId);
			const partPath = partPathsRef.current.get(mediaId);
			partPathsRef.current.delete(mediaId);
			removeActive(mediaId);
			const plan = planDownloadRemoval(
				entriesRef.current,
				mediaId,
				FileSystem.documentDirectory,
			);
			applyDownloadRemoval(plan, setEntries, persist);
			disposeTask(task, partPath);
		},
		[bumpToken, persist, removeActive, setEntries],
	);

	const clearAll = useCallback(() => {
		resetRef.current += 1;
		clearAllDownloads({
			tokens: tokensRef.current,
			bumpToken,
			tasks: tasksRef.current,
			partPaths: partPathsRef.current,
			setActive,
			setEntries,
			persist,
		});
	}, [bumpToken, persist, setActive, setEntries]);

	// Logout и смена сервера: индекс/файлы/активные задачи принадлежат
	// прошлому origin и пользователю. Повторный сброс безопасен (задачи
	// отменяются, каталог удаляется идемпотентно).
	useLocalReset(clearAll);

	const actions = useMemo<DownloadActions>(
		() => ({ start, cancel, retry: start, remove, clearAll }),
		[cancel, clearAll, remove, start],
	);
	const state = useMemo<DownloadState>(
		() => ({ hydrated, entries, active }),
		[hydrated, entries, active],
	);
	const getDownloadedPath = useStoredDownloadedPath(entriesRef, hydratedRef);

	return (
		<DownloadLookupContext.Provider value={getDownloadedPath}>
			<DownloadActionsContext.Provider value={actions}>
				<DownloadStateContext.Provider value={state}>
					{children}
				</DownloadStateContext.Provider>
			</DownloadActionsContext.Provider>
		</DownloadLookupContext.Provider>
	);
}
