import { Button, Card, Group, Stack, Text, Title } from "@mantine/core";
import { useTranslation } from "react-i18next";
import {
	useBackfillCovers,
	useBackfillThumbnails,
	useMaintenanceQuery,
} from "../../api/admin";

export function MediaMaintenanceCard() {
	const { t } = useTranslation();
	const info = useMaintenanceQuery();
	const thumbs = useBackfillThumbnails();
	const covers = useBackfillCovers();
	const state = info.data?.state;
	return (
		<Stack gap="sm">
			<Title order={2} size="h4">
				{t("admin.maintenance.title")}
			</Title>
			<Card withBorder padding="md" radius="md">
				<Stack gap="sm">
					<Text size="sm">
						{t("admin.maintenance.thumbnails")}:{" "}
						{info.data?.missing_thumbnails ?? "—"}
					</Text>
					<Text size="sm">
						{t("admin.maintenance.covers")}: {info.data?.missing_covers ?? "—"}
					</Text>
					{state?.running && (
						<Text size="sm" c="dimmed">
							{t("admin.maintenance.running", {
								kind: state.kind,
								generated: state.generated,
							})}
						</Text>
					)}
					{state?.last_error !== undefined && state.last_error !== "" && (
						<Text size="sm" c="red">
							{state.last_error}
						</Text>
					)}
					<Group>
						<Button
							loading={thumbs.isPending}
							disabled={state?.running === true}
							onClick={() => thumbs.mutate()}
						>
							{t("admin.maintenance.generateThumbnails")}
						</Button>
						<Button
							variant="light"
							loading={covers.isPending}
							disabled={state?.running === true}
							onClick={() => covers.mutate()}
						>
							{t("admin.maintenance.extractCovers")}
						</Button>
					</Group>
				</Stack>
			</Card>
		</Stack>
	);
}
