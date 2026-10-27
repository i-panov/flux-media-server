import { Badge, Card, Group, Stack, Text, Title } from "@mantine/core";
import { Info } from "lucide-react";
import { useTranslation } from "react-i18next";

export function AboutCard() {
	const { t } = useTranslation();

	return (
		<Card withBorder padding="lg" radius="md" h="100%">
			<Stack gap="md">
				<Group gap="xs">
					<Info size={18} />
					<Title order={3} size="h4">
						{t("home.about.title")}
					</Title>
				</Group>
				<Stack gap={4}>
					<Text size="sm" c="dimmed">
						{t("home.about.webVersion")}
					</Text>
					<Group gap="xs">
						<Text fw={600}>{__APP_VERSION__}</Text>
						<Badge variant="light" color="violet">
							PWA
						</Badge>
					</Group>
				</Stack>
				<Text size="sm" c="dimmed">
					{t("home.about.stack")}
				</Text>
			</Stack>
		</Card>
	);
}
