import { Alert, Pressable, StyleSheet, Text, View } from "react-native";
import { useRetryTranscode, useTranscodes } from "../../api/admin";
import { t, useLanguage } from "../../i18n";
import { useTheme } from "../../theme/ThemeProvider";

export function TranscodesPanel() {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const rows = useTranscodes();
	const retry = useRetryTranscode();
	const errorLabel = t("common.error");
	if (rows.isPending) {
		return (
			<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
		);
	}
	if (rows.isError) {
		return <Text style={{ color: colors.danger }}>{errorLabel}</Text>;
	}
	if ((rows.data ?? []).length === 0) {
		return (
			<Text style={{ color: colors.textMuted }}>{t("admin.queue.empty")}</Text>
		);
	}
	return (
		<View style={{ gap: spacing.sm }}>
			{(rows.data ?? []).map((row) => (
				<View
					key={row.id}
					style={[
						styles.card,
						{
							borderColor: colors.border,
							borderRadius: radii.md,
							padding: spacing.sm,
							gap: 4,
						},
					]}
				>
					<Text style={{ color: colors.text }} numberOfLines={1}>
						{row.filename}
					</Text>
					<Text style={{ color: colors.textMuted }}>
						{row.status} · {row.progress}%
					</Text>
					{row.status === "error" && (
						<View style={[styles.row, { gap: spacing.sm }]}>
							<Text style={{ color: colors.danger, flex: 1 }} numberOfLines={2}>
								{row.error ?? errorLabel}
							</Text>
							<Pressable
								testID={`admin-transcode-retry-${row.id}`}
								onPress={() =>
									retry.mutate(row.id, {
										onError: () =>
											Alert.alert(t("admin.queue.title"), errorLabel),
									})
								}
							>
								<Text style={{ color: colors.accent }}>
									{t("common.retry")}
								</Text>
							</Pressable>
						</View>
					)}
				</View>
			))}
		</View>
	);
}

const styles = StyleSheet.create({
	row: { flexDirection: "row", alignItems: "center" },
	card: { borderWidth: 1 },
});
