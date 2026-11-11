import Ionicons from "@expo/vector-icons/Ionicons";
import { useCallback } from "react";
import { Pressable, StyleSheet, Text, TextInput, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { nextSort, type SortOrder } from "../media/search";
import { useTheme } from "../theme/ThemeProvider";
import { tvFocusStyle } from "../tv/focus";

interface MediaSearchBarProps {
	value: string;
	onChangeText: (value: string) => void;
	/** Для списков без сортировки (мемы) переключатель не показывается. */
	sort?: SortOrder;
	onSortChange?: (sort: SortOrder) => void;
	placeholder: string;
	/** Базовый testID: input/clear/sort получают суффиксы. */
	testID: string;
}

// Общая панель поиска для вкладок видео и аудио: поле с debounce-задержкой
// живёт в экране, а здесь только ввод, очистка и переключатель сортировки.
export function MediaSearchBar({
	value,
	onChangeText,
	sort,
	onSortChange,
	placeholder,
	testID,
}: MediaSearchBarProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const sortLabel = sort === "asc" ? t("search.sortAsc") : t("search.sortDesc");
	const sortIcon = sort === "asc" ? "arrow-up" : "arrow-down";
	const showSort = sort !== undefined && onSortChange !== undefined;

	const onClear = useCallback(() => {
		onChangeText("");
	}, [onChangeText]);
	const onPressSort = useCallback(() => {
		if (sort !== undefined && onSortChange !== undefined) {
			onSortChange(nextSort(sort));
		}
	}, [onSortChange, sort]);

	return (
		<View style={[styles.row, { gap: spacing.sm }]}>
			<View
				style={[
					styles.inputWrap,
					{
						backgroundColor: colors.surface,
						borderColor: colors.controlBorder,
						borderRadius: radii.sm,
						paddingLeft: spacing.sm,
					},
				]}
			>
				<Ionicons name="search" size={18} color={colors.textMuted} />
				<TextInput
					accessibilityLabel={placeholder}
					value={value}
					onChangeText={onChangeText}
					placeholder={placeholder}
					placeholderTextColor={colors.textMuted}
					selectionColor={colors.accent}
					autoCapitalize="none"
					autoCorrect={false}
					returnKeyType="search"
					textAlignVertical="center"
					testID={`${testID}-input`}
					style={[styles.input, { color: colors.text }]}
				/>
				{value !== "" && (
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={t("search.clear")}
						onPress={onClear}
						hitSlop={4}
						testID={`${testID}-clear`}
						style={({ pressed }) => [
							styles.clearButton,
							pressed && styles.pressed,
						]}
					>
						<Ionicons name="close-circle" size={18} color={colors.textMuted} />
					</Pressable>
				)}
			</View>
			{showSort && (
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={sortLabel}
					accessibilityHint={t("search.sortHint")}
					accessibilityState={{ selected: sort === "asc" }}
					onPress={onPressSort}
					hitSlop={8}
					testID={`${testID}-sort`}
					style={({ pressed, focused }) => [
						styles.sortButton,
						{
							backgroundColor: colors.surfaceMuted,
							borderColor: colors.controlBorder,
							borderRadius: radii.sm,
							paddingHorizontal: spacing.sm,
						},
						pressed && styles.pressed,
						tvFocusStyle(focused, colors.accent),
					]}
				>
					<Ionicons name={sortIcon} size={16} color={colors.text} />
					<Text style={[styles.sortLabel, { color: colors.text }]}>
						{sortLabel}
					</Text>
				</Pressable>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
	row: { flexDirection: "row", alignItems: "center" },
	inputWrap: {
		flex: 1,
		minHeight: 44,
		flexDirection: "row",
		alignItems: "center",
		borderWidth: 1,
		gap: 6,
	},
	input: {
		flex: 1,
		minHeight: 44,
		paddingVertical: 0,
		paddingHorizontal: 0,
		fontSize: 16,
	},
	clearButton: {
		width: 44,
		height: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	sortButton: {
		minHeight: 44,
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "center",
		borderWidth: 1,
		gap: 4,
	},
	sortLabel: { fontSize: 13, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});
