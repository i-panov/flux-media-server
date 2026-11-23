import { createFileRoute } from "@tanstack/react-router";
import { AudioPage } from "../features/audio/AudioPage";

export const Route = createFileRoute("/audio/")({
	// ?play=<id> — «Открыть трек» со страницы видео: список сразу
	// включает извлечённую дорожку. Детальной страницы аудио нет.
	validateSearch: (search: Record<string, unknown>): { play?: number } => {
		const raw = Number(search.play);
		return Number.isFinite(raw) && raw > 0 ? { play: raw } : {};
	},
	component: AudioPage,
});
