import type { MediaType } from "../core/media";

// Подписи типов медиа (переводы media.*): корзина и шапка коллекции.
export const MEDIA_TYPE_LABEL_KEYS: Record<MediaType, string> = {
	video: "media.video",
	audio: "media.audio",
	image: "media.memes",
};

export function isMediaType(value: string): value is MediaType {
	return value === "video" || value === "audio" || value === "image";
}
