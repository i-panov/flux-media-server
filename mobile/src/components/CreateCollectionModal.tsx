import Ionicons from "@expo/vector-icons/Ionicons";
import type { Collection } from "@flux/shared";
import type { ComponentProps } from "react";
import { useState } from "react";
import {
	ActivityIndicator,
	KeyboardAvoidingView,
	Modal,
	Platform,
	Pressable,
	StyleSheet,
	Text,
	TextInput,
	View,
} from "react-native";
import {
	type AddableCollectionType,
	useCreateCollection,
} from "../api/collections";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

type IoniconName = ComponentProps<typeof Ionicons>["name"];

// image-коллекции пока не создаём: в mobile нет экрана изображений и
// точки добавления image-медиа, поэтому такую коллекцию нечем наполнить.
// Существующие image-коллекции с сервера открываются и удаляются.
const TYPE_OPTIONS = [
	{
		value: "video",
		icon: "videocam-outline",
		label: "collections.typeVideo",
	},
	{
		value: "audio",
		icon: "musical-notes-outline",
		label: "collections.typeAudio",
	},
] as const satisfies readonly {
	value: AddableCollectionType;
	icon: IoniconName;
	label: Parameters<typeof t>[0];
}[];

interface CreateCollectionModalProps {
	visible: boolean;
	onClose: () => void;
	defaultType?: AddableCollectionType;
	/** Для подколлекции тип фиксирован родителем, селектор скрыт. */
	fixedType?: AddableCollectionType;
	parentId?: number;
	onCreated?: (collection: Collection) => void;
}

function CollectionTypePicker({
	value,
	disabled,
	onChange,
}: {
	value: AddableCollectionType;
	disabled: boolean;
	onChange: (value: AddableCollectionType) => void;
}) {
	const { colors, radii, spacing } = useTheme();
	return (
		<View style={{ gap: spacing.xs }}>
			<Text style={[styles.label, { color: colors.textMuted }]}>
				{t("collections.type")}
			</Text>
			<View style={[styles.types, { gap: spacing.xs }]}>
				{TYPE_OPTIONS.map((option) => {
					const selected = value === option.value;
					return (
						<Pressable
							key={option.value}
							accessibilityRole="button"
							accessibilityLabel={t(option.label)}
							accessibilityState={{ selected, disabled }}
							disabled={disabled}
							onPress={() => onChange(option.value)}
							testID={`collection-create-type-${option.value}`}
							style={({ pressed }) => [
								styles.type,
								{
									borderColor: selected ? colors.accent : colors.borderStrong,
									borderRadius: radii.sm,
									backgroundColor: selected ? colors.accent : colors.background,
								},
								(pressed || disabled) && styles.pressed,
							]}
						>
							<Ionicons
								name={option.icon}
								size={16}
								color={selected ? colors.onAccent : colors.text}
							/>
							<Text
								style={[
									styles.typeLabel,
									{ color: selected ? colors.onAccent : colors.text },
								]}
							>
								{t(option.label)}
							</Text>
						</Pressable>
					);
				})}
			</View>
		</View>
	);
}

