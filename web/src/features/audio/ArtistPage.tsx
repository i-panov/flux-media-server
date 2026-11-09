import {
	Alert,
	Button,
	Group,
	Modal,
	Skeleton,
	Stack,
	Text,
	TextInput,
	Title,
} from "@mantine/core";
import { Link, useNavigate, useParams } from "@tanstack/react-router";
import { ArrowLeft, Pencil } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import { useAudioList } from "../../api/media";
import { useArtist, useRenameArtist } from "../../api/metadata";
import { useSession } from "../../api/session";
import { formatDuration } from "../../core/format";
import type { Media } from "../../core/media";
import { ChangeCoverButton } from "../media/ChangeCoverButton";
import { EditMetadataModal } from "../media/EditMetadataModal";
import {
	TVFocusScope,
	TVModalAutoFocus,
	TVModalButton,
	useTVFocusable,
} from "../tv/tvFocus";

function ArtistTrackRow({
	media,
	onEdit,
}: {
	media: Media;
	onEdit: () => void;
}) {
	const { t } = useTranslation();
	const session = useSession();
	const isAdmin = session.data?.is_admin === true;
	return (
		<Group
			justify="space-between"
			wrap="nowrap"
			className="rounded-md border border-[var(--mantine-color-default-border)] px-3 py-2"
		>
			<Link
				to="/audio/$id"
				params={{ id: String(media.id) }}
				className="min-w-0 flex-1 no-underline [color:inherit]"
			>
				<Text fw={600} size="sm" truncate>
					{media.title}
				</Text>
				<Text size="xs" c="dimmed">
					{media.album === "" ? formatDuration(media.duration) : media.album}
				</Text>
			</Link>
			{isAdmin && (
				<Group gap={4} wrap="nowrap">
					<Button variant="subtle" size="xs" onClick={onEdit}>
						{t("metadata.edit")}
					</Button>
					<ChangeCoverButton mediaId={media.id} />
				</Group>
			)}
		</Group>
	);
}

function RenameArtistModal({
	artistId,
	opened,
	onClose,
}: {
	artistId: number;
	opened: boolean;
	onClose: () => void;
}) {
	const { t } = useTranslation();
	const { artist } = useArtist(artistId);
	// Начальное имя берётся при монтировании: родитель монтирует модалку
	// только на время открытия и пересоздаёт её через key, когда имя
	// подгружается позже, — ввод при фоновых рефетчах не затирается.
	const [name, setName] = useState(artist?.name ?? "");
	const rename = useRenameArtist();

	const submit = () => {
		if (rename.isPending) {
			return;
		}
		const trimmed = name.trim();
		if (trimmed === "") {
			return;
		}
		rename.mutate({ id: artistId, name: trimmed }, { onSuccess: onClose });
	};

	return (
		<Modal
			opened={opened}
			onClose={onClose}
			title={t("artists.renameTitle")}
			centered
		>
			<TVModalAutoFocus focusKey="rename-artist-cancel" />
			<Stack gap="md">
				<TextInput
					label={t("artists.name")}
					value={name}
					data-autofocus
					onChange={(event) => setName(event.currentTarget.value)}
					onKeyDown={(event) => {
						if (event.key === "Enter") {
							submit();
						}
					}}
				/>
				{rename.isError && (
					<Text size="sm" c="red">
						{rename.error instanceof ApiError && rename.error.status === 409
							? t("artists.nameTaken")
							: t("artists.renameError")}
					</Text>
				)}
				<Group justify="flex-end">
					<TVModalButton
						focusKey="rename-artist-cancel"
						variant="default"
						onClick={onClose}
					>
						{t("collections.cancel")}
					</TVModalButton>
					<TVModalButton
						focusKey="rename-artist-save"
						loading={rename.isPending}
						disabled={name.trim() === "" || rename.isPending}
						onClick={submit}
					>
						{t("collections.save")}
					</TVModalButton>
				</Group>
			</Stack>
		</Modal>
	);
}

