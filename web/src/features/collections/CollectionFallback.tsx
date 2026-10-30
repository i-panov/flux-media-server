import { Alert, Button, Stack } from "@mantine/core";
import { useNavigate } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { BACK_LABEL_KEY } from "./collectionUtils";

export function CollectionFallback({
	title,
	onRetry,
	backPath = "/video",
}: {
	title: string;
	onRetry?: () => void;
	backPath?: "/video" | "/audio" | "/memes";
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	return (
		<Stack gap="md">
			<Alert color="red" variant="light" title={title}>
				{onRetry !== undefined && (
					<Button variant="light" size="xs" mt="xs" onClick={onRetry}>
						{t("common.retry")}
					</Button>
				)}
			</Alert>
			<Button
				variant="light"
				w="fit-content"
				onClick={() => void navigate({ to: backPath })}
			>
				{t(BACK_LABEL_KEY)}
			</Button>
		</Stack>
	);
}
