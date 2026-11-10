import type { Lyrics } from "@flux/shared";
import { useCallback, useEffect, useMemo, useRef } from "react";
import {
	ScrollView,
	type ScrollViewInstance,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { t, useLanguage } from "../i18n";
import {
	highlightLineIndex,
	type LyricsTab,
	syncedLines,
} from "../lyrics/lyricsView";
import { useTheme } from "../theme/ThemeProvider";
import { EmptyState } from "./EmptyState";

interface LyricsViewProps {
	lyrics: Lyrics | null;
	tab: LyricsTab;
	/** Текущая позиция играющего трека (секунды). */
	position: number;
	/** id маршрута совпадает с текущим треком — только тогда есть подсветка. */
	isCurrentTrack: boolean;
	/** Админ может добавить текст из пустого состояния. */
	onAdd?: () => void;
}

// Отступ сверху при автопрокрутке: активная строка не липнет к краю.
const ACTIVE_LINE_OFFSET = 96;

// Текст/перевод и синхронизированные строки. Подсветка работает только
// для текущего трека: для чужого позиция плеера к нему не относится.
export function LyricsView({
	lyrics,
	tab,
	position,
	isCurrentTrack,
	onAdd,
}: LyricsViewProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const syncData = lyrics?.sync_data ?? "";
	const lines = useMemo(() => syncedLines(syncData), [syncData]);
	const text =
		tab === "translation"
			? (lyrics?.translation ?? "")
			: (lyrics?.lyrics_text ?? "");
	const synced = tab === "lyrics" && lines.length > 0;
	const activeIndex = synced
		? highlightLineIndex(lines, position, isCurrentTrack)
		: -1;
	const scrollRef = useRef<ScrollViewInstance>(null);
	// Смещения строк приходят из onLayout: строки переносятся и имеют
	// разную высоту, поэтому фиксированная высота для scrollTo не подходит.
	const offsets = useRef<Record<number, number>>({});

	const scrollToLine = useCallback((index: number) => {
		const y = offsets.current[index];
		if (y === undefined) {
			return;
		}
		scrollRef.current?.scrollTo({
			y: Math.max(y - ACTIVE_LINE_OFFSET, 0),
			animated: true,
		});
	}, []);

	useEffect(() => {
		if (activeIndex >= 0) {
			scrollToLine(activeIndex);
		}
	}, [activeIndex, scrollToLine]);

	if (text.trim() === "" && !synced) {
		return (
			<EmptyState
				icon="document-text-outline"
				title={t("audio.lyrics.empty")}
				description={
					onAdd === undefined ? undefined : t("audio.lyrics.emptyHint")
				}
				actionLabel={onAdd === undefined ? undefined : t("audio.lyrics.add")}
				onActionPress={onAdd}
				testID="audio-lyrics-empty"
			/>
		);
	}

	if (!synced) {
		return (
			<ScrollView
				key={tab}
				ref={scrollRef}
				testID="audio-lyrics-plain"
				style={styles.fill}
				contentContainerStyle={{ padding: spacing.sm }}
			>
				<Text
					selectable
					style={[
						styles.plainText,
						{ color: colors.text, padding: spacing.xs },
					]}
				>
					{text}
				</Text>
			</ScrollView>
		);
	}

	return (
		<ScrollView
			key={`lyrics-${syncData}`}
			ref={scrollRef}
			testID="audio-lyrics-lines"
			style={styles.fill}
			contentContainerStyle={[
				styles.lines,
				{ padding: spacing.xs, gap: spacing.xs },
			]}
		>
			{lines.map((line, index) => {
				const active = index === activeIndex;
				return (
					<View
						// biome-ignore lint/suspicious/noArrayIndexKey: одинаковые время/текст в LRC не редкость, индекс делает ключ уникальным.
						key={`${line.time}-${index}`}
						onLayout={(event) => {
							offsets.current[index] = event.nativeEvent.layout.y;
							if (active) {
								scrollToLine(index);
							}
						}}
						testID={
							active ? `lyrics-line-${index}-active` : `lyrics-line-${index}`
						}
						accessibilityState={{ selected: active }}
						style={[
							styles.line,
							{
								borderRadius: radii.sm,
								paddingHorizontal: spacing.sm,
								paddingVertical: spacing.xs,
							},
							active && {
								backgroundColor: colors.surfaceMuted,
								borderLeftColor: colors.accent,
								borderLeftWidth: 3,
							},
						]}
					>
						<Text
							accessibilityLiveRegion={active ? "polite" : "none"}
							style={[
								styles.lineText,
								{
									color: active ? colors.accent : colors.text,
									fontWeight: active ? "700" : "400",
								},
							]}
						>
							{line.text === "" ? "♪" : line.text}
						</Text>
					</View>
				);
			})}
		</ScrollView>
	);
}

const styles = StyleSheet.create({
	fill: { flex: 1 },
	plainText: { fontSize: 16, lineHeight: 24 },
	lines: { paddingBottom: 32 },
	line: { flexDirection: "row", alignItems: "center" },
	lineText: { flexShrink: 1, fontSize: 16, lineHeight: 24 },
});
