import {
	Alert,
	Button,
	Group,
	Skeleton,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { useNavigate, useParams } from "@tanstack/react-router";
import { Music } from "lucide-react";
import { useRef } from "react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import { useMedia, useMediaReload, useSavedTime } from "../../api/media";
import { formatDuration } from "../../core/format";
import { MetaItem } from "../media/MetaItem";
import { useMediaProgress } from "../media/useMediaProgress";

export function AudioDetailPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { id } = useParams({ from: "/audio/$id" });
	const mediaId = Number(id);
	const valid = Number.isInteger(mediaId) && mediaId > 0;

	const media = useMedia(valid ? mediaId : 0, valid);
	const reload = useMediaReload(valid ? mediaId : 0);
	const audioRef = useRef<HTMLAudioElement | null>(null);
	const position = useSavedTime(audioRef);
	const progress = useMediaProgress(mediaId, audioRef, valid);

	const goBack = () => {
		void navigate({ to: "/audio" });
	};
	const backLabel = t("audio.back");

	// Позиция сохраняется перед ЛЮБЫМ изменением nonce (ошибка потока,
	// кнопка retry) — иначе remount сбрасывает её в 0.
	const handleMediaError = () => {
		position.save();
		reload.handleError();
	};
	const handleRetry = () => {
		position.save();
		reload.retry();
	};

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
	const artists = item.artists.map((artist) => artist.name).join(", ");
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
				<Stack gap="md" className="min-w-0 flex-1">
					<Title order={1} size="h2">
						{item.title}
					</Title>
					{/* biome-ignore lint/a11y/useMediaCaption: у аудио нет видеоряда и субтитров. */}
					<audio
						ref={audioRef}
						key={reload.nonce}
						controls
						preload="metadata"
						src={`/api/media/${item.id}/stream`}
						className="w-full"
						onError={handleMediaError}
						onLoadedMetadata={() => {
							position.restore();
							progress.handleLoadedMetadata();
						}}
						onPause={progress.handlePause}
						onTimeUpdate={progress.handleTimeUpdate}
						onEnded={progress.handleEnded}
					/>
					{reload.failed && (
						<Alert color="red" variant="light" title={t("audio.loadError")}>
							<Button variant="light" size="xs" mt="xs" onClick={handleRetry}>
								{t("common.retry")}
							</Button>
						</Alert>
					)}
					<Group gap="xl">
						{artists !== "" && (
							<MetaItem label={t("audio.meta.artist")} value={artists} />
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
				</Stack>
			</Group>
		</Stack>
	);
}
