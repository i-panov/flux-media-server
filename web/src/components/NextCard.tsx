import { Card, Group, Stack, Text, ThemeIcon, Title } from "@mantine/core";
import { Clapperboard, Image as ImageIcon, Music } from "lucide-react";
import { useTranslation } from "react-i18next";

export function NextCard() {
	const { t } = useTranslation();
	const items = [
		{ icon: Clapperboard, label: t("media.video") },
		{ icon: Music, label: t("media.audio") },
		{ icon: ImageIcon, label: t("media.memes") },
	];

	return (
		<Card withBorder padding="lg" radius="md">
			<Stack gap="md">
				<Title order={3} size="h4">
					{t("home.next.title")}
				</Title>
				<Text size="sm" c="dimmed">
					{t("home.next.body")}
				</Text>
				<Group gap="lg">
					{items.map(({ icon: Icon, label }) => (
						<Group key={label} gap="xs">
							<ThemeIcon variant="light" size="md" radius="md">
								<Icon size={16} />
							</ThemeIcon>
							<Text size="sm">{label}</Text>
						</Group>
					))}
				</Group>
			</Stack>
		</Card>
	);
}
