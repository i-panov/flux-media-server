import { Chip, Group, Stack, Title } from "@mantine/core";
import { Heart } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useFavoriteArtistIds } from "../../api/favorites";
import { useMediaArtists } from "../../api/metadata";
import { ArtistFavoriteButton } from "./ArtistFavoriteButton";

// Избранные исполнители: имён в избранном нет (только id), поэтому
// подтягиваем названия из справочника артистов. Клик по чипу ищет
// треки исполнителя — поиск умеет по артистам.
export function FavoriteArtistsSection({
	onSelect,
}: {
	onSelect: (name: string) => void;
}) {
	const { t } = useTranslation();
	const favIds = useFavoriteArtistIds();
	const artists = useMediaArtists();

	const names = new Map(
		(artists.data ?? []).map((artist) => [artist.id, artist.name] as const),
	);
	const favorite = [...(favIds.data ?? [])]
		.map((id) => ({ id, name: names.get(id) ?? "" }))
		.filter((artist) => artist.name !== "")
		.sort((a, b) => a.name.localeCompare(b.name));

	if (favorite.length === 0) {
		return null;
	}

	return (
		<Stack gap="sm">
			<Group gap="xs">
				<Heart size={18} className="text-red-500" fill="currentColor" />
				<Title order={2} size="h3">
					{t("favorites.artists")}
				</Title>
			</Group>
			<Group gap="xs">
				{favorite.map((artist) => (
					<Group key={artist.id} gap={2} wrap="nowrap">
						<Chip variant="light" onClick={() => onSelect(artist.name)}>
							{artist.name}
						</Chip>
						<ArtistFavoriteButton
							artistId={artist.id}
							artistName={artist.name}
							size={13}
						/>
					</Group>
				))}
			</Group>
		</Stack>
	);
}
