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
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import { useMedia, useMediaReload } from "../../api/media";
import type { Media } from "../../core/media";
import { AddToCollectionButton } from "../collections/AddToCollectionButton";
import { FavoriteButton } from "../favorites/FavoriteButton";
import { MediaAdminActions } from "../media/MediaAdminActions";
import { clickNode, TVFocusScope, useTVFocusable } from "../tv/tvFocus";
import { useTVMode } from "../tv/useTVMode";

// Просмотрщик мема: оригинал отдаётся стримом (превью — только для
// сетки), поэтому картинка грузится в исходном качестве.
function MemeImage({ item }: { item: Media }) {
	const { t } = useTranslation();
	const reload = useMediaReload(item.id);
	if (reload.failed) {
		return (
			<Alert color="red" variant="light" title={t("memes.loadError")}>
				<Button variant="light" size="xs" mt="xs" onClick={reload.retry}>
					{t("common.retry")}
				</Button>
			</Alert>
		);
	}
	return (
		// biome-ignore lint/a11y/noNoninteractiveElementInteractions: onError здесь — ошибка загрузки, а не интеракция.
		<img
			key={reload.nonce}
			src={`/api/media/${item.id}/stream`}
			alt={item.title}
			onError={reload.handleError}
			className="max-h-[75vh] w-auto max-w-full rounded-md object-contain"
		/>
	);
}

export function MemeDetailPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { id } = useParams({ from: "/memes/$id" });
	const mediaId = Number(id);
	const valid = Number.isInteger(mediaId) && mediaId > 0;
	// ТВ-режим: секция и кнопка назад — точки входа spatial-навигации.
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("meme-detail");
	const { targetRef: tvLoadingRef } = useTVFocusable<HTMLDivElement>(
		"meme-detail-loading",
	);
	const { targetRef: tvBackRef } = useTVFocusable<HTMLButtonElement>(
		"meme-detail-back",
		clickNode,
	);
	const { capabilities } = useTVMode();

	const media = useMedia(valid ? mediaId : 0, valid);

	const goBack = () => {
		void navigate({ to: "/memes" });
	};
	const backLabel = t("memes.back");

	if (!valid) {
		return (
			<Stack gap="md" ref={tvLoadingRef} tabIndex={tvMode ? -1 : undefined}>
				<Alert color="red" variant="light">
					{t("memes.notFound")}
				</Alert>
				<Button variant="light" w="fit-content" onClick={goBack}>
					{backLabel}
				</Button>
			</Stack>
		);
	}

	if (media.isPending) {
		return (
			<Stack
				ref={tvLoadingRef}
				tabIndex={tvMode ? -1 : undefined}
				gap="md"
				align="center"
			>
				<Skeleton height={320} width="100%" radius="md" />
				<Skeleton height={28} width="40%" radius="sm" />
			</Stack>
		);
	}

	if (media.isError || media.data === undefined) {
		const notFound =
			media.error instanceof ApiError && media.error.status === 404;
		return (
			<Stack
				ref={tvLoadingRef}
				tabIndex={tvMode ? -1 : undefined}
				gap="md"
				align="center"
			>
				<Alert
					color="red"
					variant="light"
					title={notFound ? t("memes.notFound") : t("memes.loadError")}
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
	const filename = item.filename === "" ? item.title : item.filename;

	return (
		<Stack
			gap="lg"
			align="center"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-page-root="true"
			data-tv-focus-key="meme-detail"
		>
			<TVFocusScope focusKey="meme-detail">
				<Group w="100%" justify="space-between">
					<Button
						variant="subtle"
						ref={tvBackRef}
						data-tv-focus-key="meme-detail-back"
						onClick={goBack}
					>
						{backLabel}
					</Button>
					<Group gap="xs">
						<FavoriteButton mediaId={item.id} type="image" />
						<AddToCollectionButton mediaId={item.id} type="image" />
						{capabilities.canDownload && (
							<Button
								component="a"
								variant="light"
								href={`/api/media/${item.id}/stream`}
								download={filename}
							>
								{t("memes.download")}
							</Button>
						)}
					</Group>
				</Group>
				<MemeImage item={item} />
				<Stack gap={4} align="center">
					<Title order={1} size="h2" ta="center">
						{item.title}
					</Title>
					{item.description !== "" && (
						<Text ta="center" c="dimmed">
							{item.description}
						</Text>
					)}
					<MediaAdminActions media={item} backPath="/memes" />
				</Stack>
			</TVFocusScope>
		</Stack>
	);
}
