import Ionicons from "@expo/vector-icons/Ionicons";
import type { Media } from "@flux/shared";
import type { ComponentProps } from "react";
import {
	ActivityIndicator,
	Alert,
	Pressable,
	StyleSheet,
	Text,
} from "react-native";
import {
	type DownloadIndicatorState,
	useDownloadActions,
	useDownloadIndicator,
	useDownloadState,
} from "../downloads/DownloadProvider";
import type { DownloadFailure } from "../downloads/downloadStore";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

type IoniconName = ComponentProps<typeof Ionicons>["name"];

interface DownloadButtonProps {
	media: Media;
	/** База testID: к ней добавляется состояние (idle/downloading/done/error). */
	testID?: string;
}

function downloadFailureLabel(failure: DownloadFailure | null): string {
	switch (failure) {
		case "status":
			return t("downloads.errorStatus");
		case "size":
			return t("downloads.errorSize");
		case "storage":
			return t("downloads.errorStorage");
		case "timeout":
			return t("downloads.errorTimeout");
		case "network":
			return t("downloads.errorNetwork");
		default:
			return t("downloads.errorUnknown");
	}
}

function buttonLabel(indicator: DownloadIndicatorState | null): string {
	if (indicator === null) {
		return t("downloads.download");
	}
	switch (indicator.status) {
		case "downloading":
			return indicator.progress === null
				? t("downloads.downloading")
				: t("downloads.downloadingPercent", {
						percent: Math.round(indicator.progress * 100),
					});
		case "error":
			return t("downloads.retry");
		default:
			return t("downloads.downloaded");
	}
}

function buttonIcon(indicator: DownloadIndicatorState | null): IoniconName {
	if (indicator === null) {
		return "download-outline";
	}
	switch (indicator.status) {
		case "downloading":
			return "arrow-down-circle-outline";
		case "error":
			return "alert-circle-outline";
		default:
			return "checkmark-circle";
	}
}

// Кнопка одна на все состояния: idle -> скачать, downloading -> отменить,
// error -> повторить, downloaded -> удалить с подтверждением. testID
// меняется вместе с состоянием, чтобы Maestro ждал именно завершение, а не
// просто исчезновение прогресса.
export function DownloadButton({
	media,
	testID = "download-button",
}: DownloadButtonProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const { hydrated } = useDownloadState();
	const indicator = useDownloadIndicator(media.id);
	const { start, cancel, retry, remove } = useDownloadActions();
	const status = indicator?.status ?? "idle";
	const label = buttonLabel(indicator);
	const downloading = indicator?.status === "downloading";

	const onPress = () => {
		if (indicator === null) {
			start(media);
			return;
		}
		switch (indicator.status) {
			case "downloading":
				cancel(media.id);
				return;
			case "error":
				Alert.alert(
					t("downloads.errorTitle"),
					downloadFailureLabel(indicator.failure ?? null),
					[
						{
							text: t("downloads.dismiss"),
							style: "cancel",
							onPress: () => cancel(media.id),
						},
						{
							text: t("downloads.retry"),
							onPress: () => retry(media),
						},
					],
				);
				return;
			default:
				Alert.alert(t("downloads.deleteTitle"), t("downloads.deleteConfirm"), [
					{ text: t("common.cancel"), style: "cancel" },
					{
						text: t("downloads.delete"),
						style: "destructive",
						onPress: () => remove(media.id),
					},
				]);
		}
	};

	const accent =
		indicator?.status === "downloaded"
			? colors.accent
			: indicator?.status === "error"
				? colors.danger
				: colors.text;

	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={label}
			accessibilityState={{
				disabled: !hydrated,
				selected: indicator?.status === "downloaded",
			}}
			disabled={!hydrated}
			onPress={onPress}
			testID={`${testID}-${status}`}
			hitSlop={4}
			style={({ pressed }) => [
				styles.button,
				{
					backgroundColor: colors.surface,
					borderColor:
						indicator?.status === "downloaded"
							? colors.accent
							: colors.borderStrong,
					borderRadius: radii.sm,
					gap: spacing.xs,
					paddingHorizontal: spacing.md,
					paddingVertical: spacing.sm,
				},
				(!hydrated || pressed) && styles.pressed,
			]}
		>
			{downloading ? (
				<ActivityIndicator size="small" color={colors.accent} />
			) : (
				<Ionicons name={buttonIcon(indicator)} size={18} color={accent} />
			)}
			<Text style={[styles.label, { color: accent }]}>{label}</Text>
		</Pressable>
	);
}

const styles = StyleSheet.create({
	button: {
		flexDirection: "row",
		alignSelf: "center",
		alignItems: "center",
		justifyContent: "center",
		minHeight: 44,
		borderWidth: 1,
	},
	label: { fontSize: 14, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});
