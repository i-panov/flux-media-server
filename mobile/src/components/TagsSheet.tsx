import Ionicons from "@expo/vector-icons/Ionicons";
import { useState } from "react";
import {
	ActivityIndicator,
	KeyboardAvoidingView,
	Modal,
	Platform,
	Pressable,
	ScrollView,
	StyleSheet,
	Text,
	TextInput,
	View,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useMediaCatalogContext } from "../api/catalog";
import {
	type Tag,
	type TagEntity,
	useCreateTag,
	useEntityTags,
	useSetEntityTags,
	useTags,
} from "../api/tags";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface TagsSheetProps {
	entity: TagEntity;
	id: number;
	title: string;
	onClose: () => void;
}

function TagChip({
	tag,
	active,
	onPress,
}: {
	tag: Tag;
	active: boolean;
	onPress: () => void;
}) {
	const { colors, radii } = useTheme();
	return (
		<Pressable
			testID={`tag-${tag.id}`}
			accessibilityRole="button"
			accessibilityState={{ selected: active }}
			accessibilityLabel={tag.name}
			onPress={onPress}
			style={[
				styles.chip,
				{
					borderRadius: radii.md,
					borderColor: active ? colors.accent : colors.border,
					backgroundColor: active ? colors.surfaceMuted : colors.surface,
				},
			]}
		>
			<Text style={{ color: active ? colors.accent : colors.text }}>
				{tag.name}
			</Text>
		</Pressable>
	);
}

// Формат — ровно один (только у медиа), жанры — сколько угодно.
// Значения читаются один раз при открытии, дальше правятся локально.
function TagsForm({
	entity,
	id,
	tags,
	initial,
	onClose,
}: TagsSheetProps & { tags: Tag[]; initial: number[] }) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const save = useSetEntityTags(entity, id);
	const create = useCreateTag();
	const [selected, setSelected] = useState<number[]>(initial);
	const [name, setName] = useState("");
	const [group, setGroup] = useState<"genre" | "format">("genre");
	const [error, setError] = useState<string | null>(null);

	const formats = tags.filter((tag) => tag.group === "format");
	const genres = tags.filter((tag) => tag.group === "genre");

	const toggle = (tag: Tag) => {
		setSelected((prev) => {
			if (tag.group !== "format") {
				return prev.includes(tag.id)
					? prev.filter((value) => value !== tag.id)
					: [...prev, tag.id];
			}
			// Формат ровно один: выбор нового снимает прежний.
			const otherFormats = tags
				.filter((item) => item.group === "format" && item.id !== tag.id)
				.map((item) => item.id);
			const next = prev.filter((id) => !otherFormats.includes(id));
			return next.includes(tag.id)
				? next.filter((id) => id !== tag.id)
				: [...next, tag.id];
		});
	};

	return (
		<>
			<Text style={[styles.heading, { color: colors.text }]}>
				{t("tags.title")}
			</Text>
			<ScrollView contentContainerStyle={{ gap: spacing.md }}>
				{entity === "media" && formats.length > 0 && (
					<View style={{ gap: spacing.xs }}>
						<Text style={{ color: colors.textMuted }}>{t("tags.format")}</Text>
						<View style={[styles.wrap, { gap: spacing.xs }]}>
							{formats.map((tag) => (
								<TagChip
									key={tag.id}
									tag={tag}
									active={selected.includes(tag.id)}
									onPress={() => toggle(tag)}
								/>
							))}
						</View>
					</View>
				)}
				<View style={{ gap: spacing.xs }}>
					<Text style={{ color: colors.textMuted }}>{t("tags.genre")}</Text>
					{genres.length === 0 ? (
						<Text style={{ color: colors.textMuted }}>{t("tags.empty")}</Text>
					) : (
						<View style={[styles.wrap, { gap: spacing.xs }]}>
							{genres.map((tag) => (
								<TagChip
									key={tag.id}
									tag={tag}
									active={selected.includes(tag.id)}
									onPress={() => toggle(tag)}
								/>
							))}
						</View>
					)}
				</View>
				<View style={{ gap: spacing.xs }}>
					<Text style={{ color: colors.textMuted }}>
						{t("tags.createInline")}
					</Text>
					<View style={[styles.row, { gap: spacing.xs }]}>
						<TextInput
							value={name}
							onChangeText={setName}
							placeholder={t("tags.name")}
							placeholderTextColor={colors.textMuted}
							testID="tag-name"
							style={[
								styles.input,
								{
									color: colors.text,
									borderColor: colors.border,
									borderRadius: radii.md,
								},
							]}
						/>
						{(["genre", "format"] as const).map((value) =>
							entity !== "media" && value === "format" ? null : (
								<Pressable
									key={value}
									onPress={() => setGroup(value)}
									style={[
										styles.groupButton,
										{
											borderRadius: radii.md,
											borderColor:
												group === value ? colors.accent : colors.border,
										},
									]}
								>
									<Text
										style={{
											color: group === value ? colors.accent : colors.text,
										}}
									>
										{value === "format" ? t("tags.format") : t("tags.genre")}
									</Text>
								</Pressable>
							),
						)}
					</View>
					<Pressable
						disabled={name.trim() === "" || create.isPending}
						testID="tag-create"
						onPress={() => {
							const value = name.trim();
							if (value === "") return;
							create.mutate(
								{
									group,
									name: value,
									slug: value.toLocaleLowerCase().replace(/\s+/g, "-"),
								},
								{
									onSuccess: (tag) => {
										setSelected((prev) => {
											if (tag.group !== "format") {
												return [...prev, tag.id];
											}
											const otherFormats = tags
												.filter(
													(item) =>
														item.group === "format" && item.id !== tag.id,
												)
												.map((item) => item.id);
											return [
												...prev.filter((id) => !otherFormats.includes(id)),
												tag.id,
											];
										});
										setName("");
										setError(null);
									},
									onError: () => setError(t("tags.saveError")),
								},
							);
						}}
						style={[
							styles.save,
							{
								borderRadius: radii.md,
								backgroundColor: colors.surfaceMuted,
								opacity: name.trim() === "" ? 0.5 : 1,
							},
						]}
					>
						<Text style={{ color: colors.accent }}>{t("tags.create")}</Text>
					</Pressable>
				</View>
				{error !== null && (
					<Text style={{ color: colors.danger }}>{error}</Text>
				)}
			</ScrollView>
			<Pressable
				testID="tags-save"
				disabled={save.isPending}
				onPress={() => {
					save.mutate(selected, {
						onSuccess: () => {
							setError(null);
							onClose();
						},
						onError: () => setError(t("tags.saveError")),
					});
				}}
				style={[
					styles.save,
					{
						borderRadius: radii.md,
						backgroundColor: colors.accent,
						opacity: save.isPending ? 0.6 : 1,
					},
				]}
			>
				{save.isPending ? (
					<ActivityIndicator color={colors.onAccent} />
				) : (
					<Text style={{ color: colors.onAccent, fontWeight: "600" }}>
						{t("common.save")}
					</Text>
				)}
			</Pressable>
		</>
	);
}

