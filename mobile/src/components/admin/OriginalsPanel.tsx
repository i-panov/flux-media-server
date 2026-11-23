import { Alert, Pressable, StyleSheet, Text, View } from "react-native";
import { useDeleteOriginal, useOriginals } from "../../api/admin";
import { formatFileSize } from "../../api/upload";
import { t, useLanguage } from "../../i18n";
import { useTheme } from "../../theme/ThemeProvider";

// Карантин оригиналов: список и удаление. Скачивание на мобильном не
// делаем — файл и так лежит на сервере.
function statusLabel(status: string): string {
	switch (status) {
		case "untracked":
			return t("admin.originals.statusUntracked");
		case "orphaned":
			return t("admin.originals.statusOrphaned");
		case "queued":
			return t("admin.queue.statusQueued");
		case "processing":
			return t("admin.queue.statusProcessing");
		case "done":
			return t("admin.queue.statusDone");
		case "error":
			return t("admin.queue.statusError");
		case "cancelled":
			return t("admin.queue.statusCancelled");
		default:
			return status;
	}
}

export function OriginalsPanel() {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const originals = useOriginals();
	const remove = useDeleteOriginal();
	const deleteLabel = t("admin.originals.delete");
	if (originals.isPending) {
		return (
			<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
		);
	}
	if (originals.isError) {
		return <Text style={{ color: colors.danger }}>{t("common.error")}</Text>;
	}
	if ((originals.data ?? []).length === 0) {
		return (
			<Text style={{ color: colors.textMuted }}>
				{t("admin.originals.empty")}
			</Text>
		);
	}
	return (
		<View style={{ gap: spacing.sm }}>
			{(originals.data ?? []).map((row) => (
				<View
					key={row.name}
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
						{row.name}
					</Text>
					<Text style={{ color: colors.textMuted }}>
						{formatFileSize(row.size_bytes)} · {statusLabel(row.status)} ·{" "}
						{t("admin.originals.views", { count: row.views })}
					</Text>
					<Pressable
						testID={`admin-original-delete-${row.name}`}
						onPress={() =>
							Alert.alert(deleteLabel, row.name, [
								{ text: t("common.cancel"), style: "cancel" },
								{
									text: deleteLabel,
									style: "destructive",
									onPress: () =>
										remove.mutate(row.name, {
											onError: () =>
												Alert.alert(
													t("admin.originals.title"),
													t("common.error"),
												),
										}),
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
}

const styles = StyleSheet.create({
	card: { borderWidth: 1 },
});
