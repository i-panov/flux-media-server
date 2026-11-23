import { Alert, StyleSheet, Switch, Text, View } from "react-native";
import { useSetAutoCleanup, useStorage } from "../../api/admin";
import { formatFileSize } from "../../api/upload";
import { t, useLanguage } from "../../i18n";
import { useTheme } from "../../theme/ThemeProvider";

// Хранилище: свободное место по разделам и автоочистка оригиналов.
export function StoragePanel() {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const storage = useStorage();
	const cleanup = useSetAutoCleanup();
	if (storage.isPending) {
		return (
			<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
		);
	}
	if (storage.isError || storage.data === undefined) {
		return <Text style={{ color: colors.danger }}>{t("common.error")}</Text>;
	}
	const data = storage.data;
	return (
		<View style={{ gap: spacing.sm }}>
			<View style={[styles.row, { gap: spacing.sm }]}>
				<Text style={{ color: colors.text, flex: 1 }}>
					{t("admin.storage.autoCleanup")}
				</Text>
				<Switch
					value={data.auto_cleanup}
					testID="admin-auto-cleanup"
					disabled={cleanup.isPending}
					onValueChange={(value) =>
						cleanup.mutate(value, {
							onError: () =>
								Alert.alert(t("admin.storage.title"), t("common.error")),
						})
					}
				/>
			</View>
			{data.disks.map((disk) => {
				const freePercent =
					disk.total_bytes > 0
						? Math.round((disk.free_bytes / disk.total_bytes) * 100)
						: 0;
				return (
					<View
						key={disk.path}
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
						<Text style={{ color: colors.text }} numberOfLines={2}>
							{disk.path}
						</Text>
						<View
							style={[styles.bar, { backgroundColor: colors.surfaceMuted }]}
						>
							<View
								style={{
									width: `${100 - freePercent}%`,
									height: 6,
									backgroundColor: colors.accent,
								}}
							/>
						</View>
						<Text style={{ color: colors.textMuted }}>
							{t("admin.storage.free", {
								free: formatFileSize(disk.free_bytes),
								percent: freePercent,
							})}
						</Text>
						<Text style={{ color: colors.textMuted }}>
							{t("admin.storage.total", {
								total: formatFileSize(disk.total_bytes),
							})}
						</Text>
					</View>
				);
			})}
			<Text style={{ color: colors.textMuted }}>
				{t("admin.storage.breakdown", {
					video: formatFileSize(data.video_bytes),
					audio: formatFileSize(data.audio_bytes),
					originals: formatFileSize(data.originals_bytes),
					temp: formatFileSize(data.temp_bytes),
				})}
			</Text>
		</View>
	);
}

const styles = StyleSheet.create({
	row: { flexDirection: "row", alignItems: "center" },
	card: { borderWidth: 1 },
	bar: { height: 6, borderRadius: 3, overflow: "hidden" },
});
