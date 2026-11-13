export {
	type AuthUser,
	approveDeviceCode,
	createDeviceCode,
	type DeviceCodeResponse,
	type DeviceInspectResponse,
	type DevicePollResponse,
	type DeviceSession,
	fetchDevices,
	fetchMe,
	inspectDeviceCode,
	logout,
	pollDeviceCode,
	type RequestCodeResponse,
	renameDevice,
	requestCode,
	revokeDevice,
	type VerifyCodeResponse,
	verifyCode,
} from "./api/auth";
export {
	ApiError,
	apiFetch,
	apiFetchBlob,
	getHealth,
	type HealthResponse,
} from "./api/client";
export {
	addToCollection,
	type BulkMoveCollectionItemsInput,
	type BulkResult,
	bulkAddCollectionItems,
	bulkMoveCollectionItems,
	bulkRemoveCollectionItems,
	bulkResultSchema,
	type Collection,
	type CollectionStats,
	collectionSchema,
	collectionStatsSchema,
	createCollection,
	deleteCollection,
	fetchCollectionItems,
	fetchCollectionStats,
	fetchCollections,
	moveCollection,
	moveCollectionItem,
	removeFromCollection,
	renameCollection,
} from "./api/collections";
export {
	type Favorite,
	favoriteSchema,
	favoritesListSchema,
	fetchFavoriteArtistIds,
	fetchFavoriteMedia,
	isStaleFavoriteError,
	toggleArtistFavorite,
	toggleFavorite,
} from "./api/favorites";
export { type HealthSnapshot, useHealthQuery } from "./api/health";
export {
	fetchLyrics,
	type Lyrics,
	lyricsSchema,
	type SaveLyricsInput,
	saveLyrics,
} from "./api/lyrics";
export {
	type ContinueEntry,
	deleteProgress,
	fetchContinueWatching,
	fetchLatestUnfinishedAudio,
	fetchProgress,
	isUnfinishedProgress,
	type Progress,
	type ProgressEntry,
	progressEntrySchema,
	progressListSchema,
	progressSchema,
	type SaveProgressInput,
	saveProgress,
} from "./api/progress";
export type { CredentialsMode } from "./api/transport";
export {
	ACCESS_TOKEN_KEY,
	type ApiConfig,
	type AuthTransport,
	configureApi,
	createTokenTransport,
	createWebTransport,
	getApiConfig,
	REFRESH_TOKEN_KEY,
	resetApiConfig,
} from "./api/transport";
export * from "./core/audioQueue";
export * from "./core/format";
export * from "./core/lyricsSync";
export * from "./core/media";
export { type QrMatrix, qrMatrix } from "./qr";
export { createQueryClient } from "./query";
export type { KeyValueStore } from "./storage";
