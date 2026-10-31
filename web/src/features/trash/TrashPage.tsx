import {
	ActionIcon,
	Alert,
	Badge,
	Button,
	Card,
	Group,
	Modal,
	Skeleton,
	Stack,
	Text,
	Title,
	Tooltip,
} from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { Link } from "@tanstack/react-router";
import { ArrowLeft, RotateCcw, Trash2 } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import type { Collection } from "../../api/collections";
import { useSession } from "../../api/session";
import { useTrash, useTrashActions } from "../../api/trash";
import { isMediaType, MEDIA_TYPE_LABEL_KEYS } from "../../components/mediaType";
import type { Media } from "../../core/media";
import {
	TVFocusScope,
	TVModalAutoFocus,
	TVModalButton,
	useTVFocusable,
} from "../tv/tvFocus";

function TrashActionsBar({
	onRestore,
	onPurge,
	restorePending,
	purgePending,
}: {
	onRestore: () => void;
	onPurge: () => void;
	restorePending: boolean;
	purgePending: boolean;
}) {
	const { t } = useTranslation();
	const restoreLabel = t("trash.restore");
	const purgeLabel = t("trash.purge");
	return (
		<Group gap="xs">
			<Tooltip label={restoreLabel} withArrow>
				<ActionIcon
					variant="light"
					aria-label={restoreLabel}
					loading={restorePending}
					onClick={onRestore}
				>
					<RotateCcw size={16} />
				</ActionIcon>
			</Tooltip>
			<Tooltip label={purgeLabel} withArrow>
				<ActionIcon
					color="red"
					variant="light"
					aria-label={purgeLabel}
					loading={purgePending}
					onClick={onPurge}
				>
					<Trash2 size={16} />
				</ActionIcon>
			</Tooltip>
		</Group>
	);
}

function TrashCollectionCard({
	collection,
	restorePending,
	purgePending,
	onRestore,
	onPurge,
}: {
	collection: Collection;
	restorePending: boolean;
	purgePending: boolean;
	onRestore: () => void;
	onPurge: () => void;
}) {
	const { t } = useTranslation();
	return (
		<Card withBorder padding="md" radius="md">
			<Group justify="space-between" wrap="wrap" gap="sm">
				<Group gap="sm">
					<Text fw={600}>{collection.name}</Text>
					{isMediaType(collection.type) && (
						<Badge variant="light" color="violet">
							{t(MEDIA_TYPE_LABEL_KEYS[collection.type])}
						</Badge>
					)}
				</Group>
				<TrashActionsBar
					restorePending={restorePending}
					purgePending={purgePending}
					onRestore={onRestore}
					onPurge={onPurge}
				/>
			</Group>
		</Card>
	);
}

function TrashMediaCard({
	media,
	isAdmin,
	restorePending,
	purgePending,
	onRestore,
	onPurge,
}: {
	media: Media;
	isAdmin: boolean;
	restorePending: boolean;
	purgePending: boolean;
	onRestore: () => void;
	onPurge: () => void;
}) {
	const { t } = useTranslation();
	return (
		<Card withBorder padding="md" radius="md">
			<Group justify="space-between" wrap="wrap" gap="sm">
				<Group gap="sm" className="min-w-0">
					<Text fw={600} truncate>
						{media.title}
					</Text>
					{isMediaType(media.type) && (
						<Badge variant="light" color="gray">
							{t(MEDIA_TYPE_LABEL_KEYS[media.type])}
						</Badge>
					)}
				</Group>
				{isAdmin && (
					<TrashActionsBar
						restorePending={restorePending}
						purgePending={purgePending}
						onRestore={onRestore}
						onPurge={onPurge}
					/>
				)}
			</Group>
		</Card>
	);
}

