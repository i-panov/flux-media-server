import {
	ActionIcon,
	Card,
	Group,
	Progress,
	SimpleGrid,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { Link } from "@tanstack/react-router";
import { Film, Music, RotateCw } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useMediaReload } from "../../api/media";
import { type ContinueEntry, useContinueWatching } from "../../api/progress";
import { formatDuration } from "../../core/format";
import type { MediaKind } from "../../core/media";

function ContinueCard({
	entry,
	kind,
}: {
	entry: ContinueEntry;
	kind: MediaKind;
}) {
	const { t } = useTranslation();
	const media = entry.media;
	const reload = useMediaReload(media.id);
	// У видео превью — кадр, у аудио — обложка. Плейсхолдер общий:
	// пустой URL и окончательно битая картинка выглядят одинаково.
	const preview = kind === "video" ? media.thumbnail_url : media.cover_url;
	const hasPreview = preview !== "" && !reload.failed;
	const FallbackIcon = kind === "video" ? Film : Music;
	// Кадр видео — широкий, обложка аудио — квадратная.
	const previewSize = kind === "video" ? "h-16 w-24" : "h-16 w-16";
	// Длительность прогресса точнее карточки: она пишется плеером.
	const total = entry.duration > 0 ? entry.duration : media.duration;
	const percent = total > 0 ? Math.min(100, (entry.position / total) * 100) : 0;
	return (
		<div className="relative">
			<Link
				to={kind === "video" ? "/video/$id" : "/audio/$id"}
				params={{ id: String(media.id) }}
				className="no-underline [color:inherit]"
			>
				<Card withBorder padding="sm" radius="md">
					<Stack gap="xs">
						<Group gap="sm" wrap="nowrap">
							{hasPreview ? (
								// biome-ignore lint/a11y/noNoninteractiveElementInteractions: onError здесь — ошибка загрузки, а не интеракция.
								<img
									key={reload.nonce}
									src={preview}
									alt=""
									loading="lazy"
									onError={reload.handleError}
									className={`${previewSize} shrink-0 rounded object-cover`}
								/>
							) : (
								<div
									aria-hidden="true"
									className={`${previewSize} grid shrink-0 place-items-center rounded bg-[var(--mantine-color-default-hover)]`}
								>
									<FallbackIcon
										size={20}
										className="text-[var(--mantine-color-dimmed)]"
									/>
								</div>
							)}
							<Stack gap={2} className="min-w-0">
								<Text fw={600} size="sm" lineClamp={2}>
									{media.title}
								</Text>
								<Text size="xs" c="dimmed">
									{t("continue.remaining", {
										time: formatDuration(Math.max(total - entry.position, 0)),
									})}
								</Text>
							</Stack>
						</Group>
						<Progress
							value={percent}
							size="sm"
							radius="xl"
							aria-label={t("continue.progressLabel", {
								position: formatDuration(entry.position),
								duration: formatDuration(total),
							})}
						/>
					</Stack>
				</Card>
			</Link>
			{/* Retry — сосед ссылки: кнопка внутри <a> ломает content model.
			Лежит поверх превью, чтобы не наезжать на название. */}
			{reload.failed && (
				<ActionIcon
					variant="filled"
					size="sm"
					radius="xl"
					aria-label={t("common.retry")}
					className="absolute top-3 left-3"
					onClick={reload.retry}
				>
					<RotateCw size={14} />
				</ActionIcon>
			)}
		</div>
	);
}

// Блок «Продолжить просмотр/прослушивание»: последние начатые и
// недосмотренные записи нужного типа. Ошибку запроса не показываем — это
// вспомогательная секция, основной список должен работать и без неё.
export function ContinueWatching({
	kind,
	limit,
}: {
	kind: MediaKind;
	limit?: number;
}) {
	const { t } = useTranslation();
	const list = useContinueWatching(kind);
	const items = (list.data ?? []).slice(0, limit);
	if (items.length === 0) {
		return null;
	}
	return (
		<Stack gap="sm">
			<Title order={2} size="h3">
				{t(kind === "video" ? "continue.watching" : "continue.listening")}
			</Title>
			<SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="md">
				{items.map((entry) => (
					<ContinueCard key={entry.id} entry={entry} kind={kind} />
				))}
			</SimpleGrid>
		</Stack>
	);
}
