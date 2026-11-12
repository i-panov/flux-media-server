import { Badge, Button, Card, Group, Stack, Text, Title } from "@mantine/core";
import { useTranslation } from "react-i18next";
import { useDevicesQuery, useRevokeDeviceMutation } from "../../api/session";

export function DevicesCard() {
	const { t } = useTranslation();
	const devices = useDevicesQuery();
	const revoke = useRevokeDeviceMutation();

	return (
		<Card withBorder padding="lg" radius="md" h="100%">
			<Stack gap="md">
				<Title order={2} size="h4">
					{t("devices.title")}
				</Title>
				<Text size="sm" c="dimmed">
					{t("devices.hint")}
				</Text>
				{devices.isPending && <Text size="sm">{t("common.loading")}</Text>}
				{devices.data?.length === 0 && (
					<Text size="sm" c="dimmed">
						{t("devices.empty")}
					</Text>
				)}
				{devices.data?.map((device) => (
					<Group key={device.id} justify="space-between" wrap="nowrap">
						<Stack gap={0}>
							<Group gap="xs">
								<Text size="sm" fw={600}>
									{device.device_name}
								</Text>
								<Badge size="xs" variant="light">
									{device.platform}
								</Badge>
							</Group>
							<Text size="xs" c="dimmed">
								{device.last_used_at ?? device.created_at}
							</Text>
						</Stack>
						<Button
							variant="subtle"
							color="red"
							size="xs"
							loading={revoke.isPending && revoke.variables === device.id}
							onClick={() => {
								if (window.confirm(t("devices.confirm"))) {
									revoke.mutate(device.id);
								}
							}}
						>
							{t("devices.revoke")}
						</Button>
					</Group>
				))}
			</Stack>
		</Card>
	);
}
