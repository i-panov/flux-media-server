import { useState } from "react";
import {
	ActivityIndicator,
	Alert,
	Pressable,
	StyleSheet,
	Text,
	TextInput,
	View,
} from "react-native";
import {
	type TagGroup,
	useCreateTag,
	useDeleteTag,
	useTags,
} from "../../api/tags";
import { t, useLanguage } from "../../i18n";
import { useTheme } from "../../theme/ThemeProvider";

// Теги каталога: список по типам, создание и удаление. Формат и жанр —
// единственные типы; отдельного управления группами нет.
export function TagsPanel() {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const tags = useTags();
	const create = useCreateTag();
	const remove = useDeleteTag();
	const [name, setName] = useState("");
	const [group, setGroup] = useState<TagGroup>("genre");
	const deleteLabel = t("admin.delete");
	const formatLabel = t("tags.format");
	const genreLabel = t("tags.genre");

	const submit = () => {
		const value = name.trim();
		if (value === "") return;
		create.mutate(
			{
				group,
				name: value,
				slug: value.toLocaleLowerCase().replace(/\s+/g, "-"),
			},
			{ onSuccess: () => setName("") },
		);
	};

	if (tags.isPending) {
		return <ActivityIndicator color={colors.accent} />;
	}
	return (
		<View style={{ gap: spacing.sm }}>
			<View style={[styles.row, { gap: spacing.sm }]}>
				<TextInput
					value={name}
					onChangeText={setName}
					placeholder={t("tags.name")}
					placeholderTextColor={colors.textMuted}
					testID="admin-tag-name"
					style={[
						styles.input,
						{
							color: colors.text,
							borderColor: colors.border,
							borderRadius: radii.md,
						},
					]}
				/>
				{(["genre", "format"] as const).map((value) => (
					<Pressable
						key={value}
						testID={`admin-tag-group-${value}`}
						onPress={() => setGroup(value)}
						style={[
							styles.group,
							{
								borderRadius: radii.md,
								borderColor: group === value ? colors.accent : colors.border,
							},
						]}
					>
						<Text
							style={{ color: group === value ? colors.accent : colors.text }}
						>
							{value === "format" ? formatLabel : genreLabel}
						</Text>
					</Pressable>
				))}
			</View>
			<Pressable
				testID="admin-tag-create"
				disabled={name.trim() === "" || create.isPending}
				onPress={submit}
				style={[
					styles.button,
					{
						backgroundColor: colors.accent,
						borderRadius: radii.md,
						opacity: name.trim() === "" ? 0.5 : 1,
					},
				]}
			>
				<Text style={{ color: colors.onAccent, fontWeight: "600" }}>
					{t("tags.create")}
				</Text>
			</Pressable>
			{(["format", "genre"] as const).map((kind) => {
				const rows = (tags.data ?? []).filter((tag) => tag.group === kind);
				if (rows.length === 0) return null;
				return (
					<View key={kind} style={{ gap: spacing.xs }}>
						<Text style={{ color: colors.textMuted }}>
							{kind === "format" ? formatLabel : genreLabel}
						</Text>
						{rows.map((tag) => (
							<View
								key={tag.id}
								style={[styles.row, styles.between, { gap: spacing.sm }]}
							>
								<Text style={{ color: colors.text }}>
									{tag.name}{" "}
									<Text style={{ color: colors.textMuted, fontSize: 12 }}>
										{tag.slug}
									</Text>
								</Text>
								<Pressable
									accessibilityRole="button"
									accessibilityLabel={`${deleteLabel}: ${tag.name}`}
									testID={`admin-tag-delete-${tag.id}`}
									onPress={() =>
										Alert.alert(deleteLabel, tag.name, [
											{ text: t("common.cancel"), style: "cancel" },
											{
												text: deleteLabel,
												style: "destructive",
												onPress: () => remove.mutate(tag.id),
											},
										])
									}
								>
									<Text style={{ color: colors.danger }}>{deleteLabel}</Text>
								</Pressable>
							</View>
						))}
					</View>
				);
			})}
		</View>
	);
}

const styles = StyleSheet.create({
	row: { flexDirection: "row", alignItems: "center" },
	between: { justifyContent: "space-between" },
	input: { flex: 1, borderWidth: 1, paddingHorizontal: 10, paddingVertical: 8 },
	group: { borderWidth: 1, paddingHorizontal: 10, paddingVertical: 8 },
	button: { alignItems: "center", paddingVertical: 10 },
});