export function ArtistPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { id } = useParams({ from: "/artists/$id" });
	const artistId = Number(id);
	const valid = Number.isSafeInteger(artistId) && artistId > 0;
	const backLabel = t("audio.back");
	const backToAudio = () => {
		void navigate({ to: "/audio" });
	};

	const session = useSession();
	const isAdmin = session.data?.is_admin === true;
	const {
		artist,
		isPending,
		isError: isArtistError,
		refetch: refetchArtists,
	} = useArtist(valid ? artistId : 0);
	const list = useAudioList("", valid ? artistId : undefined, valid);
	const [renameOpened, setRenameOpened] = useState(false);
	const [editMedia, setEditMedia] = useState<Media | null>(null);
	// ТВ-режим: корень страницы — spatial-секция, треки внутри —
	// контент секции.
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("artist-page");
	const retryLabel = t("common.retry");

	const {
		hasNextPage,
		isFetchingNextPage,
		isFetchNextPageError,
		fetchNextPage,
	} = list;

	// Фильтр по артисту — на сервере (artist_id), поэтому клиент не
	// догружает всю аудиотеку и не фильтрует её в памяти.
	const tracks = list.data?.pages.flatMap((page) => page.items) ?? [];

	if (!valid) {
		return (
			<Stack gap="md">
				<Alert color="red" variant="light">
					{t("artists.notFound")}
				</Alert>
				<Button variant="light" w="fit-content" onClick={backToAudio}>
					{backLabel}
				</Button>
			</Stack>
		);
	}

	if (isPending || list.isPending) {
		return (
			<Stack gap="md">
				<Skeleton height={32} width="40%" radius="sm" />
				<Skeleton height={64} radius="md" />
				<Skeleton height={64} radius="md" />
			</Stack>
		);
	}

	if (isArtistError || artist === undefined) {
		return (
			<Stack gap="md">
				<Alert
					color="red"
					variant="light"
					title={isArtistError ? t("artists.loadError") : t("artists.notFound")}
				>
					{isArtistError && (
						<Button
							variant="light"
							size="xs"
							mt="xs"
							onClick={() => void refetchArtists()}
						>
							{retryLabel}
						</Button>
					)}
				</Alert>
				<Button variant="light" w="fit-content" onClick={backToAudio}>
					{backLabel}
				</Button>
			</Stack>
		);
	}

	return (
		<Stack
			gap="lg"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-focus-key="artist-page"
		>
			<TVFocusScope focusKey="artist-page">
				<Button
					variant="subtle"
					w="fit-content"
					leftSection={<ArrowLeft size={16} />}
					onClick={backToAudio}
				>
					{backLabel}
				</Button>
				<Group justify="space-between" align="center" wrap="wrap">
					<Title order={1} size="h2">
						{artist.name}
					</Title>
					{isAdmin && (
						<Button
							variant="light"
							leftSection={<Pencil size={16} />}
							onClick={() => setRenameOpened(true)}
						>
							{t("artists.rename")}
						</Button>
					)}
				</Group>
				{list.isError && tracks.length === 0 ? (
					<Alert color="red" variant="light" title={t("artists.tracksError")}>
						<Button
							variant="light"
							size="xs"
							mt="xs"
							onClick={() => void list.refetch()}
						>
							{retryLabel}
						</Button>
					</Alert>
				) : tracks.length === 0 ? (
					<Text c="dimmed">{t("artists.noTracks")}</Text>
				) : (
					<Stack gap="xs">
						{tracks.map((media) => (
							<ArtistTrackRow
								key={media.id}
								media={media}
								onEdit={() => setEditMedia(media)}
							/>
						))}
					</Stack>
				)}
				{isFetchNextPageError ? (
					<Alert color="red" variant="light" title={t("artists.tracksError")}>
						<Button
							variant="light"
							size="xs"
							mt="xs"
							onClick={() => void fetchNextPage()}
						>
							{retryLabel}
						</Button>
					</Alert>
				) : (
					hasNextPage && (
						<Button
							variant="light"
							w="fit-content"
							loading={isFetchingNextPage}
							onClick={() => void fetchNextPage()}
						>
							{t("audio.loadMore")}
						</Button>
					)
				)}
			</TVFocusScope>
			{/* Модалка монтируется только на время открытия, а key по имени
			пересоздаёт её, когда артист подгружается позже: поле стартует
			с загруженным именем, а не с пустого маунта. */}
			{renameOpened && (
				<RenameArtistModal
					key={`${artistId}:${artist?.name ?? ""}`}
					opened
					artistId={artistId}
					onClose={() => setRenameOpened(false)}
				/>
			)}
			{editMedia !== null && (
				<EditMetadataModal
					key={editMedia.id}
					opened
					media={editMedia}
					onClose={() => setEditMedia(null)}
				/>
			)}
		</Stack>
	);
}
