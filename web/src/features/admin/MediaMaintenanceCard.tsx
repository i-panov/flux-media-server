import { Button, Card, Group, Stack, Text, Title } from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { useEffect, useRef } from "react";
import { useTranslation } from "react-i18next";
import {
	useBackfillCovers,
	useBackfillThumbnails,
	useMaintenanceQuery,
} from "../../api/admin";
import { ApiError } from "../../api/client";

export function MediaMaintenanceCard() {
	const { t } = useTranslation();
	const info = useMaintenanceQuery();
	const thumbs = useBackfillThumbnails();
	const covers = useBackfillCovers();
	const state = info.data?.state;
	const wasRunning = useRef(false);

	// Проход может завершиться за миллисекунды (нет файлов/ffmpeg), поэтому
	// без уведомления кнопка выглядит «мёртвой».
	useEffect(() => {
		if (state?.running === true) {
			wasRunning.current = true;
			return;
		}
		if (wasRunning.current && state !== undefined) {
			wasRunning.current = false;
			notifications.show({
				message: t("admin.maintenance.finished", {
					generated: state.generated,
					failed: state.failed,
				}),
				color: state.failed > 0 ? "orange" : "green",
			});
		}
	}, [state, t]);

	const notifyError = (error: unknown) => {
		notifications.show({
			message:
				error instanceof ApiError
					? error.message
					: t("admin.maintenance.failed"),
			color: "red",
		});
	};

	const start = (kind: "thumbnails" | "covers") => {
		const mutation = kind === "thumbnails" ? thumbs : covers;
		mutation.mutate(undefined, {
			onSuccess: () =>
				notifications.show({
					message: t("admin.maintenance.started"),
					color: "blue",
				}),
			onError: notifyError,
		});
	};

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
					{state?.running === true && (
						<Text size="sm" c="dimmed">
							{t("admin.maintenance.running", {
								kind: state.kind,
								generated: state.generated,
							})}
						</Text>
					)}
					{state !== undefined &&
						state.running !== true &&
						state.kind !== undefined &&
						state.kind !== "" && (
							<Text size="sm" c="dimmed">
								{t("admin.maintenance.lastRun", {
									kind: state.kind,
									generated: state.generated,
									failed: state.failed,
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
							onClick={() => start("thumbnails")}
						>
							{t("admin.maintenance.generateThumbnails")}
						</Button>
						<Button
							variant="light"
							loading={covers.isPending}
							disabled={state?.running === true}
							onClick={() => start("covers")}
						>
							{t("admin.maintenance.extractCovers")}
						</Button>
					</Group>
				</Stack>
			</Card>
		</Stack>
	);
}
