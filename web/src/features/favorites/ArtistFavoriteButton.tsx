import { ActionIcon } from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { Heart } from "lucide-react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import {
	useFavoriteArtistIds,
	useToggleArtistFavorite,
} from "../../api/favorites";

// Сердечко исполнителя: бэкенд-эндпоинты есть давно, UI не было
// ни в одном клиенте — веб первый.
export function ArtistFavoriteButton({
	artistId,
	artistName,
	size = 18,
}: {
	artistId: number;
	artistName: string;
	size?: number;
}) {
	const { t } = useTranslation();
	const ids = useFavoriteArtistIds();
	const toggle = useToggleArtistFavorite();
	const active = ids.data?.has(artistId) ?? false;
	const label = active ? t("favorites.remove") : t("favorites.add");
	return (
		<ActionIcon
			variant="subtle"
			color={active ? "red" : "gray"}
			radius="xl"
			size="sm"
			aria-label={`${label}: ${artistName}`}
			title={`${label}: ${artistName}`}
			loading={toggle.isPending}
			disabled={ids.isPending}
			onClick={() => {
				toggle.mutate(
					{ artistId, favorite: active },
					{
						onError: (error) => {
							notifications.show({
								color: "red",
								title: t("favorites.error"),
								message: error instanceof ApiError ? error.message : "",
							});
						},
					},
				);
			}}
		>
			<Heart size={size} fill={active ? "currentColor" : "none"} />
		</ActionIcon>
	);
}
