import {
	fetchTrash as fetchSharedTrash,
	isTrashMissing as isSharedTrashMissing,
	parseTrash as parseSharedTrash,
	type TrashData as SharedTrashData,
	trashErrorKey as sharedTrashErrorKey,
	trashActions,
} from "@flux/shared";
import {
	type QueryClient,
	queryOptions,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";

export const trashQueryKey = ["trash"] as const;

export type TrashData = SharedTrashData;

// Корзина — два массива в одном ответе. Собираем схему из shared-схем,
// чтобы не тянуть zod в mobile как прямую зависимость.
export function parseTrash(body: unknown): TrashData {
	return parseSharedTrash(body);
}

// Пустая корзина для экрана, пока данных ещё нет: один литерал вместо
// нового массива на каждый рендер.
export const EMPTY_TRASH: TrashData = { collections: [], media: [] };

export function trashCount(data: TrashData): number {
	return data.collections.length + data.media.length;
}

export function isTrashEmpty(data: TrashData): boolean {
	return trashCount(data) === 0;
}

// 404 — объект уже восстановили/удалили с другого устройства. Это не
// сетевой сбой: экран должен обновить список, а не повторять запрос.
export function isTrashMissing(error: unknown): boolean {
	return isSharedTrashMissing(error);
}

export type TrashErrorKey =
	| "trash.missingError"
	| "trash.conflictError"
	| "trash.forbiddenError"
	| "trash.actionError";

// Статусы, которые пользователь должен увидеть отдельным текстом:
// 404 — запись устарела, 409 — файл недоступен/уже существует,
// 403 — чужая коллекция или нехватка прав.
export function trashErrorKey(error: unknown): TrashErrorKey {
	return sharedTrashErrorKey(error);
}

async function fetchTrash(signal?: AbortSignal): Promise<TrashData> {
	return await fetchSharedTrash(signal);
}

function trashQueryOptions() {
	return queryOptions({
		queryKey: trashQueryKey,
		queryFn: ({ signal }) => fetchTrash(signal),
		// Корзина меняется из чужих экранов (delete media/collection):
		// не держим её 30 секунд по общему дефолту.
		staleTime: 0,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useTrash() {
	return useQuery(trashQueryOptions());
}

// Корзина влияет не только на список: восстановленное медиа может снова
// оказаться в избранном/продолжить, а purge — убрать его оттуда. Поэтому
// инвалидируем и зависимые подборки, иначе «мёртвые» карточки останутся.
export function invalidateTrash(queryClient: QueryClient): void {
	void queryClient.invalidateQueries({ queryKey: trashQueryKey });
	void queryClient.invalidateQueries({ queryKey: ["media"] });
	void queryClient.invalidateQueries({ queryKey: ["collections"] });
	void queryClient.invalidateQueries({ queryKey: ["favorites"] });
	void queryClient.invalidateQueries({ queryKey: ["progress"] });
}

// Мутации не держат общий isPending для всего списка: экран показывает
// спиннер на конкретной строке по variables.id.
export function useTrashActions() {
	const queryClient = useQueryClient();
	const invalidate = () => invalidateTrash(queryClient);
	const onError = (error: unknown) => {
		// 404 значит, что показанный список устарел: сбрасываем его сразу,
		// не дожидаясь ручного retry.
		if (isTrashMissing(error)) {
			invalidate();
		}
	};

	return {
		restoreMedia: useMutation({
			mutationFn: (id: number) => trashActions.restoreMedia(id),
			onSuccess: invalidate,
			onError,
		}),
		purgeMedia: useMutation({
			mutationFn: (id: number) => trashActions.purgeMedia(id),
			onSuccess: invalidate,
			onError,
		}),
		restoreCollection: useMutation({
			mutationFn: (id: number) => trashActions.restoreCollection(id),
			onSuccess: invalidate,
			onError,
		}),
		purgeCollection: useMutation({
			mutationFn: (id: number) => trashActions.purgeCollection(id),
			onSuccess: invalidate,
			onError,
		}),
		emptyTrash: useMutation({
			mutationFn: () => trashActions.emptyTrash(),
			onSuccess: invalidate,
			onError,
		}),
	};
}