export function TrashPage() {
	const { t } = useTranslation();
	const session = useSession();
	const trash = useTrash();
	const actions = useTrashActions();
	const [emptyOpened, setEmptyOpened] = useState(false);
	const isAdmin = session.data?.is_admin === true;
	// ТВ-режим: корень страницы — spatial-секция, карточки внутри —
	// контент секции.
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("trash-page");
	const notifyError = (error: unknown) => {
		notifications.show({
			color: "red",
			title: t("trash.actionError"),
			message: error instanceof ApiError ? error.message : "",
		});
	};

	if (trash.isPending) {
		return (
			<Stack gap="md">
				<Skeleton height={32} width="30%" radius="sm" />
				<Skeleton height={160} radius="md" />
			</Stack>
		);
	}

	if (trash.isError) {
		return (
			<Stack gap="md">
				<Alert color="red" variant="light" title={t("trash.loadError")}>
					<Button
						variant="light"
						size="xs"
						mt="xs"
						onClick={() => void trash.refetch()}
					>
						{t("common.retry")}
					</Button>
				</Alert>
				<Button
					component={Link}
					to="/settings"
					variant="light"
					w="fit-content"
					leftSection={<ArrowLeft size={16} />}
				>
					{t("trash.back")}
				</Button>
			</Stack>
		);
	}

	const data = trash.data ?? { collections: [], media: [] };
	const empty = data.collections.length === 0 && data.media.length === 0;

	return (
		<Stack
			gap="lg"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-focus-key="trash-page"
		>
			<TVFocusScope focusKey="trash-page">
				<Group justify="space-between" align="center" wrap="wrap">
					<Group gap="sm">
						<Button
							component={Link}
							to="/settings"
							variant="subtle"
							leftSection={<ArrowLeft size={16} />}
						>
							{t("trash.back")}
						</Button>
						<Title order={1} size="h2">
							{t("trash.title")}
						</Title>
					</Group>
					{isAdmin && !empty && (
						<Button
							color="red"
							variant="light"
							leftSection={<Trash2 size={16} />}
							onClick={() => setEmptyOpened(true)}
						>
							{t("trash.emptyAction")}
						</Button>
					)}
				</Group>

				{empty ? (
					<Card withBorder padding="xl" radius="md">
						<Stack align="center" gap="sm">
							<Trash2
								size={40}
								className="text-[var(--mantine-color-dimmed)]"
							/>
							<Text c="dimmed">{t("trash.empty")}</Text>
						</Stack>
					</Card>
				) : (
					<Stack gap="lg">
						{data.collections.length > 0 && (
							<Stack gap="sm">
								<Title order={2} size="h4">
									{t("trash.collections")}
								</Title>
								{data.collections.map((collection) => (
									<TrashCollectionCard
										key={collection.id}
										collection={collection}
										restorePending={actions.restoreCollection.isPending}
										purgePending={actions.purgeCollection.isPending}
										onRestore={() => {
											actions.restoreCollection.mutate(collection.id, {
												onError: notifyError,
											});
										}}
										onPurge={() => {
											actions.purgeCollection.mutate(collection.id, {
												onError: notifyError,
											});
										}}
									/>
								))}
							</Stack>
						)}
						{data.media.length > 0 && (
							<Stack gap="sm">
								<Title order={2} size="h4">
									{t("trash.media")}
								</Title>
								{!isAdmin && (
									<Text size="sm" c="dimmed">
										{t("trash.adminOnlyMedia")}
									</Text>
								)}
								{data.media.map((media) => (
									<TrashMediaCard
										key={media.id}
										media={media}
										isAdmin={isAdmin}
										restorePending={actions.restoreMedia.isPending}
										purgePending={actions.purgeMedia.isPending}
										onRestore={() => {
											actions.restoreMedia.mutate(media.id, {
												onError: notifyError,
											});
										}}
										onPurge={() => {
											actions.purgeMedia.mutate(media.id, {
												onError: notifyError,
											});
										}}
									/>
								))}
							</Stack>
						)}
					</Stack>
				)}
			</TVFocusScope>

			<Modal
				opened={emptyOpened}
				onClose={() => setEmptyOpened(false)}
				title={t("trash.emptyTitle")}
				centered
			>
				<TVModalAutoFocus focusKey="empty-trash-cancel" />
				<Stack gap="md">
					<Text size="sm">{t("trash.emptyConfirm")}</Text>
					<Group justify="flex-end">
						<TVModalButton
							focusKey="empty-trash-cancel"
							variant="default"
							onClick={() => setEmptyOpened(false)}
						>
							{t("collections.cancel")}
						</TVModalButton>
						<TVModalButton
							focusKey="empty-trash-confirm"
							color="red"
							loading={actions.emptyTrash.isPending}
							onClick={() => {
								actions.emptyTrash.mutate(undefined, {
									onSuccess: () => setEmptyOpened(false),
									onError: notifyError,
								});
							}}
						>
							{t("trash.emptyAction")}
						</TVModalButton>
					</Group>
				</Stack>
			</Modal>
		</Stack>
	);
}
