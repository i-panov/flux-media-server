// Совместимый реэкспорт: модели, схемы и fetch-функции переехали в
// @flux/shared, чтобы их мог использовать mobile. Список намеренно
// именованный: старый контракт ../core/media не должен превращаться в
// второй barrel всего пакета.
export type {
	CoreFetcher,
	Media,
	MediaKind,
	MediaType,
} from "@flux/shared";
export {
	audioListOptions,
	fetchMediaList,
	imageListOptions,
	isSafeImageUrl,
	mediaOptions,
	mediaSchema,
	mediaSubsOptions,
	videoListOptions,
} from "@flux/shared";
