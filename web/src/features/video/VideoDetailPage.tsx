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
import { useCallback, useEffect, useRef } from "react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import {
	useMedia,
	useMediaReload,
	useMediaSubs,
	useSavedTime,
} from "../../api/media";
import { formatDuration, splitSubLang } from "../../core/format";
import type { Media } from "../../core/media";
import { AddToCollectionButton } from "../collections/AddToCollectionButton";
import { FavoriteButton } from "../favorites/FavoriteButton";
import { MediaAdminActions } from "../media/MediaAdminActions";
import { MetaItem } from "../media/MetaItem";
import { useMediaProgress } from "../media/useMediaProgress";
import { clickNode, TVFocusScope, useTVFocusable } from "../tv/tvFocus";
import { TVVideoControls } from "./TVVideoControls";

// Мета-строка деталей: свой компонент, чтобы страница оставалась
// в лимите строк.
function VideoMeta({ item }: { item: Media }) {
	const { t } = useTranslation();
	const resolution =
		item.width > 0 && item.height > 0
			? `${item.width}×${item.height}`
			: t("common.emptyFallback");
	return (
		<Group gap="xl">
			<MetaItem
				label={t("video.meta.year")}
				value={item.year > 0 ? String(item.year) : t("common.emptyFallback")}
			/>
			<MetaItem
				label={t("video.meta.duration")}
				value={formatDuration(item.duration)}
			/>
			<MetaItem label={t("video.meta.resolution")} value={resolution} />
			<MetaItem label={t("video.meta.views")} value={String(item.view_count)} />
		</Group>
	);
}

// React не поддерживает onError на <track> (только audio/video/img/...),
// поэтому ошибку загрузки дорожки ловим нативным слушателем: при истёкшей
// access-куке выбор субтитров даёт 401, а видео при этом продолжает играть.
const HTTP_URL_PATTERN = /^https?:\/\//i;

export function SubTrack({
	base,
	label,
	url,
	onError,
}: {
	base: string;
	label: string;
	url: string;
	onError: () => void;
}) {
	const ref = useRef<HTMLTrackElement | null>(null);
	useEffect(() => {
		const el = ref.current;
		if (el === null) {
			return;
		}
		el.addEventListener("error", onError);
		return () => {
			el.removeEventListener("error", onError);
		};
	}, [onError]);
	return (
		<track ref={ref} kind="subtitles" srcLang={base} label={label} src={url} />
	);
}

