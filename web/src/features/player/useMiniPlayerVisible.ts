import { useRouterState } from "@tanstack/react-router";
import { useAudioPlayer } from "./AudioPlayerProvider";

// Мини-плеер виден везде, кроме полной страницы плеера: там те же
// кнопки дублировались бы. От этого же зависит отступ контента.
export function useMiniPlayerVisible(): boolean {
	const player = useAudioPlayer();
	const pathname = useRouterState({
		select: (state) => state.location.pathname,
	});
	return player.current !== null && pathname !== "/player";
}
