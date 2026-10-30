import type { RefObject } from "react";

export function HiddenAudio({
	audioRef,
	src,
	onLoadedMetadata,
	onTimeUpdate,
	onSeeked,
	onPlay,
	onPause,
	onEnded,
	onError,
}: {
	audioRef: RefObject<HTMLAudioElement | null>;
	src: string | undefined;
	onLoadedMetadata: (event: React.SyntheticEvent<HTMLAudioElement>) => void;
	onTimeUpdate: (event: React.SyntheticEvent<HTMLAudioElement>) => void;
	onSeeked: (event: React.SyntheticEvent<HTMLAudioElement>) => void;
	onPlay: () => void;
	onPause: () => void;
	onEnded: () => void;
	onError: () => void;
}) {
	return (
		// biome-ignore lint/a11y/useMediaCaption: у аудио нет видеоряда и субтитров.
		<audio
			ref={audioRef}
			src={src}
			preload="metadata"
			className="hidden"
			onLoadedMetadata={onLoadedMetadata}
			onTimeUpdate={onTimeUpdate}
			onSeeked={onSeeked}
			onPlay={onPlay}
			onPause={onPause}
			onEnded={onEnded}
			onError={onError}
		/>
	);
}
