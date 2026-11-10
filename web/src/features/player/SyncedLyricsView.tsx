import { type SyncedLyricLine, syncedLyricIndex } from "@flux/shared";
import { Stack, Text } from "@mantine/core";
import { useEffect, useRef } from "react";
import { useAudioPlayer } from "./AudioPlayerProvider";

// Построчный синхронный текст (только вкладка лирики): текущая строка
// подсвечивается по позиции воспроизведения, список держит её в виду.
export function SyncedLyricsView({ lines }: { lines: SyncedLyricLine[] }) {
	const { currentTime } = useAudioPlayer();
	const active = syncedLyricIndex(lines, currentTime);
	const activeRef = useRef<HTMLParagraphElement | null>(null);

	// Эффект должен выполняться при каждой смене активной строки,
	// хотя тело её не читает (работает через ref).
	// biome-ignore lint/correctness/useExhaustiveDependencies: timing matters, not values
	useEffect(() => {
		activeRef.current?.scrollIntoView({ block: "nearest" });
	}, [active]);

	return (
		<Stack gap={4} className="max-h-96 overflow-y-auto" role="list">
			{lines.map((line, position) => {
				const isActive = position === active;
				return (
					<Text
						// Строка без времени уникальна только позицией в файле.
						// biome-ignore lint/suspicious/noArrayIndexKey: synced lyric line
						key={position}
						ref={isActive ? activeRef : undefined}
						role="listitem"
						aria-current={isActive ? "true" : undefined}
						size={isActive ? "md" : "sm"}
						fw={isActive ? 700 : 400}
						c={isActive ? undefined : "dimmed"}
						ta="center"
					>
						{line.text === "" ? "…" : line.text}
					</Text>
				);
			})}
		</Stack>
	);
}
