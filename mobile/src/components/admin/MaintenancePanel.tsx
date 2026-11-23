import { Alert, Pressable, StyleSheet, Text, View } from "react-native";
import { useBackfill, useMaintenance } from "../../api/admin";
import { t, useLanguage } from "../../i18n";
import { useTheme } from "../../theme/ThemeProvider";

export function MaintenancePanel() {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const errorLabel = t("common.error");
	const info = useMaintenance();
	const thumbs = useBackfill("thumbnails");
	const covers = useBackfill("covers");
	if (info.isPending) {
		return (
			<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
		);
	}
	if (info.isError || info.data === undefined) {
		return <Text style={{ color: colors.danger }}>{errorLabel}</Text>;
	}
	const state = info.data.state;
	const busy = state.running;
	return (
		<View style={{ gap: spacing.sm }}>
			<Text style={{ color: colors.text }}>
				{t("admin.maintenance.thumbnails")}: {info.data.missing_thumbnails}
			</Text>
			<Text style={{ color: colors.text }}>
				{t("admin.maintenance.covers")}: {info.data.missing_covers}
			</Text>
			<View style={[styles.row, { gap: spacing.sm }]}>
				<Pressable
					testID="admin-backfill-thumbnails"
					disabled={busy || thumbs.isPending}
					onPress={() =>
						thumbs.mutate(undefined, {
							onError: () => Alert.alert(t("admin.maintenance"), errorLabel),
						})
					}
					style={[
						styles.button,
						{ backgroundColor: colors.accent, borderRadius: radii.md },
					]}
				>
					<Text style={{ color: colors.onAccent, fontWeight: "600" }}>
						{t("admin.maintenance.generate")}
					</Text>
				</Pressable>
				<Pressable
					testID="admin-backfill-covers"
					disabled={busy || covers.isPending}
					onPress={() =>
						covers.mutate(undefined, {
							onError: () => Alert.alert(t("admin.maintenance"), errorLabel),
						})
					}
					style={[
						styles.button,
						{
							backgroundColor: colors.surfaceMuted,
							borderRadius: radii.md,
						},
					]}
				>
					<Text style={{ color: colors.accent, fontWeight: "600" }}>
						{t("admin.maintenance.extract")}
					</Text>
				</Pressable>
			</View>
			{state.running && (
				<Text style={{ color: colors.textMuted }}>
					{t("admin.maintenance.running")}
				</Text>
			)}
			{!state.running && state.kind !== undefined && (
				<Text style={{ color: colors.textMuted }}>
					{t("admin.maintenance.lastRun", {
						generated: state.generated,
						failed: state.failed,
					})}
				</Text>
			)}
			{state.last_error !== undefined && state.last_error !== "" && (
				<Text style={{ color: colors.danger }}>{errorLabel}</Text>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
	row: { flexDirection: "row" },
	button: { flex: 1, alignItems: "center", paddingVertical: 10 },
});