export function TagsSheet(props: TagsSheetProps) {
	const { colors, radii, spacing } = useTheme();
	const insets = useSafeAreaInsets();
	const current = useEntityTags(props.entity, props.id);
	const tags = useTags();
	const context = useMediaCatalogContext(
		props.entity === "media" ? props.id : 0,
		props.entity === "media",
	);
	const inherited = (context.data?.work_tags ?? []).filter(
		(tag) => tag.group === "genre",
	);
	const ready =
		current.data !== undefined &&
		current.data !== null &&
		tags.data !== undefined;
	return (
		<Modal
			visible
			transparent
			animationType="slide"
			onRequestClose={props.onClose}
		>
			<KeyboardAvoidingView
				style={styles.backdrop}
				behavior={Platform.OS === "ios" ? "padding" : undefined}
			>
				<Pressable style={styles.backdrop} onPress={props.onClose}>
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
							<Text style={{ color: colors.textMuted }} numberOfLines={1}>
								{props.title}
							</Text>
							<Pressable onPress={props.onClose} testID="tags-close">
								<Ionicons name="close" size={20} color={colors.textMuted} />
							</Pressable>
						</View>
						{inherited.length > 0 && (
							<View style={{ gap: 4 }}>
								<Text style={{ color: colors.textMuted }}>
									{t("catalog.inheritedTags")}
								</Text>
								<View style={[styles.wrap, { gap: spacing.xs }]}>
									{inherited.map((tag) => (
										<View
											key={tag.id}
											style={[
												styles.chip,
												{
													borderRadius: radii.md,
													borderColor: colors.border,
												},
											]}
										>
											<Text style={{ color: colors.textMuted }}>
												{tag.name}
											</Text>
										</View>
									))}
								</View>
							</View>
						)}
						{ready ? (
							<TagsForm
								{...props}
								tags={tags.data ?? []}
								initial={(current.data ?? []).map((tag) => tag.id)}
							/>
						) : (
							<ActivityIndicator color={colors.accent} />
						)}
					</Pressable>
				</Pressable>
			</KeyboardAvoidingView>
		</Modal>
	);
}

const styles = StyleSheet.create({
	backdrop: {
		flex: 1,
		backgroundColor: "rgba(0,0,0,0.4)",
		justifyContent: "flex-end",
	},
	sheet: { maxHeight: "85%" },
	heading: { fontSize: 18, fontWeight: "600" },
	wrap: { flexDirection: "row", flexWrap: "wrap" },
	chip: { borderWidth: 1, paddingHorizontal: 10, paddingVertical: 6 },
	row: { flexDirection: "row", alignItems: "center" },
	between: { justifyContent: "space-between" },
	input: { flex: 1, borderWidth: 1, paddingHorizontal: 10, paddingVertical: 8 },
	groupButton: { borderWidth: 1, paddingHorizontal: 10, paddingVertical: 8 },
	save: { alignItems: "center", paddingVertical: 12 },
});
