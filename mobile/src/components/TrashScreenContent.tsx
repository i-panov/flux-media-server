import type { Collection, Media } from "@flux/shared";
import { useState } from "react";
import { ActivityIndicator, Alert, StyleSheet, Text, View } from "react-native";
import {
	EMPTY_TRASH,
	isTrashEmpty,
	type TrashData,
	trashErrorKey,
	useTrash,
	useTrashActions,
} from "../api/trash";
import { useSession } from "../auth/session";
import { collectionTypeLabel } from "../collections/labels";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

import { EmptyState } from "./EmptyState";
import { ErrorState } from "./ErrorState";
import { InlineError } from "./InlineError";
import { Screen } from "./Screen";
import { type ConfirmTarget, TrashConfirmModal } from "./TrashConfirmModal";
import {
	collectionIcon,
	mediaIcon,
	TrashEmptyButton,
	TrashHeader,
	TrashRow,
	TrashSection,
} from "./TrashRow";

const LOAD_ERROR = "trash.loadError" as const;

interface TrashListProps {
	data: TrashData;
	isAdmin: boolean;
	hasError: boolean;
	busy: boolean;
	restoringMediaId: number | undefined;
	purgingMediaId: number | undefined;
	restoringCollectionId: number | undefined;
	purgingCollectionId: number | undefined;
	onRestoreMedia: (media: Media) => void;
	onPurgeMedia: (media: Media) => void;
	onRestoreCollection: (collection: Collection) => void;
	onPurgeCollection: (collection: Collection) => void;
	onEmpty: () => void;
	onRetry: () => void;
}

function TrashList({
	data,
	isAdmin,
	hasError,
	busy,
	restoringMediaId,
	purgingMediaId,
	restoringCollectionId,
	purgingCollectionId,
	onRestoreMedia,
	onPurgeMedia,
	onRestoreCollection,
	onPurgeCollection,
	onEmpty,
	onRetry,
}: TrashListProps) {
	const { colors } = useTheme();
	return (
		<>
			{hasError && (
				<InlineError
					message={t(LOAD_ERROR)}
					onRetry={onRetry}
					testID="trash-inline-error"
					retryTestID="trash-inline-retry"
				/>
			)}
			{isAdmin && <TrashEmptyButton onPress={onEmpty} />}

			{data.collections.length > 0 && (
				<TrashSection
					title={t("trash.collections")}
					count={data.collections.length}
					testID="trash-collections"
				>
					{data.collections.map((collection) => (
						<TrashRow
							key={collection.id}
							testID={`trash-collection-${collection.id}`}
							title={collection.name}
							typeLabel={collectionTypeLabel(collection.type)}
							subtitle=""
							icon={collectionIcon(collection.type)}
							canRestore
							canPurge
							disabled={busy}
							restorePending={restoringCollectionId === collection.id}
							purgePending={purgingCollectionId === collection.id}
							onRestore={() => onRestoreCollection(collection)}
							onPurge={() => onPurgeCollection(collection)}
						/>
					))}
				</TrashSection>
			)}

			{data.media.length > 0 && (
				<TrashSection
					title={t("trash.media")}
					count={data.media.length}
					testID="trash-media"
				>
					{!isAdmin && (
						<Text
							testID="trash-admin-only-media"
							style={[styles.note, { color: colors.textMuted }]}
						>
							{t("trash.adminOnlyMedia")}
						</Text>
					)}
					{data.media.map((media) => {
						const artists = media.artists
							.map((artist) => artist.name)
							.join(", ");
						return (
							<TrashRow
								key={media.id}
								testID={`trash-media-${media.id}`}
								title={media.title}
								typeLabel={collectionTypeLabel(media.type)}
								subtitle={artists === "" ? media.album : artists}
								icon={mediaIcon(media.type)}
								canRestore={isAdmin}
								canPurge={isAdmin}
								disabled={busy}
								restorePending={restoringMediaId === media.id}
								purgePending={purgingMediaId === media.id}
								onRestore={() => onRestoreMedia(media)}
								onPurge={() => onPurgeMedia(media)}
							/>
						);
					})}
				</TrashSection>
			)}
		</>
	);
}

