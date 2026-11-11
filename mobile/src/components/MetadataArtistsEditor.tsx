import Ionicons from "@expo/vector-icons/Ionicons";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { t } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { MetadataField } from "./MetadataEditFields";

interface MetadataArtistsEditorProps {
	artists: readonly string[];
	editable: boolean;
	onChange: (index: number, value: string) => void;
	onAdd: () => void;
	onRemove: (index: number) => void;
}

// Один TextInput на артиста: запятая — часть имени, а не разделитель
// ("Tyler, The Creator"). Кнопки добавления/удаления — 44dp.
export function MetadataArtistsEditor({
	artists,
	editable,
	onChange,
	onAdd,
	onRemove,
}: MetadataArtistsEditorProps) {
	const { colors, radii, spacing } = useTheme();
	return (
		<View style={{ gap: spacing.sm }} testID="metadata-artists">
			<Text style={[styles.label, { color: colors.text }]}>
				{t("metadata.artists")}
			</Text>
			<Text style={[styles.hint, { color: colors.textMuted }]}>
				{t("metadata.artistsHint")}
			</Text>
			{artists.map((artist, index) => (
				// biome-ignore lint/suspicious/noArrayIndexKey: у строки артиста нет id, порядок задаёт сам пользователь.
				<View key={index} style={[styles.row, { gap: spacing.sm }]}>
					<View style={styles.field}>
						<MetadataField
							label={t("metadata.artistLabel", { index: index + 1 })}
							value={artist}
							onChangeText={(value) => onChange(index, value)}
							testID={`metadata-field-artist-${index}`}
							editable={editable}
						/>
					</View>
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={t("metadata.removeArtist")}
						accessibilityState={{ disabled: !editable }}
						disabled={!editable}
						onPress={() => onRemove(index)}
						testID={`metadata-artist-remove-${index}`}
						hitSlop={4}
						style={({ pressed }) => [
							styles.remove,
							{
								borderColor: colors.borderStrong,
								borderRadius: radii.sm,
								backgroundColor: colors.surface,
							},
							(pressed || !editable) && styles.pressed,
						]}
					>
						<Ionicons name="trash-outline" size={18} color={colors.danger} />
					</Pressable>
				</View>
			))}
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("metadata.addArtist")}
				accessibilityState={{ disabled: !editable }}
				disabled={!editable}
				onPress={onAdd}
				testID="metadata-artist-add"
				style={({ pressed }) => [
					styles.add,
					{
						borderColor: colors.accent,
						borderRadius: radii.sm,
						paddingHorizontal: spacing.md,
						gap: spacing.sm,
					},
					(pressed || !editable) && styles.pressed,
				]}
			>
				<Ionicons name="add" size={18} color={colors.accent} />
				<Text style={[styles.addLabel, { color: colors.accent }]}>
					{t("metadata.addArtist")}
				</Text>
			</Pressable>
		</View>
	);
}

const styles = StyleSheet.create({
	label: { fontSize: 14, fontWeight: "600" },
	hint: { fontSize: 12, lineHeight: 16 },
	row: { flexDirection: "row", alignItems: "flex-end" },
	field: { flex: 1 },
	remove: {
		width: 44,
		height: 44,
		borderWidth: 1,
		alignItems: "center",
		justifyContent: "center",
	},
	add: {
		minHeight: 44,
		borderWidth: 1,
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "center",
	},
	addLabel: { fontSize: 14, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});
