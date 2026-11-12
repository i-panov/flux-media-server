import Ionicons from "@expo/vector-icons/Ionicons";
import type { Media } from "@flux/shared";
import { router } from "expo-router";
import { useState } from "react";
import { Alert, Modal, Pressable, StyleSheet, Text, View } from "react-native";
import { useDeleteMedia } from "../api/media";
import { useSession } from "../auth/session";
import {
	useDownloadActions,
	useDownloadIndicator,
} from "../downloads/DownloadProvider";
import { saveMediaFile } from "../downloads/saveMediaFile";
import { t } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { AddToCollectionSheet } from "./AddToCollectionSheet";
import { ChangeCoverSheet } from "./ChangeCoverSheet";

export function MediaActionsSheet({
	media,
	onClose,
}: {
	media: Media | null;
	onClose: () => void;
}) {
	const { colors, radii, spacing } = useTheme();
	const session = useSession();
	const remove = useDeleteMedia();
	const download = useDownloadIndicator(media?.id ?? 0);
	const downloadActions = useDownloadActions();
	const [coverOpen, setCoverOpen] = useState(false);
	const [collectionOpen, setCollectionOpen] = useState(false);
	if (media === null) return null;
	const admin = session.data?.is_admin === true;

	const confirmDelete = () => {
		Alert.alert(t("media.deleteTitle"), t("media.deleteConfirm"), [
			{ text: t("common.cancel"), style: "cancel" },
			{
				text: t("media.delete"),
				style: "destructive",
				onPress: () => {
					remove.mutate(media.id, { onSuccess: onClose });
				},
			},
		]);
	};

	const row = (
		icon: keyof typeof Ionicons.glyphMap,
		label: string,
		onPress: () => void,
	) => (
		<Pressable
			accessibilityRole="button"
			onPress={onPress}
			style={({ pressed }) => [
				styles.row,
				{ gap: spacing.sm, paddingVertical: spacing.sm },
				pressed && styles.pressed,
			]}
		>
			<Ionicons name={icon} size={20} color={colors.text} />
			<Text style={{ color: colors.text, fontSize: 16 }}>{label}</Text>
		</Pressable>
	);

	return (
		<>
			<Modal visible transparent animationType="fade" onRequestClose={onClose}>
				<Pressable style={styles.backdrop} onPress={onClose}>
					<Pressable
						onPress={() => undefined}
						style={[
							styles.sheet,
							{
								backgroundColor: colors.surface,
								borderColor: colors.border,
								borderRadius: radii.md,
								padding: spacing.lg,
								gap: spacing.xs,
							},
						]}
					>
						<View style={[styles.handle, { backgroundColor: colors.border }]} />
						<Text style={[styles.title, { color: colors.text }]}>
							{media.title}
						</Text>
						{row(
							download?.status === "downloaded"
								? "checkmark-circle-outline"
								: "cloud-download-outline",
							download === null
								? t("downloads.download")
								: download.status === "downloading"
									? t("downloads.downloading")
									: download.status === "error"
										? t("downloads.retry")
										: t("downloads.downloaded"),
							() => {
								if (download === null) {
									downloadActions.start(media);
									onClose();
									return;
								}
								if (download.status === "downloading") {
									downloadActions.cancel(media.id);
									onClose();
									return;
								}
								if (download.status === "error") {
									downloadActions.retry(media);
									onClose();
									return;
								}
								downloadActions.remove(media.id);
								onClose();
							},
						)}
						{row("download-outline", t("media.saveFile"), () => {
							onClose();
							void saveMediaFile(media);
						})}
						{media.type !== "image" &&
							row("folder-open-outline", t("collections.addTitle"), () =>
								setCollectionOpen(true),
							)}
						{admin &&
							row("create-outline", t("metadata.edit"), () => {
								onClose();
								router.push(`/media/${media.id}/edit`);
							})}
						{admin &&
							media.type !== "image" &&
							row("image-outline", t("cover.change"), () => setCoverOpen(true))}
						{admin && row("trash-outline", t("media.delete"), confirmDelete)}
					</Pressable>
				</Pressable>
			</Modal>
			<ChangeCoverSheet
				visible={coverOpen}
				media={media}
				onClose={() => setCoverOpen(false)}
				onUploaded={() => setCoverOpen(false)}
			/>
			{media.type !== "image" && (
				<AddToCollectionSheet
					visible={collectionOpen}
					mediaId={media.id}
					type={media.type === "audio" ? "audio" : "video"}
					onClose={() => setCollectionOpen(false)}
				/>
			)}
		</>
	);
}

const styles = StyleSheet.create({
	backdrop: {
		flex: 1,
		justifyContent: "flex-end",
		backgroundColor: "rgba(0,0,0,0.45)",
	},
	sheet: { borderTopWidth: 1 },
	handle: { alignSelf: "center", width: 36, height: 4, borderRadius: 2 },
	title: { fontSize: 18, fontWeight: "700", marginBottom: 4 },
	row: { flexDirection: "row", alignItems: "center", minHeight: 44 },
	pressed: { opacity: 0.7 },
});
