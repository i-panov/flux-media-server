export const PLAYBACK_ERROR = "Playback failed";

export function playAudio(
	element: HTMLAudioElement,
	onError: (message: string) => void,
): void {
	void element.play().catch((error: unknown) => {
		onError(error instanceof Error ? error.message : PLAYBACK_ERROR);
	});
}
