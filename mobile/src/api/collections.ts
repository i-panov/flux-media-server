import {
	ApiError,
	addToCollection,
	apiFetch,
	type BulkResult,
	bulkMoveCollectionItems,
	bulkRemoveCollectionItems,
	type Collection,
	collectionSchema,
	createCollection,
	deleteCollection,
	fetchCollectionItems,
	fetchCollectionStats,
	fetchCollections,
	type Media,
	type MediaType,
	moveCollection,
	removeFromCollection,
	renameCollection,
} from "@flux/shared";
import {
	type QueryClient,
	queryOptions,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";

import { trashQueryKey } from "./trash";

export const collectionsQueryKey = ["collections"] as const;

/** Типы коллекций, в которые mobile умеет добавлять медиа. */
export type AddableCollectionType = "video" | "audio";

function collectionsQueryOptions() {
	return queryOptions({
		queryKey: collectionsQueryKey,
		queryFn: () => fetchCollections(),
		retry: false,
		refetchOnWindowFocus: false,
	});
}

// Один и тот же список делят экшены добавления и ряды на главных; фильтр
// по типу живёт в select, поэтому query-ключ остаётся общим с библиотекой.
function typedCollectionsQueryOptions(type: AddableCollectionType) {
	return queryOptions({
		...collectionsQueryOptions(),
		select: (collections: Collection[]) =>
			collections.filter((collection) => collection.type === type),
	});
}

export function useCollections() {
	return useQuery(collectionsQueryOptions());
}

export function useVideoCollections() {
	return useQuery(typedCollectionsQueryOptions("video"));
}

export function useAudioCollections() {
	return useQuery(typedCollectionsQueryOptions("audio"));
}

// Общий хук для sheet добавления: тип приходит из экрана (видео/аудио).
export function useCollectionsByType(type: AddableCollectionType) {
	return useQuery(typedCollectionsQueryOptions(type));
}

export function collectionItemsQueryKey(collectionId: number) {
	return ["collections", collectionId, "items"] as const;
}

export function collectionStatsQueryKey(collectionId: number) {
	return ["collections", collectionId, "stats"] as const;
}

function collectionQueryKey(collectionId: number) {
	return ["collections", collectionId] as const;
}

export function useCollectionItems(collectionId: number, enabled = true) {
	return useQuery({
		queryKey: collectionItemsQueryKey(collectionId),
		queryFn: (): Promise<Media[]> => fetchCollectionItems(collectionId),
		enabled,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useCollectionStats(collectionId: number, enabled = true) {
	return useQuery({
		queryKey: collectionStatsQueryKey(collectionId),
		queryFn: () => fetchCollectionStats(collectionId),
		enabled,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

// Инвалидация корневого ключа ["collections"] накрывает и вложенные
// items/stats: TanStack сравнивает ключи по префиксу. Один вызов вместо
// десятка точечных — после любой мутации список и счётчики согласованы.
function invalidateCollections(queryClient: QueryClient): void {
	void queryClient.invalidateQueries({ queryKey: collectionsQueryKey });
}

// 409 — видео уже в этой коллекции. Это не сетевая ошибка: показываем
// пользователю понятное сообщение, а не общий текст сбоя.
export function isAlreadyInCollection(error: unknown): boolean {
	return error instanceof ApiError && error.status === 409;
}

// 404 после удаления коллекции с другого устройства: экран должен
// показать «не найдена», а не общий сбой загрузки.
export function isCollectionMissing(error: unknown): boolean {
	return error instanceof ApiError && error.status === 404;
}

interface CreateCollectionInput {
	name: string;
	type: MediaType;
	parentId?: number | null;
}

// Общий createCollection не принимает parent_id, хотя backend умеет
// создавать подколлекцию одной транзакцией. Локальная обёртка шлёт тот же
// контракт через shared apiFetch; корень по-прежнему создаёт shared-функция.
async function createCollectionIn({
	name,
	type,
	parentId,
}: CreateCollectionInput): Promise<Collection> {
	if (parentId === undefined || parentId === null) {
		const body = await createCollection(name, type);
		return collectionSchema.parse(body);
	}
	const body = await apiFetch<unknown>("/collections", {
		method: "POST",
		body: JSON.stringify({ name, type, parent_id: parentId }),
	});
	return collectionSchema.parse(body);
}

export function useCreateCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: CreateCollectionInput) => createCollectionIn(input),
		onSuccess: () => invalidateCollections(queryClient),
	});
}

export function useRenameCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ id, name }: { id: number; name: string }) =>
			renameCollection(id, name),
		onSuccess: () => invalidateCollections(queryClient),
	});
}

// Удалённая коллекция сразу должна появиться в корзине: без инвалидации
// trash-кэш живёт до 30 секунд и Maestro/пользователь видят старый список.
export function invalidateAfterCollectionDelete(
	queryClient: QueryClient,
	id: number,
): void {
	// Удалённой коллекции больше нет: выкидываем её items/stats,
	// иначе фоновый рефетч вернёт 404 и оживит экран.
	queryClient.removeQueries({ queryKey: collectionQueryKey(id) });
	invalidateCollections(queryClient);
	void queryClient.invalidateQueries({ queryKey: trashQueryKey });
}

export function useDeleteCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) => deleteCollection(id),
		onSuccess: (_data, id) => invalidateAfterCollectionDelete(queryClient, id),
	});
}

export function useMoveCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ id, parentId }: { id: number; parentId: number | null }) =>
			moveCollection(id, parentId),
		onSuccess: () => invalidateCollections(queryClient),
	});
}

export function useAddMediaToCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			collectionId,
			mediaId,
		}: {
			collectionId: number;
			mediaId: number;
		}) => addToCollection(collectionId, mediaId),
		onSuccess: () => invalidateCollections(queryClient),
	});
}

export function useRemoveFromCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			collectionId,
			mediaId,
		}: {
			collectionId: number;
			mediaId: number;
		}) => removeFromCollection(collectionId, mediaId),
		onSuccess: () => invalidateCollections(queryClient),
	});
}

export interface BulkMoveCollectionItemsInput {
	sourceId: number;
	mediaIds: number[];
	toCollectionId: number;
}

export function useBulkMoveCollectionItems() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: BulkMoveCollectionItemsInput): Promise<BulkResult> =>
			bulkMoveCollectionItems(input.sourceId, {
				mediaIds: input.mediaIds,
				toCollectionId: input.toCollectionId,
			}),
		onSuccess: () => invalidateCollections(queryClient),
	});
}

export function useBulkRemoveCollectionItems() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			collectionId,
			mediaIds,
		}: {
			collectionId: number;
			mediaIds: number[];
		}): Promise<BulkResult> =>
			bulkRemoveCollectionItems(collectionId, mediaIds),
		onSuccess: () => invalidateCollections(queryClient),
	});
}
