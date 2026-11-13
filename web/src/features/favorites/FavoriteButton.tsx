import { notifications } from "@mantine/notifications";
import { Heart } from "lucide-react";
import { useId } from "react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import { useFavoriteIds, useToggleFavorite } from "../../api/favorites";
import type { MediaType } from "../../core/media";
import { TVActionIcon } from "../tv/tvFocus";

export function FavoriteButton({
	mediaId,
	type,
	className,
}: {
	mediaId: number;
	type: MediaType;
	className?: string;
}) {
	const { t } = useTranslation();
	const instanceKey = useId().replace(/:/g, "");
	const ids = useFavoriteIds(type);
	const toggle = useToggleFavorite(type);
	const active = ids.data?.has(mediaId) ?? false;
	const label = active ? t("favorites.remove") : t("favorites.add");
	return (
		<TVActionIcon
			focusKey={`favorite-${type}-${mediaId}-${instanceKey}`}
			secondary
			variant="filled"
			color={active ? "red" : "dark"}
			radius="xl"
			size="lg"
			aria-label={label}
			title={label}
			loading={toggle.isPending}
			disabled={ids.isPending}
			className={className}
			onClick={() => {
				toggle.mutate(
					{ mediaId, favorite: active },
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
			<Heart size={18} fill={active ? "currentColor" : "none"} />
		</TVActionIcon>
	);
}
