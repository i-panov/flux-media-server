import Ionicons from "@expo/vector-icons/Ionicons";
import type { Media } from "@flux/shared";
import { router } from "expo-router";
import type { ComponentProps } from "react";
import { useState } from "react";
import { Alert, Modal, Pressable, StyleSheet, Text, View } from "react-native";
import { useDeleteMedia } from "../api/media";
import { useSession } from "../auth/session";
import { LEGACY_COLLECTIONS_ENABLED } from "../collections/legacy";
import {
	useDownloadActions,
	useDownloadIndicator,
} from "../downloads/DownloadProvider";
import { saveMediaFile } from "../downloads/saveMediaFile";
import { t } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { tvCapabilities } from "../tv/profile";
import { AddToCollectionSheet } from "./AddToCollectionSheet";
import { ChangeCoverSheet } from "./ChangeCoverSheet";
import { ClipSheet } from "./ClipSheet";
import { TagsSheet } from "./TagsSheet";

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
	const [tagsOpen, setTagsOpen] = useState(false);
	const [clipOpen, setClipOpen] = useState(false);
	if (media === null) return null;
	const admin = session.data?.is_admin === true;

	const confirmDelete = () => {
		Alert.alert(t("media.deleteTitle"), t("media.deleteConfirm"), [
			{ text: t("common.cancel"), style: "cancel" },
			{
				text: t("media.delete"),
				style: "destructive",
				onPress: () => {
					remove.mutate(media.id, {
						onSuccess: onClose,
						onError: () =>
							Alert.alert(t("common.error"), t("media.deleteError")),
					});
				},
			},
		]);
	};

	const row = (
		icon: ComponentProps<typeof Ionicons>["name"],
		label: string,
		onPress: () => void,
	) => <ActionRow icon={icon} label={label} onPress={onPress} />;

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
						{tvCapabilities.canDownload &&
							row(
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
						{tvCapabilities.canDownload &&
							row("download-outline", t("media.saveFile"), () => {
								onClose();
								void saveMediaFile(media);
							})}
						{LEGACY_COLLECTIONS_ENABLED &&
							media.type !== "image" &&
							row("folder-open-outline", t("collections.addTitle"), () =>
								setCollectionOpen(true),
							)}
						{tvCapabilities.canEditMetadata &&
							admin &&
							row("create-outline", t("metadata.edit"), () => {
								onClose();
								router.push(`/media/${media.id}/edit`);
							})}
						{tvCapabilities.canChangeCover &&
							admin &&
							media.type !== "image" &&
							row("image-outline", t("cover.change"), () => setCoverOpen(true))}
						<MediaExtraRows
							media={media}
							onClip={() => setClipOpen(true)}
							onSource={() => {
								onClose();
								router.push(`/video/${media.source_media_id ?? 0}`);
							}}
						/>
						{admin &&
							media.type !== "image" &&
							row("pricetags-outline", t("tags.title"), () =>
								setTagsOpen(true),
							)}
						{tvCapabilities.canDelete &&
							admin &&
							row("trash-outline", t("media.delete"), confirmDelete)}
					</Pressable>
				</Pressable>
			</Modal>
			{clipOpen && (
				<ClipSheet
					media={media}
					position={0}
					duration={media.duration}
					onClose={() => setClipOpen(false)}
				/>
			)}
			{tagsOpen && (
				<TagsSheet
					entity="media"
					id={media.id}
					title={media.title}
					onClose={() => setTagsOpen(false)}
				/>
			)}
			<ChangeCoverSheet
				visible={coverOpen}
				media={media}
				onClose={() => setCoverOpen(false)}
				onUploaded={() => setCoverOpen(false)}
			/>
			{LEGACY_COLLECTIONS_ENABLED && media.type !== "image" && (
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

function ActionRow({
	icon,
	label,
	onPress,
}: {
	icon: ComponentProps<typeof Ionicons>["name"];
	label: string;
	onPress: () => void;
}) {
	const { colors, spacing } = useTheme();
	return (
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
}

function MediaExtraRows({
	media,
	onClip,
	onSource,
}: {
	media: Media;
	onClip: () => void;
	onSource: () => void;
}) {
	return (
		<>
			{(media.type === "video" || media.type === "audio") && (
				<ActionRow
					icon="cut-outline"
					label={t("clip.submit")}
					onPress={onClip}
				/>
			)}
			{media.source_media_id != null && media.source_media_id > 0 && (
				<ActionRow
					icon="film-outline"
					label={t("audio.sourceVideo")}
					onPress={onSource}
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
