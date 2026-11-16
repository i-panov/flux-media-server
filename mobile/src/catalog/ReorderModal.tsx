import { useEffect, useState } from "react";
import { Modal, Pressable, Text, View } from "react-native";
import DraggableFlatList, {
	type RenderItemParams,
	ScaleDecorator,
} from "react-native-draggable-flatlist";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { t } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

export interface ReorderRow {
	id: number;
	label: string;
}

export function ReorderModal({
	visible,
	title,
	rows,
	onClose,
	onSave,
}: {
	visible: boolean;
	title: string;
	rows: ReorderRow[];
	onClose: () => void;
	onSave: (ids: number[]) => void;
}) {
	const { colors, spacing } = useTheme();
	const [items, setItems] = useState(rows);
	useEffect(() => {
		if (visible) {
			// eslint-disable-next-line react-hooks/set-state-in-effect -- синхронизация с новым списком при открытии.
			setItems(rows);
		}
	}, [rows, visible]);

	const renderItem = ({
		item,
		drag,
		isActive,
	}: RenderItemParams<ReorderRow>) => (
		<ScaleDecorator>
			<Pressable
				onLongPress={drag}
				disabled={isActive}
				style={{
					padding: spacing.md,
					marginBottom: spacing.xs,
					borderRadius: 8,
					backgroundColor: isActive ? colors.surfaceMuted : colors.surface,
					borderWidth: 1,
					borderColor: colors.border,
				}}
			>
				<Text style={{ color: colors.text }}>{item.label}</Text>
			</Pressable>
		</ScaleDecorator>
	);

	return (
		<Modal visible={visible} animationType="slide" onRequestClose={onClose}>
			<GestureHandlerRootView style={{ flex: 1 }}>
				<View
					style={{
						flex: 1,
						backgroundColor: colors.background,
						padding: spacing.lg,
						gap: spacing.md,
					}}
				>
					<Text style={{ color: colors.text, fontSize: 20, fontWeight: "700" }}>
						{title}
					</Text>
					<Text style={{ color: colors.textMuted }}>
						{t("catalog.dragHint")}
					</Text>
					<DraggableFlatList
						data={items}
						keyExtractor={(item) => String(item.id)}
						renderItem={renderItem}
						onDragEnd={({ data }) => setItems(data)}
						containerStyle={{ flex: 1 }}
					/>
					<View
						style={{
							flexDirection: "row",
							justifyContent: "flex-end",
							gap: spacing.md,
						}}
					>
						<Pressable onPress={onClose}>
							<Text style={{ color: colors.textMuted }}>
								{t("common.cancel")}
							</Text>
						</Pressable>
						<Pressable
							onPress={() => {
								onSave(items.map((item) => item.id));
								onClose();
							}}
						>
							<Text style={{ color: colors.accent, fontWeight: "700" }}>
								{t("common.save")}
							</Text>
						</Pressable>
					</View>
				</View>
			</GestureHandlerRootView>
		</Modal>
	);
}
