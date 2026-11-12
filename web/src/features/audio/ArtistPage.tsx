import {
	Alert,
	Avatar,
	Button,
	Group,
	Modal,
	Skeleton,
	Stack,
	Text,
	TextInput,
	Title,
} from "@mantine/core";
import { useNavigate, useParams } from "@tanstack/react-router";
import { ArrowLeft, Music, Pencil } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import { useAudioList } from "../../api/media";
import { useArtist, useRenameArtist } from "../../api/metadata";
import { useSession } from "../../api/session";
import { formatDuration } from "../../core/format";
import type { Media } from "../../core/media";
import { ArtistFavoriteButton } from "../favorites/ArtistFavoriteButton";
import { ChangeCoverButton } from "../media/ChangeCoverButton";
import { EditMetadataModal } from "../media/EditMetadataModal";
import { useAudioPlayer } from "../player/AudioPlayerProvider";
import {
	clickNode,
	TVButton,
	TVFocusScope,
	TVModalAutoFocus,
	useTVFocusable,
} from "../tv/tvFocus";
import { useTVMode } from "../tv/useTVMode";

function ArtistTrackRow({
	media,
	onEdit,
	canEditMetadata,
	canChangeCover,
}: {
	media: Media;
	onEdit: () => void;
	canEditMetadata: boolean;
	canChangeCover: boolean;
}) {
	const { t } = useTranslation();
	const player = useAudioPlayer();
	// Строка трека — spatial-цель: Enter запускает трек в мини-плеере.
	const { targetRef: rowRef, tvMode } = useTVFocusable<HTMLDivElement>(
		`artist-track-${media.id}`,
		() => player.playQueue([media], 0),
	);
	return (
		<Group
			ref={rowRef}
			tabIndex={tvMode ? -1 : undefined}
			justify="space-between"
			wrap="nowrap"
			className="rounded-md border border-[var(--mantine-color-default-border)] px-3 py-2"
		>
			<button
				type="button"
				onClick={() => player.playQueue([media], 0)}
				className="min-w-0 flex-1 cursor-pointer border-0 bg-transparent p-0 text-left [color:inherit]"
			>
				<Text fw={600} size="sm" truncate>
					{media.title}
				</Text>
				<Text size="xs" c="dimmed">
					{media.album === "" ? formatDuration(media.duration) : media.album}
				</Text>
			</button>
			{canEditMetadata && (
				<Group gap={4} wrap="nowrap">
					<Button variant="subtle" size="xs" onClick={onEdit}>
						{t("metadata.edit")}
					</Button>
					{canChangeCover && <ChangeCoverButton mediaId={media.id} />}
				</Group>
			)}
		</Group>
	);
}

function ArtistBackButton({
	label,
	onClick,
}: {
	label: string;
	onClick: () => void;
}) {
	const { targetRef } = useTVFocusable<HTMLButtonElement>(
		"artist-back",
		clickNode,
	);
	return (
		<Button
			ref={targetRef}
			data-tv-focus-key="artist-back"
			variant="subtle"
			w="fit-content"
			leftSection={<ArrowLeft size={16} />}
			onClick={onClick}
		>
			{label}
		</Button>
	);
}

function ArtistFavoriteControl({
	artistId,
	artistName,
}: {
	artistId: number;
	artistName: string;
}) {
	// Отдельный компонент: он монтируется только вместе с загруженной
	// страницей, поэтому useFocusable получает настоящий DOM-узел сразу.
	// Внутри ArtistPage hook живёт с первого рендера скелетона и при
	// позднем появлении узла spatial-реестр остаётся с node=null.
	const { targetRef, tvMode } = useTVFocusable<HTMLDivElement>(
		"artist-favorite",
		(node) => {
			node?.querySelector<HTMLButtonElement>("button")?.click();
		},
	);
	return (
		<div
			ref={targetRef}
			tabIndex={tvMode ? -1 : undefined}
			className="rounded-full"
		>
			<ArtistFavoriteButton artistId={artistId} artistName={artistName} />
		</div>
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
					<TVButton
						focusKey="rename-artist-cancel"
						variant="default"
						onClick={onClose}
					>
						{t("collections.cancel")}
					</TVButton>
					<TVButton
						focusKey="rename-artist-save"
						loading={rename.isPending}
						disabled={name.trim() === "" || rename.isPending}
						onClick={submit}
					>
						{t("collections.save")}
					</TVButton>
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
	const { capabilities } = useTVMode();
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
	// контент секции. Capabilities скрывают write-действия (read-only),
	// но избранное остаётся.
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("artist-page");
	// Скелетон — отдельная цель: route-focus не должен уходить в навбар,
	// пока данные артиста грузятся.
	const { targetRef: tvLoadingRef } =
		useTVFocusable<HTMLDivElement>("artist-loading");
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
	const canEditMetadata = isAdmin && capabilities.canEditMetadata;
	const canChangeCover = isAdmin && capabilities.canChangeCover;

	if (!valid) {
		return (
			<Stack gap="md">
				<Alert color="red" variant="light">
					{t("artists.notFound")}
				</Alert>
				<ArtistBackButton label={backLabel} onClick={backToAudio} />
			</Stack>
		);
	}

	if (isPending || list.isPending) {
		return (
			<Stack gap="md" ref={tvLoadingRef} tabIndex={tvMode ? -1 : undefined}>
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
				<ArtistBackButton label={backLabel} onClick={backToAudio} />
			</Stack>
		);
	}

	return (
		<Stack
			gap="lg"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-page-root="true"
			data-tv-focus-key="artist-page"
		>
			<TVFocusScope focusKey="artist-page">
				<ArtistBackButton label={backLabel} onClick={backToAudio} />
				<Group justify="space-between" align="center" wrap="wrap">
					<Group gap="md" align="center">
						<Avatar
							size={72}
							radius="xl"
							src={
								artist.has_cover
									? `/api/artists/${artistId}/cover?v=${encodeURIComponent(artist.updated_at)}`
									: undefined
							}
						>
							<Music size={28} />
						</Avatar>
						<Group gap="xs" align="center">
							<Title order={1} size="h2">
								{artist.name}
							</Title>
							<ArtistFavoriteControl
								artistId={artistId}
								artistName={artist.name}
							/>
						</Group>
					</Group>
					{canEditMetadata && (
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
								canEditMetadata={canEditMetadata}
								canChangeCover={canChangeCover}
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
						<TVButton
							focusKey="artist-load-more"
							variant="light"
							w="fit-content"
							loading={isFetchingNextPage}
							onClick={() => void fetchNextPage()}
						>
							{t("audio.loadMore")}
						</TVButton>
					)
				)}
			</TVFocusScope>
			{/* Модалка монтируется только на время открытия, а key по имени
			пересоздаёт её, когда артист подгружается позже: поле стартует
			с загруженным именем, а не с пустого маунта. */}
			{canEditMetadata && renameOpened && (
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
