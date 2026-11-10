import Ionicons from "@expo/vector-icons/Ionicons";
import { router } from "expo-router";
import type { ComponentProps } from "react";
import {
	FlatList,
	Modal,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { EmptyState } from "../components/EmptyState";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { useAudioActions, useAudioState } from "./AudioProvider";
import { formatAudioTime } from "./audioLabels";

type IoniconName = ComponentProps<typeof Ionicons>["name"];

interface QueueActionProps {
	icon: IoniconName;
	label: string;
	testID: string;
	onPress: () => void;
	disabled?: boolean;
}

function QueueAction({
	icon,
	label,
	testID,
	onPress,
	disabled = false,
}: QueueActionProps) {
	const { colors } = useTheme();
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={label}
			accessibilityState={{ disabled }}
			disabled={disabled}
			onPress={onPress}
			testID={testID}
			hitSlop={4}
			style={({ pressed }) => [
				styles.action,
				disabled && styles.disabled,
				pressed && styles.pressed,
			]}
		>
			<Ionicons
				name={icon}
				size={20}
				color={disabled ? colors.borderStrong : colors.textMuted}
			/>
		</Pressable>
	);
}

interface AudioQueueSheetProps {
	visible: boolean;
	onClose: () => void;
}

// Очередь полного плеера: текущий и следующие треки, перестановка стрелками
// (без новых зависимостей и drag), удаление и очистка. Тап по строке
// выбирает трек и закрывает лист.
export function AudioQueueSheet({ visible, onClose }: AudioQueueSheetProps) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const { queue, index } = useAudioState();
	const { select, move, removeAt, clear } = useAudioActions();

	const clearAll = () => {
		clear();
		onClose();
	};

	return (
		<Modal
			visible={visible}
			transparent
			animationType="slide"
			onRequestClose={onClose}
		>
			<View style={[styles.backdrop, { backgroundColor: colors.overlay }]}>
				<SafeAreaView
					edges={["bottom"]}
					testID="audio-queue-sheet"
					style={[
						styles.sheet,
						{ backgroundColor: colors.surface, borderColor: colors.border },
					]}
				>
					<View
						style={[
							styles.header,
							{ borderBottomColor: colors.border, padding: spacing.md },
						]}
					>
						<View style={styles.headerText}>
							<Text style={[styles.title, { color: colors.text }]}>
								{t("audio.player.queue")}
							</Text>
							<Text style={[styles.muted, { color: colors.textMuted }]}>
								{t("audio.player.queueCount", { count: queue.length })}
							</Text>
						</View>
						<QueueAction
							icon="trash-outline"
							label={t("audio.player.clearQueue")}
							testID="audio-queue-clear"
							onPress={clearAll}
							disabled={queue.length === 0}
						/>
						<QueueAction
							icon="close"
							label={t("audio.player.dismiss")}
							testID="audio-queue-close"
							onPress={onClose}
						/>
					</View>
					{queue.length === 0 ? (
						<EmptyState
							icon="list-outline"
							title={t("audio.player.empty")}
							testID="audio-queue-empty"
						/>
					) : (
						<FlatList
							data={queue}
							keyExtractor={(item, position) => `${item.id}-${position}`}
							contentContainerStyle={[
								styles.list,
								{ padding: spacing.sm, gap: spacing.xs },
							]}
							renderItem={({ item, index: position }) => {
								const selected = position === index;
								const artists = item.artists
									.map((artist) => artist.name)
									.join(", ");
								return (
									<View
										style={[
											styles.row,
											{
												borderColor: selected ? colors.accent : colors.border,
												backgroundColor: selected
													? colors.surfaceMuted
													: colors.background,
												borderRadius: 10,
												gap: spacing.xs,
												paddingHorizontal: spacing.sm,
												paddingVertical: spacing.xs,
											},
										]}
									>
										<Pressable
											accessibilityRole="button"
											accessibilityLabel={item.title}
											accessibilityState={{ selected }}
											onPress={() => {
												select(position);
												onClose();
											}}
											testID={`audio-queue-row-${position}`}
											style={({ pressed }) => [
												styles.selectZone,
												pressed && styles.pressed,
											]}
										>
											<View style={styles.rowInfo}>
												<View
													style={[styles.rowTitleLine, { gap: spacing.xs }]}
												>
													<Text
														numberOfLines={1}
														style={[styles.rowTitle, { color: colors.text }]}
													>
														{item.title}
													</Text>
													{selected && (
														<Text
															style={[styles.badge, { color: colors.accent }]}
														>
															{t("audio.player.queueCurrent")}
														</Text>
													)}
												</View>
												<Text
													numberOfLines={1}
													style={[styles.muted, { color: colors.textMuted }]}
												>
													{artists === ""
														? t("audio.player.unknownArtist")
														: artists}
													{` · ${formatAudioTime(item.duration)}`}
												</Text>
											</View>
										</Pressable>
										<QueueAction
											icon="document-text-outline"
											label={`${item.title} — ${t("audio.lyrics.open")}`}
											testID={`audio-queue-lyrics-${position}`}
											onPress={() => {
												onClose();
												router.push(`/audio/${item.id}`);
											}}
										/>
										<QueueAction
											icon="chevron-up"
											label={t("audio.player.moveUp")}
											testID={`audio-queue-up-${position}`}
											onPress={() => move(position, position - 1)}
											disabled={position === 0}
										/>
										<QueueAction
											icon="chevron-down"
											label={t("audio.player.moveDown")}
											testID={`audio-queue-down-${position}`}
											onPress={() => move(position, position + 1)}
											disabled={position === queue.length - 1}
										/>
										<QueueAction
											icon="remove-circle-outline"
											label={t("audio.player.remove")}
											testID={`audio-queue-remove-${position}`}
											onPress={() => {
												removeAt(position);
												if (queue.length === 1) {
													onClose();
												}
											}}
										/>
									</View>
								);
							}}
						/>
					)}
				</SafeAreaView>
			</View>
		</Modal>
	);
}

const styles = StyleSheet.create({
	backdrop: {
		flex: 1,
		justifyContent: "flex-end",
	},
	sheet: {
		minHeight: 240,
		maxHeight: "75%",
		borderTopWidth: 1,
		borderTopLeftRadius: 16,
		borderTopRightRadius: 16,
	},
	header: {
		flexDirection: "row",
		alignItems: "center",
		gap: 4,
		borderBottomWidth: 1,
	},
	headerText: { flex: 1 },
	title: { fontSize: 17, fontWeight: "700" },
	muted: { fontSize: 13 },
	list: { flexGrow: 1 },
	row: { flexDirection: "row", alignItems: "center", borderWidth: 1 },
	selectZone: { flex: 1, justifyContent: "center" },
	rowInfo: { flex: 1 },
	rowTitleLine: { flexDirection: "row", alignItems: "center" },
	rowTitle: { flexShrink: 1, fontSize: 15, fontWeight: "600" },
	badge: { fontSize: 11, fontWeight: "700" },
	action: {
		minHeight: 44,
		minWidth: 40,
		alignItems: "center",
		justifyContent: "center",
	},
	disabled: { opacity: 0.4 },
	pressed: { opacity: 0.7 },
});
