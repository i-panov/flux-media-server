import Ionicons from "@expo/vector-icons/Ionicons";
import { router } from "expo-router";
import { Pressable, StyleSheet, Text } from "react-native";
import { useSession } from "../auth/session";
import { t } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { isTV } from "../tv/profile";

export type UploadMediaType = "video" | "audio" | "image";

// Загрузка вызывается из конкретного раздела, как во Flutter: тип
// фиксирован, пользователь не выбирает его в общем экране.
export function UploadAction({ type }: { type: UploadMediaType }) {
	const session = useSession();
	const { colors, radii, spacing } = useTheme();
	if (isTV || session.data?.is_admin !== true) {
		return null;
	}
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={t("upload.title")}
			onPress={() => router.push(`/upload?type=${type}`)}
			testID={`upload-${type}`}
			style={({ pressed }) => [
				styles.button,
				{
					backgroundColor: colors.surfaceMuted,
					borderRadius: radii.pill,
					paddingHorizontal: spacing.sm,
					gap: spacing.xs,
				},
				pressed && styles.pressed,
			]}
		>
			<Ionicons name="cloud-upload-outline" size={17} color={colors.text} />
			<Text style={[styles.label, { color: colors.text }]}>
				{t("upload.short")}
			</Text>
		</Pressable>
	);
}

const styles = StyleSheet.create({
	button: {
		flexDirection: "row",
		alignItems: "center",
		minHeight: 36,
	},
	label: { fontSize: 12, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});
