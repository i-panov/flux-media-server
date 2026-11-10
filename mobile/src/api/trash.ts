import {
	ApiError,
	apiFetch,
	type Collection,
	collectionSchema,
	type Media,
	mediaSchema,
} from "@flux/shared";
import {
	type QueryClient,
	queryOptions,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";

export const trashQueryKey = ["trash"] as const;

export interface TrashData {
	collections: Collection[];
	media: Media[];
}

interface SchemaParser<T> {
	parse: (value: unknown) => T;
}

function parseList<T>(schema: SchemaParser<T>, value: unknown): T[] {
	if (!Array.isArray(value)) {
		throw new Error("Invalid trash response: expected arrays");
	}
	return value.map((item) => schema.parse(item));
}

// Корзина — два массива в одном ответе. Собираем схему из shared-схем,
// чтобы не тянуть zod в mobile как прямую зависимость.
export function parseTrash(body: unknown): TrashData {
	if (typeof body !== "object" || body === null) {
		throw new Error("Invalid trash response");
	}
	const record = body as { collections?: unknown; media?: unknown };
	return {
		collections: parseList(collectionSchema, record.collections),
		media: parseList(mediaSchema, record.media),
	};
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
	return error instanceof ApiError && error.status === 404;
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
	if (!(error instanceof ApiError)) {
		return "trash.actionError";
	}
	switch (error.status) {
		case 404:
			return "trash.missingError";
		case 409:
			return "trash.conflictError";
		case 403:
			return "trash.forbiddenError";
		default:
			return "trash.actionError";
	}
}

async function fetchTrash(signal?: AbortSignal): Promise<TrashData> {
	const body = await apiFetch<unknown>("/trash", { signal });
	return parseTrash(body);
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
			mutationFn: (id: number) =>
				apiFetch<unknown>(`/trash/media/${id}/restore`, { method: "POST" }),
			onSuccess: invalidate,
			onError,
		}),
		purgeMedia: useMutation({
			mutationFn: (id: number) =>
				apiFetch<unknown>(`/trash/media/${id}`, { method: "DELETE" }),
			onSuccess: invalidate,
			onError,
		}),
		restoreCollection: useMutation({
			mutationFn: (id: number) =>
				apiFetch<unknown>(`/trash/collections/${id}/restore`, {
					method: "POST",
				}),
			onSuccess: invalidate,
			onError,
		}),
		purgeCollection: useMutation({
			mutationFn: (id: number) =>
				apiFetch<unknown>(`/trash/collections/${id}`, { method: "DELETE" }),
			onSuccess: invalidate,
			onError,
		}),
		emptyTrash: useMutation({
			mutationFn: () => apiFetch<unknown>("/trash", { method: "DELETE" }),
			onSuccess: invalidate,
			onError,
		}),
	};
}