export function CreateCollectionModal({
	visible,
	onClose,
	defaultType = "video",
	fixedType,
	parentId,
	onCreated,
}: CreateCollectionModalProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const [name, setName] = useState("");
	const [type, setType] = useState<AddableCollectionType>(defaultType);
	const create = useCreateCollection();
	const chosenType = fixedType ?? type;
	const trimmed = name.trim();
	const canSave = trimmed !== "" && !create.isPending;

	const submit = () => {
		if (!canSave) {
			return;
		}
		create.mutate(
			{ name: trimmed, type: chosenType, parentId: parentId ?? null },
			{
				onSuccess: (collection) => {
					onClose();
					onCreated?.(collection);
				},
			},
		);
	};

	const title =
		parentId === undefined
			? t("collections.createTitle")
			: t("collections.createSubcollectionTitle");

	return (
		<Modal
			visible={visible}
			transparent
			animationType="fade"
			onRequestClose={onClose}
		>
			<KeyboardAvoidingView
				behavior={Platform.OS === "ios" ? "padding" : "height"}
				style={styles.overlay}
			>
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("common.close")}
					onPress={onClose}
					testID="collection-create-backdrop"
					style={[StyleSheet.absoluteFill, { backgroundColor: colors.overlay }]}
				/>
				<View
					testID="collection-create-modal"
					style={[
						styles.card,
						{
							backgroundColor: colors.surface,
							borderColor: colors.border,
							borderRadius: radii.lg,
							gap: spacing.md,
							padding: spacing.lg,
						},
					]}
				>
					<Text style={[styles.title, { color: colors.text }]}>{title}</Text>
					<TextInput
						testID="collection-create-name"
						accessibilityLabel={t("collections.name")}
						autoFocus
						value={name}
						onChangeText={(next) => {
							setName(next);
							if (create.isError) {
								create.reset();
							}
						}}
						onSubmitEditing={submit}
						returnKeyType="done"
						maxLength={200}
						placeholder={t("collections.namePlaceholder")}
						placeholderTextColor={colors.textMuted}
						style={[
							styles.input,
							{
								borderColor: colors.controlBorder,
								borderRadius: radii.sm,
								color: colors.text,
								backgroundColor: colors.background,
								paddingHorizontal: spacing.md,
							},
						]}
					/>
					<CollectionTypePicker
						value={chosenType}
						disabled={fixedType !== undefined}
						onChange={setType}
					/>
					{create.isError && (
						<Text
							testID="collection-create-error"
							accessibilityRole="alert"
							style={[styles.error, { color: colors.danger }]}
						>
							{t("collections.createError")}
						</Text>
					)}
					<View style={[styles.actions, { gap: spacing.sm }]}>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("common.cancel")}
							onPress={onClose}
							testID="collection-create-cancel"
							style={({ pressed }) => [
								styles.button,
								{
									borderColor: colors.borderStrong,
									borderRadius: radii.sm,
									paddingHorizontal: spacing.md,
								},
								pressed && styles.pressed,
							]}
						>
							<Text style={[styles.buttonLabel, { color: colors.text }]}>
								{t("common.cancel")}
							</Text>
						</Pressable>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("common.create")}
							accessibilityState={{ disabled: !canSave }}
							disabled={!canSave}
							onPress={submit}
							testID="collection-create-submit"
							style={({ pressed }) => [
								styles.button,
								{
									backgroundColor: canSave
										? colors.accent
										: colors.surfaceMuted,
									borderColor: canSave ? colors.accent : colors.border,
									borderRadius: radii.sm,
									paddingHorizontal: spacing.md,
								},
								pressed && styles.pressed,
							]}
						>
							{create.isPending ? (
								<ActivityIndicator size="small" color={colors.textMuted} />
							) : (
								<Text
									style={[
										styles.buttonLabel,
										{ color: canSave ? colors.onAccent : colors.textMuted },
									]}
								>
									{t("common.create")}
								</Text>
							)}
						</Pressable>
					</View>
				</View>
			</KeyboardAvoidingView>
		</Modal>
	);
}

const styles = StyleSheet.create({
	overlay: {
		flex: 1,
		alignItems: "center",
		justifyContent: "center",
		padding: 24,
	},
	card: { width: "100%", maxWidth: 420, borderWidth: 1 },
	title: { fontSize: 18, fontWeight: "700" },
	label: { fontSize: 13, fontWeight: "600" },
	input: { minHeight: 44, borderWidth: 1, fontSize: 16 },
	types: { flexDirection: "row", flexWrap: "wrap" },
	type: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "center",
		gap: 6,
		minHeight: 44,
		paddingHorizontal: 12,
		borderWidth: 1,
	},
	typeLabel: { fontSize: 14, fontWeight: "600" },
	error: { fontSize: 13, lineHeight: 18 },
	actions: { flexDirection: "row", justifyContent: "flex-end" },
	button: {
		minHeight: 44,
		minWidth: 88,
		alignItems: "center",
		justifyContent: "center",
		borderWidth: 1,
	},
	buttonLabel: { fontSize: 15, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});
