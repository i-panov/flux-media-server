import Ionicons from "@expo/vector-icons/Ionicons";
import type { ComponentProps } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

type IoniconName = ComponentProps<typeof Ionicons>["name"];

interface Action {
	label: string;
	icon: IoniconName;
	testID: string;
	onPress: () => void;
	danger?: boolean;
}

interface CollectionActionBarProps {
	canAddSubcollection: boolean;
	onAddSubcollection: () => void;
	onRename: () => void;
	onMove: () => void;
	onDelete: () => void;
}

// Действия над текущей коллекцией. Обычные кнопки с подписями, а не
// скрытое меню: на мобильном четыре иконки без текста читаются хуже.
export function CollectionActionBar({
	canAddSubcollection,
	onAddSubcollection,
	onRename,
	onMove,
	onDelete,
}: CollectionActionBarProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const actions: Action[] = [];
	if (canAddSubcollection) {
		actions.push({
			label: t("collections.addSubcollection"),
			icon: "add-circle-outline",
			testID: "collection-action-add",
			onPress: onAddSubcollection,
		});
	}
	actions.push(
		{
			label: t("collections.rename"),
			icon: "pencil-outline",
			testID: "collection-action-rename",
			onPress: onRename,
		},
		{
			label: t("collections.moveCollection"),
			icon: "arrow-redo-outline",
			testID: "collection-action-move",
			onPress: onMove,
		},
		{
			label: t("collections.delete"),
			icon: "trash-outline",
			testID: "collection-action-delete",
			onPress: onDelete,
			danger: true,
		},
	);

	return (
		<View style={[styles.bar, { gap: spacing.xs }]}>
			{actions.map((action) => (
				<Pressable
					key={action.testID}
					accessibilityRole="button"
					accessibilityLabel={action.label}
					onPress={action.onPress}
					testID={action.testID}
					style={({ pressed }) => [
						styles.action,
						{
							borderColor: action.danger ? colors.danger : colors.borderStrong,
							borderRadius: radii.sm,
							backgroundColor: colors.surface,
							gap: spacing.xs,
							paddingHorizontal: spacing.sm,
						},
						pressed && styles.pressed,
					]}
				>
					<Ionicons
						name={action.icon}
						size={16}
						color={action.danger ? colors.danger : colors.text}
					/>
					<Text
						numberOfLines={1}
						style={[
							styles.label,
							{ color: action.danger ? colors.danger : colors.text },
						]}
					>
						{action.label}
					</Text>
				</Pressable>
			))}
		</View>
	);
}

const styles = StyleSheet.create({
	bar: { flexDirection: "row", flexWrap: "wrap" },
	action: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "center",
		minHeight: 44,
		borderWidth: 1,
	},
	label: { fontSize: 13, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});
