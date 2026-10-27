import {
	Badge,
	Button,
	Card,
	Group,
	Loader,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { RefreshCw, Server } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useHealthQuery } from "../api/health";

export function HealthCard() {
	const { t } = useTranslation();
	const { data, isPending, isError, isFetching, refetch } = useHealthQuery();

	return (
		<Card withBorder padding="lg" radius="md" h="100%">
			<Stack gap="md" h="100%">
				<Group justify="space-between" align="flex-start">
					<Group gap="xs">
						<Server size={18} />
						<Title order={3} size="h4">
							{t("home.server.title")}
						</Title>
					</Group>
					{isPending ? (
						<Badge variant="light" color="gray">
							{t("common.loading")}
						</Badge>
					) : isError ? (
						<Badge variant="light" color="red">
							{t("home.server.offline")}
						</Badge>
					) : (
						<Badge variant="light" color="teal">
							{t("home.server.online")}
						</Badge>
					)}
				</Group>

				{isPending ? (
					<Group gap="xs">
						<Loader size="xs" />
						<Text size="sm" c="dimmed">
							{t("home.server.checking")}
						</Text>
					</Group>
				) : null}

				{isError ? (
					<Stack gap="sm">
						<Text size="sm" c="dimmed">
							{t("home.server.error")}
						</Text>
						<Button
							variant="light"
							size="xs"
							leftSection={<RefreshCw size={14} />}
							loading={isFetching}
							onClick={() => void refetch()}
							w="fit-content"
						>
							{t("common.retry")}
						</Button>
					</Stack>
				) : null}

				{data ? (
					<Stack gap={4}>
						<Text size="sm" c="dimmed">
							{t("home.server.backendVersion")}
						</Text>
						<Text fw={600}>{data.version}</Text>
						<Text size="sm" c="dimmed">
							{t("home.server.latency")}:{" "}
							{t("health.latencyValue", { value: data.latencyMs })}
						</Text>
					</Stack>
				) : null}
			</Stack>
		</Card>
	);
}
