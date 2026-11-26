import { useState } from "react";
import {
	ActivityIndicator,
	Alert,
	Modal,
	Pressable,
	ScrollView,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useBulkMediaTags, useTags } from "../api/tags";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

// Массовая разметка: выбрать тег и добавить/убрать его у всех выбранных.
export function BulkTagsSheet({
	mediaIDs,
	onClose,
}: {
	mediaIDs: number[];
	onClose: () => void;
}) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const insets = useSafeAreaInsets();
	const tags = useTags();
	const bulk = useBulkMediaTags();
	const [tagID, setTagID] = useState<number | null>(null);
	const [add, setAdd] = useState(true);
	const selectedTag = (tags.data ?? []).find((tag) => tag.id === tagID);
	const tooMany = mediaIDs.length > 500;
	const canApply =
		tagID !== null && mediaIDs.length > 0 && !tooMany && !bulk.isPending;
	return (
		<Modal visible transparent animationType="slide" onRequestClose={onClose}>
			<Pressable style={styles.backdrop} onPress={onClose}>
				<Pressable
					onPress={() => undefined}
					style={[
						styles.sheet,
						{
							backgroundColor: colors.surface,
							borderRadius: radii.lg,
							padding: spacing.lg,
							paddingBottom: spacing.lg + insets.bottom,
							gap: spacing.sm,
						},
					]}
				>
					<View style={[styles.row, styles.between]}>
						<Text style={{ color: colors.text, fontWeight: "600" }}>
							{t("bulk.title", { count: mediaIDs.length })}
						</Text>
						<Pressable
							accessibilityRole="button"
							onPress={onClose}
							testID="bulk-tags-close"
						>
							<Text style={{ color: colors.textMuted }}>
								{t("common.close")}
							</Text>
						</Pressable>
					</View>
					<ScrollView style={{ maxHeight: 320 }}>
						<View style={[styles.wrap, { gap: spacing.xs }]}>
							{(tags.data ?? []).map((tag) => {
								const active = tag.id === tagID;
								return (
									<Pressable
										key={tag.id}
										accessibilityRole="button"
										accessibilityState={{ selected: active }}
										testID={`bulk-tag-${tag.id}`}
										onPress={() => setTagID(tag.id)}
										style={[
											styles.chip,
											{
												borderColor: active ? colors.accent : colors.border,
												backgroundColor: active
													? colors.surfaceMuted
													: colors.surface,
												borderRadius: radii.pill,
												paddingHorizontal: spacing.sm,
											},
										]}
									>
										<Text
											style={{
												color: active ? colors.accent : colors.text,
											}}
										>
											{tag.name} · {t(`bulk.group.${tag.group}`)}
										</Text>
									</Pressable>
								);
							})}
						</View>
					</ScrollView>
					<View style={[styles.row, { gap: spacing.sm }]}>
						{[
							{ value: true, label: t("bulk.add") },
							{ value: false, label: t("bulk.remove") },
						].map((mode) => (
							<Pressable
								key={String(mode.value)}
								accessibilityRole="button"
								accessibilityState={{ selected: add === mode.value }}
								onPress={() => setAdd(mode.value)}
								style={[
									styles.chip,
									{
										borderColor:
											add === mode.value ? colors.accent : colors.border,
										backgroundColor:
											add === mode.value ? colors.surfaceMuted : colors.surface,
										borderRadius: radii.pill,
										paddingHorizontal: spacing.md,
									},
								]}
							>
								<Text
									style={{
										color: add === mode.value ? colors.accent : colors.text,
									}}
								>
									{mode.label}
								</Text>
							</Pressable>
						))}
					</View>
					<Pressable
						accessibilityRole="button"
						disabled={!canApply}
						testID="bulk-tags-apply"
						onPress={() => {
							if (tagID === null) {
								return;
							}
							const apply = () =>
								bulk.mutate(
									{ mediaIDs, tagID, add },
									{
										onSuccess: onClose,
										onError: () =>
											Alert.alert(t("common.error"), t("tags.saveError")),
									},
								);
							// Format-тег заменяет формат у всех выбранных — спрашиваем.
							if (add && selectedTag?.group === "format") {
								Alert.alert(
									t("bulk.formatTitle"),
									t("bulk.formatBody", { name: selectedTag.name }),
									[
										{ text: t("common.cancel"), style: "cancel" },
										{ text: t("bulk.applyShort"), onPress: apply },
									],
								);
								return;
							}
							apply();
						}}
						style={[
							styles.apply,
							{
								backgroundColor: colors.accent,
								borderRadius: radii.md,
								opacity: canApply ? 1 : 0.5,
							},
						]}
					>
						{tooMany ? (
							<Text style={{ color: colors.onAccent, fontWeight: "600" }}>
								{t("bulk.tooMany")}
							</Text>
						) : bulk.isPending ? (
							<ActivityIndicator color={colors.onAccent} />
						) : (
							<Text style={{ color: colors.onAccent, fontWeight: "600" }}>
								{t("bulk.apply", { count: mediaIDs.length })}
							</Text>
						)}
					</Pressable>
				</Pressable>
			</Pressable>
		</Modal>
	);
}

const styles = StyleSheet.create({
	backdrop: { flex: 1, justifyContent: "flex-end", backgroundColor: "#0008" },
	sheet: { maxHeight: "90%" },
	row: { flexDirection: "row", alignItems: "center" },
	between: { justifyContent: "space-between" },
	wrap: { flexDirection: "row", flexWrap: "wrap" },
	chip: { borderWidth: 1, paddingVertical: 6 },
	apply: { alignItems: "center", paddingVertical: 12 },
});
