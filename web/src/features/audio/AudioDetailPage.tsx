import {
	Alert,
	Button,
	Group,
	Skeleton,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { Link, useNavigate, useParams } from "@tanstack/react-router";
import { Music, Pause, Play } from "lucide-react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import { useMedia } from "../../api/media";
import { formatDuration } from "../../core/format";
import { AddToCollectionButton } from "../collections/AddToCollectionButton";
import { ArtistFavoriteButton } from "../favorites/ArtistFavoriteButton";
import { FavoriteButton } from "../favorites/FavoriteButton";
import { MediaAdminActions } from "../media/MediaAdminActions";
import { MetaItem } from "../media/MetaItem";
import { useAudioPlayer } from "../player/AudioPlayerProvider";

export function AudioDetailPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { id } = useParams({ from: "/audio/$id" });
	const mediaId = Number(id);
	const valid = Number.isInteger(mediaId) && mediaId > 0;

	const media = useMedia(valid ? mediaId : 0, valid);
	const player = useAudioPlayer();

	const goBack = () => {
		void navigate({ to: "/audio" });
	};
	const backLabel = t("audio.back");

	if (!valid) {
		return (
			<Stack gap="md">
				<Alert color="red" variant="light">
					{t("audio.notFound")}
				</Alert>
				<Button variant="light" w="fit-content" onClick={goBack}>
					{backLabel}
				</Button>
			</Stack>
		);
	}

	if (media.isPending) {
		return (
			<Group align="flex-start" gap="lg" wrap="wrap">
				<Skeleton height={240} width={240} radius="md" />
				<Stack gap="sm" className="min-w-0 flex-1">
					<Skeleton height={28} width="50%" radius="sm" />
					<Skeleton height={48} radius="sm" />
					<Skeleton height={16} width="80%" radius="sm" />
				</Stack>
			</Group>
		);
	}

	if (media.isError || media.data === undefined) {
		const notFound =
			media.error instanceof ApiError && media.error.status === 404;
		return (
			<Stack gap="md">
				<Alert
					color="red"
					variant="light"
					title={notFound ? t("audio.notFound") : t("audio.loadError")}
				>
					<Group gap="xs" mt="xs">
						{!notFound && (
							<Button
								variant="light"
								size="xs"
								onClick={() => {
									void media.refetch();
								}}
							>
								{t("common.retry")}
							</Button>
						)}
						<Button variant="light" size="xs" onClick={goBack}>
							{backLabel}
						</Button>
					</Group>
				</Alert>
			</Stack>
		);
	}

	const item = media.data;
	const isCurrent = player.current?.id === item.id;
	// Обложка — декоративный фон: битая картинка не должна оставлять иконку.
	const coverStyle =
		item.cover_url === ""
			? undefined
			: { backgroundImage: `url("${item.cover_url}")` };

	return (
		<Stack gap="lg">
			<Button variant="subtle" w="fit-content" onClick={goBack}>
				{backLabel}
			</Button>
			<Group align="flex-start" gap="lg" wrap="wrap">
				<div
					aria-hidden="true"
					style={coverStyle}
					className="grid h-60 w-60 shrink-0 place-items-center rounded-md bg-[var(--mantine-color-default-hover)] bg-cover bg-center"
				>
					{item.cover_url === "" && (
						<Music size={48} className="text-[var(--mantine-color-dimmed)]" />
					)}
				</div>
				<Stack
					gap="md"
					className="min-w-0 flex-1 basis-full min-[48em]:basis-auto"
				>
					<Group justify="space-between" align="flex-start" wrap="wrap">
						<Title order={1} size="h2">
							{item.title}
						</Title>
						<Group gap="xs">
							<FavoriteButton mediaId={item.id} type="audio" />
							<AddToCollectionButton mediaId={item.id} type="audio" />
						</Group>
					</Group>
					<Group gap="xs">
						<Button
							leftSection={
								isCurrent && player.playing ? (
									<Pause size={16} />
								) : (
									<Play size={16} fill="currentColor" />
								)
							}
							onClick={() => {
								if (isCurrent) {
									player.toggle();
								} else {
									player.playMedia(item);
								}
							}}
						>
							{isCurrent && player.playing
								? t("player.pause")
								: t("player.play")}
						</Button>
						{isCurrent && (
							<Button
								variant="light"
								onClick={() => void navigate({ to: "/player" })}
							>
								{t("player.open")}
							</Button>
						)}
					</Group>
					{isCurrent && player.error !== null && (
						<Alert color="red" variant="light" title={t("player.error")}>
							{player.error}
						</Alert>
					)}
					<Group gap="xl">
						{item.artists.length > 0 && (
							<Stack gap={4}>
								<Text size="xs" c="dimmed">
									{t("audio.meta.artist")}
								</Text>
								<Group gap="xs">
									{item.artists.map((artist) => (
										<Group key={artist.id} gap={2} wrap="nowrap">
											<Link
												to="/artists/$id"
												params={{ id: String(artist.id) }}
												className="no-underline [color:inherit]"
											>
												<Text size="sm" fw={600}>
													{artist.name}
												</Text>
											</Link>
											<ArtistFavoriteButton
												artistId={artist.id}
												artistName={artist.name}
												size={15}
											/>
										</Group>
									))}
								</Group>
							</Stack>
						)}
						{item.album !== "" && (
							<MetaItem label={t("audio.meta.album")} value={item.album} />
						)}
						{item.genre !== "" && (
							<MetaItem label={t("audio.meta.genre")} value={item.genre} />
						)}
						{item.year > 0 && (
							<MetaItem
								label={t("audio.meta.year")}
								value={String(item.year)}
							/>
						)}
						<MetaItem
							label={t("audio.meta.duration")}
							value={formatDuration(item.duration)}
						/>
					</Group>
					{item.description !== "" && <Text>{item.description}</Text>}
					<MediaAdminActions media={item} backPath="/audio" />
				</Stack>
			</Group>
		</Stack>
	);
}