export function VideoDetailPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { id } = useParams({ from: "/video/$id" });
	const mediaId = Number(id);
	const valid = Number.isInteger(mediaId) && mediaId > 0;

	const media = useMedia(valid ? mediaId : 0, valid);
	const subs = useMediaSubs(valid ? mediaId : 0, valid);
	const reload = useMediaReload(valid ? mediaId : 0);
	const videoRef = useRef<HTMLVideoElement | null>(null);
	// ТВ-режим: секция и кнопка назад — точки входа spatial-навигации.
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("video-detail");
	// Отдельный ключ у скелетона: когда данные придут, route-focus увидит
	// новый корень и переведёт фокус на кнопку/плеер, а не оставит его
	// на исчезнувшем узле.
	const { targetRef: tvLoadingRef } = useTVFocusable<HTMLDivElement>(
		"video-detail-loading",
	);
	// Назад — secondary: route-focus сначала ведёт на кнопку play OSD,
	// а к списку видео пульт доходит стрелками.
	const { targetRef: tvBackRef } = useTVFocusable<HTMLButtonElement>(
		"video-detail-back",
		clickNode,
		undefined,
		{ secondary: true },
	);
	const position = useSavedTime(videoRef);
	const played = useRef(false);
	const videoProgress = useMediaProgress(mediaId, videoRef, valid);

	// Переход между видео без размонтирования: счётчик нового видео
	// тоже должен сработать один раз.
	// biome-ignore lint/correctness/useExhaustiveDependencies: mediaId — триггер сброса, в теле эффекта не читается.
	useEffect(() => {
		played.current = false;
	}, [mediaId]);

	const goBack = () => void navigate({ to: "/video" });
	const backLabel = t("video.back");

	// Позиция сохраняется перед ЛЮБЫМ изменением nonce (ошибка video,
	// ошибка track, кнопка retry) — иначе remount сбрасывает её в 0.
	// useCallback со стабильными зависимостями: SubTrack подписывается
	// нативным слушателем в эффекте от onError, и новая ссылка на каждой
	// отрисовке давала бы переподписку на каждый рендер. Оба колбэка
	// стабильны сами по себе, поэтому деструктурируем их из объектов,
	// которые пересоздаются на каждый рендер.
	const { save: savePosition } = position;
	const { handleError: handleReloadError } = reload;
	const handleMediaError = useCallback(() => {
		savePosition();
		handleReloadError();
	}, [savePosition, handleReloadError]);
	const handleRetry = () => {
		position.save();
		reload.retry();
	};

	if (!valid) {
		return (
			<Stack gap="md" ref={tvLoadingRef} tabIndex={tvMode ? -1 : undefined}>
				<Alert color="red" variant="light">
					{t("video.notFound")}
				</Alert>
				<Button variant="light" w="fit-content" onClick={goBack}>
					{backLabel}
				</Button>
			</Stack>
		);
	}

	if (media.isPending) {
		return (
			<Stack gap="md" ref={tvLoadingRef} tabIndex={tvMode ? -1 : undefined}>
				<Skeleton height={360} radius="md" />
				<Skeleton height={28} width="50%" radius="sm" />
				<Skeleton height={16} width="80%" radius="sm" />
			</Stack>
		);
	}

	if (media.isError || media.data === undefined) {
		const notFound =
			media.error instanceof ApiError && media.error.status === 404;
		return (
			<Stack gap="md" ref={tvLoadingRef} tabIndex={tvMode ? -1 : undefined}>
				<Alert
					color="red"
					variant="light"
					title={notFound ? t("video.notFound") : t("video.loadError")}
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

	return (
		<Stack
			gap="lg"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-page-root="true"
			data-tv-focus-key="video-detail"
		>
			<TVFocusScope focusKey="video-detail">
				<Button
					variant="subtle"
					w="fit-content"
					ref={tvBackRef}
					data-tv-focus-key="video-detail-back"
					onClick={goBack}
				>
					{backLabel}
				</Button>
				{/* Сервер отдаёт только субтитры-переводы, дорожек captions нет —
			размечать перевод как captions было бы неверно. Выбор дорожки
			доступен в нативных контролах обычного режима; в ТВ-OSD
			отдельного меню дорожек пока нет. */}
				<div className="tv-video-shell">
					{/* biome-ignore lint/a11y/useMediaCaption: нет captions-дорожек в данных. */}
					<video
						ref={videoRef}
						key={reload.nonce}
						controls={!tvMode}
						preload="metadata"
						src={`/api/media/${item.id}/stream`}
						poster={item.thumbnail_url === "" ? undefined : item.thumbnail_url}
						className="aspect-video w-full rounded-md bg-black"
						onError={handleMediaError}
						onLoadedMetadata={() => {
							position.restore();
							videoProgress.handleLoadedMetadata();
						}}
						onPlay={() => {
							// Счётчик backend инкрементирует в Stream: подтягиваем
							// свежее значение один раз за просмотр, плеер не трогаем.
							if (!played.current) {
								played.current = true;
								void media.refetch();
							}
						}}
						onPause={videoProgress.handlePause}
						onTimeUpdate={videoProgress.handleTimeUpdate}
						onEnded={videoProgress.handleEnded}
					>
						{(subs.data ?? []).map((track) => {
							const { base, label } = splitSubLang(track.lang);
							return (
								<SubTrack
									key={track.lang}
									base={base}
									label={label}
									url={track.url}
									onError={handleMediaError}
								/>
							);
						})}
					</video>
					{tvMode && (
						<TVVideoControls
							videoRef={videoRef}
							videoNonce={reload.nonce}
							onBack={goBack}
						/>
					)}
				</div>
				{reload.failed && (
					<Alert color="red" variant="light" title={t("video.loadError")}>
						<Button variant="light" size="xs" mt="xs" onClick={handleRetry}>
							{t("common.retry")}
						</Button>
					</Alert>
				)}
				{subs.isError && (
					<Alert color="yellow" variant="light">
						{t("video.subsError")}
					</Alert>
				)}
				<Stack gap="xs">
					<Group justify="space-between" align="center" wrap="wrap">
						<Title order={1} size="h2">
							{item.title}
						</Title>
						<Group gap="xs">
							<FavoriteButton mediaId={item.id} type="video" />
							<AddToCollectionButton mediaId={item.id} type="video" />
						</Group>
					</Group>
					<VideoMeta item={item} />
					{item.description !== "" && <Text>{item.description}</Text>}
					{HTTP_URL_PATTERN.test(item.source_url) && (
						<Button
							component="a"
							href={item.source_url}
							target="_blank"
							rel="noopener noreferrer"
							variant="subtle"
							w="fit-content"
						>
							{t("metadata.sourceUrl")}
						</Button>
					)}
					<MediaAdminActions media={item} extractAudio backPath="/video" />
				</Stack>
			</TVFocusScope>
		</Stack>
	);
}
