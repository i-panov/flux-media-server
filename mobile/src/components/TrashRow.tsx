import Ionicons from "@expo/vector-icons/Ionicons";
import { router } from "expo-router";
import type { ComponentProps, ReactNode } from "react";
import {
	ActivityIndicator,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

type IoniconName = ComponentProps<typeof Ionicons>["name"];

// Deep link может открыть корзину первым — назад ведёт в библиотеку.
function closeTrash(): void {
	if (router.canGoBack()) {
		router.back();
		return;
	}
	router.replace("/settings");
}

export function mediaIcon(type: string): IoniconName {
	if (type === "audio") {
		return "musical-notes-outline";
	}
	if (type === "image") {
		return "image-outline";
	}
	return "videocam-outline";
}

export function collectionIcon(type: string): IoniconName {
	if (type === "audio") {
		return "musical-notes-outline";
	}
	if (type === "image") {
		return "image-outline";
	}
	return "folder-outline";
}

export function TrashHeader() {
	const { colors } = useTheme();
	return (
		<View style={styles.header}>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("common.back")}
				onPress={closeTrash}
				testID="trash-back"
				hitSlop={8}
				style={({ pressed }) => [
					styles.headerButton,
					pressed && styles.pressed,
				]}
			>
				<Ionicons name="chevron-back" size={24} color={colors.text} />
			</Pressable>
			<Text
				testID="trash-title"
				style={[styles.headerTitle, { color: colors.text }]}
			>
				{t("trash.title")}
			</Text>
			<View style={styles.headerButton} />
		</View>
	);
}

export function TrashEmptyButton({ onPress }: { onPress: () => void }) {
	const { colors, radii, spacing } = useTheme();
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={t("trash.emptyAction")}
			onPress={onPress}
			testID="trash-empty"
			style={({ pressed }) => [
				styles.emptyButton,
				{
					borderColor: colors.danger,
					backgroundColor: colors.surface,
					borderRadius: radii.sm,
					gap: spacing.sm,
					paddingHorizontal: spacing.md,
				},
				pressed && styles.pressed,
			]}
		>
			<Ionicons name="trash-outline" size={18} color={colors.danger} />
			<Text style={[styles.emptyButtonLabel, { color: colors.danger }]}>
				{t("trash.emptyAction")}
			</Text>
		</Pressable>
	);
}

export interface TrashRowProps {
	testID: string;
	title: string;
	typeLabel: string;
	subtitle: string;
	icon: IoniconName;
	canRestore: boolean;
	canPurge: boolean;
	disabled: boolean;
	restorePending: boolean;
	purgePending: boolean;
	onRestore: () => void;
	onPurge: () => void;
}

// Строка корзины: слева тип/название, справа — восстановление и, где
// разрешено, безвозвратное удаление. Обе кнопки 44×44 с подписями для a11y.
export function TrashRow({
	testID,
	title,
	typeLabel,
	subtitle,
	icon,
	canRestore,
	canPurge,
	disabled,
	restorePending,
	purgePending,
	onRestore,
	onPurge,
}: TrashRowProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	return (
		<View
			testID={testID}
			style={[
				styles.row,
				{
					borderColor: colors.border,
					backgroundColor: colors.surface,
					borderRadius: radii.md,
					paddingLeft: spacing.sm,
				},
			]}
		>
			<View
				style={[styles.iconCircle, { backgroundColor: colors.surfaceMuted }]}
			>
				<Ionicons name={icon} size={18} color={colors.textMuted} />
			</View>
			<View style={styles.info}>
				<Text
					numberOfLines={2}
					style={[styles.rowTitle, { color: colors.text }]}
				>
					{title}
				</Text>
				<View style={[styles.metaRow, { gap: spacing.xs }]}>
					<View
						style={[styles.typeBadge, { backgroundColor: colors.surfaceMuted }]}
					>
						<Text style={[styles.typeLabel, { color: colors.textMuted }]}>
							{typeLabel}
						</Text>
					</View>
					{subtitle !== "" && (
						<Text
							numberOfLines={1}
							style={[styles.meta, { color: colors.textMuted }]}
						>
							{subtitle}
						</Text>
					)}
				</View>
			</View>
			<View style={styles.actions}>
				{canRestore && (
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={t("trash.restoreNamed", { title })}
						accessibilityState={{ disabled }}
						disabled={disabled}
						onPress={onRestore}
						testID={`${testID}-restore`}
						hitSlop={4}
						style={({ pressed }) => [styles.action, pressed && styles.pressed]}
					>
						{restorePending ? (
							<ActivityIndicator size="small" color={colors.accent} />
						) : (
							<Ionicons
								name="refresh-outline"
								size={21}
								color={colors.accent}
							/>
						)}
					</Pressable>
				)}
				{canPurge && (
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={t("trash.purgeNamed", { title })}
						accessibilityState={{ disabled }}
						disabled={disabled}
						onPress={onPurge}
						testID={`${testID}-purge`}
						hitSlop={4}
						style={({ pressed }) => [styles.action, pressed && styles.pressed]}
					>
						{purgePending ? (
							<ActivityIndicator size="small" color={colors.danger} />
						) : (
							<Ionicons name="trash-outline" size={20} color={colors.danger} />
						)}
					</Pressable>
				)}
			</View>
		</View>
	);
}

export function TrashSection({
	title,
	count,
	testID,
	children,
}: {
	title: string;
	count: number;
	testID: string;
	children: ReactNode;
}) {
	const { colors, spacing } = useTheme();
	return (
		<View style={{ gap: spacing.sm }} testID={testID}>
			<Text style={[styles.sectionTitle, { color: colors.text }]}>
				{title} · {count}
			</Text>
			<View style={{ gap: spacing.xs }}>{children}</View>
		</View>
	);
}

const styles = StyleSheet.create({
	header: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
	},
	headerButton: {
		width: 44,
		height: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	headerTitle: { flex: 1, fontSize: 20, fontWeight: "700" },
	emptyButton: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "center",
		minHeight: 44,
		borderWidth: 1,
	},
	emptyButtonLabel: { fontSize: 14, fontWeight: "600" },
	sectionTitle: { fontSize: 18, fontWeight: "700" },
	row: {
		flexDirection: "row",
		alignItems: "center",
		borderWidth: 1,
		minHeight: 64,
		paddingRight: 4,
	},
	iconCircle: {
		width: 32,
		height: 32,
		borderRadius: 16,
		alignItems: "center",
		justifyContent: "center",
	},
	info: { flex: 1, gap: 2, paddingVertical: 8 },
	rowTitle: { fontSize: 15, fontWeight: "600" },
	metaRow: { flexDirection: "row", alignItems: "center" },
	typeBadge: {
		paddingHorizontal: 6,
		paddingVertical: 1,
		borderRadius: 999,
	},
	typeLabel: { fontSize: 11, fontWeight: "600" },
	meta: { flexShrink: 1, fontSize: 12 },
	actions: { flexDirection: "row", alignItems: "center" },
	action: {
		width: 44,
		height: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	pressed: { opacity: 0.7 },
});
