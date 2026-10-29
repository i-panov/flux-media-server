import { ActionIcon, Card } from "@mantine/core";
import { Link } from "@tanstack/react-router";
import { Image as ImageIcon, RotateCw } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useMediaReload } from "../../api/media";
import type { Media } from "../../core/media";

// Квадратная плитка галереи: подписи нет, название уходит в aria-label
// ссылки. Превью — серверный JPEG до 512 px, оригинал грузится только
// в просмотрщике.
export function MemeCard({ media }: { media: Media }) {
	const { t } = useTranslation();
	const reload = useMediaReload(media.id);
	const src =
		media.thumbnail_url === ""
			? `/api/media/${media.id}/stream`
			: media.thumbnail_url;
	return (
		<div className="relative">
			<Link
				to="/memes/$id"
				params={{ id: String(media.id) }}
				aria-label={media.title}
				className="block"
			>
				<Card withBorder padding={0} radius="md" className="overflow-hidden">
					<div className="aspect-square bg-[var(--mantine-color-default-hover)]">
						{reload.failed ? (
							<div
								aria-hidden="true"
								className="grid h-full w-full place-items-center"
							>
								<ImageIcon
									size={28}
									className="text-[var(--mantine-color-dimmed)]"
								/>
							</div>
						) : (
							// biome-ignore lint/a11y/noNoninteractiveElementInteractions: onError здесь — ошибка загрузки, а не интеракция.
							<img
								key={reload.nonce}
								src={src}
								alt=""
								loading="lazy"
								decoding="async"
								onError={reload.handleError}
								className="h-full w-full object-cover"
							/>
						)}
					</div>
				</Card>
			</Link>
			{reload.failed && (
				<ActionIcon
					variant="filled"
					size="lg"
					radius="xl"
					aria-label={t("common.retry")}
					className="absolute top-2 right-2"
					onClick={reload.retry}
				>
					<RotateCw size={18} />
				</ActionIcon>
			)}
		</div>
	);
}
