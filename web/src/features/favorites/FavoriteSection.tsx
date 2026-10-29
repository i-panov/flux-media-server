import { Group, SimpleGrid, Stack, Title } from "@mantine/core";
import { Heart } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useFavoriteMedia } from "../../api/favorites";
import type { Media, MediaType } from "../../core/media";
import { AudioCard } from "../audio/AudioCard";
import { MemeCard } from "../memes/MemeCard";
import { VideoCard } from "../video/VideoCard";

function FavoriteCard({ media, type }: { media: Media; type: MediaType }) {
	if (type === "video") {
		return <VideoCard media={media} />;
	}
	if (type === "audio") {
		return <AudioCard media={media} />;
	}
	return <MemeCard media={media} />;
}

export function FavoriteSection({ type }: { type: MediaType }) {
	const { t } = useTranslation();
	const items = useFavoriteMedia(type);
	if (items.length === 0) {
		return null;
	}
	return (
		<Stack gap="sm">
			<Group gap="xs">
				<Heart size={18} className="text-red-500" fill="currentColor" />
				<Title order={2} size="h3">
					{t("favorites.title")}
				</Title>
			</Group>
			<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5, xl: 6 }} spacing="md">
				{items.map((media) => (
					<FavoriteCard key={media.id} media={media} type={type} />
				))}
			</SimpleGrid>
		</Stack>
	);
}
