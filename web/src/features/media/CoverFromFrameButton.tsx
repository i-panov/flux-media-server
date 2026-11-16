import { Button } from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { Image as ImageIcon } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useCoverFromFrame } from "../../api/media";

export function CoverFromFrameButton({ mediaId }: { mediaId: number }) {
	const { t } = useTranslation();
	const generate = useCoverFromFrame();
	return (
		<Button
			variant="light"
			leftSection={<ImageIcon size={16} />}
			loading={generate.isPending}
			onClick={() => {
				if (!window.confirm(t("metadata.coverFromFrameConfirm"))) return;
				generate.mutate(mediaId, {
					onSuccess: () =>
						notifications.show({
							message: t("metadata.coverFromFrameDone"),
							color: "green",
						}),
					onError: () =>
						notifications.show({
							message: t("metadata.coverFromFrameError"),
							color: "red",
						}),
				});
			}}
		>
			{t("metadata.coverFromFrame")}
		</Button>
	);
}