export function TrashScreenContent() {
	useLanguage();
	const { colors, spacing } = useTheme();
	const trash = useTrash();
	const session = useSession();
	const actions = useTrashActions();
	const [confirm, setConfirm] = useState<ConfirmTarget | null>(null);
	const isAdmin = session.data?.is_admin === true;
	const data = trash.data ?? EMPTY_TRASH;

	const notifyError = (error: unknown) => {
		Alert.alert(t("trash.actionError"), t(trashErrorKey(error)));
	};
	const closeConfirm = () => setConfirm(null);

	const restoreMedia = (media: Media) => {
		actions.restoreMedia.mutate(media.id, { onError: notifyError });
	};
	const restoreCollection = (collection: Collection) => {
		actions.restoreCollection.mutate(collection.id, { onError: notifyError });
	};
	const purgeMedia = (media: Media) => setConfirm({ kind: "media", media });
	const purgeCollection = (collection: Collection) =>
		setConfirm({ kind: "collection", collection });

	// Подтверждение показываем только для необратимых операций; restore
	// выполняется сразу, как в web-клиенте.
	const runConfirm = () => {
		if (confirm === null) {
			return;
		}
		const options = {
			onSuccess: closeConfirm,
			onError: (error: unknown) => {
				closeConfirm();
				notifyError(error);
			},
		};
		if (confirm.kind === "empty") {
			actions.emptyTrash.mutate(undefined, options);
			return;
		}
		if (confirm.kind === "media") {
			actions.purgeMedia.mutate(confirm.media.id, options);
			return;
		}
		actions.purgeCollection.mutate(confirm.collection.id, options);
	};

	const busy =
		actions.restoreMedia.isPending ||
		actions.purgeMedia.isPending ||
		actions.restoreCollection.isPending ||
		actions.purgeCollection.isPending ||
		actions.emptyTrash.isPending;
	const restoringMediaId = actions.restoreMedia.isPending
		? actions.restoreMedia.variables
		: undefined;
	const purgingMediaId = actions.purgeMedia.isPending
		? actions.purgeMedia.variables
		: undefined;
	const restoringCollectionId = actions.restoreCollection.isPending
		? actions.restoreCollection.variables
		: undefined;
	const purgingCollectionId = actions.purgeCollection.isPending
		? actions.purgeCollection.variables
		: undefined;

	if (trash.isPending) {
		return (
			<Screen testID="trash-screen">
				<TrashHeader />
				<View
					style={[styles.center, { gap: spacing.sm }]}
					testID="trash-loading"
				>
					<ActivityIndicator color={colors.accent} />
					<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
				</View>
			</Screen>
		);
	}

	if (trash.isError && trash.data === undefined) {
		return (
			<Screen testID="trash-screen">
				<TrashHeader />
				<ErrorState
					title={t(LOAD_ERROR)}
					onRetry={() => void trash.refetch()}
					retryTestID="trash-retry"
					testID="trash-error"
				/>
			</Screen>
		);
	}

	if (isTrashEmpty(data)) {
		return (
			<Screen testID="trash-screen">
				<TrashHeader />
				{trash.isError && (
					<InlineError
						message={t(LOAD_ERROR)}
						onRetry={() => void trash.refetch()}
						testID="trash-inline-error"
						retryTestID="trash-inline-retry"
					/>
				)}
				<EmptyState
					icon="trash-outline"
					title={t("trash.empty")}
					description={t("trash.emptyHint")}
					testID="trash-empty-state"
				/>
			</Screen>
		);
	}

	return (
		<Screen scroll testID="trash-screen">
			<TrashHeader />
			<TrashList
				data={data}
				isAdmin={isAdmin}
				hasError={trash.isError}
				busy={busy}
				restoringMediaId={restoringMediaId}
				purgingMediaId={purgingMediaId}
				restoringCollectionId={restoringCollectionId}
				purgingCollectionId={purgingCollectionId}
				onRestoreMedia={restoreMedia}
				onPurgeMedia={purgeMedia}
				onRestoreCollection={restoreCollection}
				onPurgeCollection={purgeCollection}
				onEmpty={() => setConfirm({ kind: "empty" })}
				onRetry={() => void trash.refetch()}
			/>
			{confirm !== null && (
				<TrashConfirmModal
					target={confirm}
					pending={busy}
					onCancel={closeConfirm}
					onConfirm={runConfirm}
				/>
			)}
		</Screen>
	);
}

const styles = StyleSheet.create({
	center: {
		flex: 1,
		alignItems: "center",
		justifyContent: "center",
		minHeight: 200,
	},
	note: { fontSize: 13, lineHeight: 18 },
});
