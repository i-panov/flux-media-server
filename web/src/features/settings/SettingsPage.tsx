import {
	Badge,
	Button,
	Card,
	Group,
	SegmentedControl,
	Select,
	SimpleGrid,
	Stack,
	Text,
	Title,
	useMantineColorScheme,
} from "@mantine/core";
import { Link } from "@tanstack/react-router";
import { LogOut, Trash2 } from "lucide-react";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { useHealthQuery } from "../../api/health";
import { useSession } from "../../api/session";
import { pickLang, SUPPORTED_LANGS, type SupportedLang } from "../../i18n";
import { useLogout } from "../auth/useLogout";

const languageNames: Record<SupportedLang, string> = {
	ru: "Русский",
	en: "English",
};

function SettingsCard({
	title,
	children,
}: {
	title: string;
	children: ReactNode;
}) {
	return (
		<Card withBorder padding="lg" radius="md" h="100%">
			<Stack gap="md">
				<Title order={2} size="h4">
					{title}
				</Title>
				{children}
			</Stack>
		</Card>
	);
}

export function SettingsPage() {
	const { t, i18n } = useTranslation();
	const { colorScheme, setColorScheme } = useMantineColorScheme();
	const { data } = useHealthQuery();
	const { data: session } = useSession();
	const { logout, isPending: logoutPending } = useLogout();
	const currentLang = pickLang(i18n.language);

	return (
		<Stack gap="lg">
			<Title order={1} size="h2">
				{t("settings.title")}
			</Title>

			<SimpleGrid cols={{ base: 1, md: 2 }} spacing="lg">
				<SettingsCard title={t("settings.appearance.title")}>
					<Stack gap={4}>
						<Text size="sm" c="dimmed">
							{t("settings.appearance.theme")}
						</Text>
						<SegmentedControl
							value={colorScheme}
							onChange={(value) => setColorScheme(value)}
							data={[
								{ value: "auto", label: t("settings.appearance.auto") },
								{ value: "light", label: t("settings.appearance.light") },
								{ value: "dark", label: t("settings.appearance.dark") },
							]}
							fullWidth
							size="xs"
						/>
					</Stack>
				</SettingsCard>

				<SettingsCard title={t("settings.language.title")}>
					<Select
						label={t("settings.language.label")}
						value={currentLang}
						onChange={(value) => {
							if (value !== null) {
								void i18n.changeLanguage(value);
							}
						}}
						data={SUPPORTED_LANGS.map((value) => ({
							value,
							label: languageNames[value],
						}))}
						allowDeselect={false}
						w={{ base: "100%", sm: 280 }}
					/>
				</SettingsCard>

				<SettingsCard title={t("settings.account.title")}>
					<Stack gap="sm">
						<Group justify="space-between" wrap="nowrap">
							<Text size="sm" truncate>
								{session?.email ?? "—"}
							</Text>
							{session?.is_admin === true && (
								<Badge variant="light" color="violet">
									{t("settings.account.admin")}
								</Badge>
							)}
						</Group>
						<Button
							variant="light"
							color="red"
							leftSection={<LogOut size={16} />}
							loading={logoutPending}
							onClick={logout}
							w="fit-content"
						>
							{t("settings.account.logout")}
						</Button>
						<Button
							component={Link}
							to="/trash"
							variant="light"
							leftSection={<Trash2 size={16} />}
							w="fit-content"
						>
							{t("settings.trash")}
						</Button>
					</Stack>
				</SettingsCard>

				<SettingsCard title={t("settings.server.title")}>
					<Stack gap="xs">
						<Group justify="space-between" wrap="nowrap">
							<Text size="sm" c="dimmed">
								{t("settings.server.origin")}
							</Text>
							<Text size="sm" fw={600} ta="right" truncate>
								{window.location.origin}
							</Text>
						</Group>
						<Group justify="space-between">
							<Text size="sm" c="dimmed">
								{t("settings.about.backendVersion")}
							</Text>
							<Text size="sm" fw={600}>
								{data?.version ?? "—"}
							</Text>
						</Group>
					</Stack>
				</SettingsCard>
			</SimpleGrid>

			<SettingsCard title={t("settings.about.title")}>
				<Stack gap="xs">
					<Group justify="space-between">
						<Text size="sm" c="dimmed">
							{t("settings.about.webVersion")}
						</Text>
						<Text size="sm" fw={600}>
							{__APP_VERSION__}
						</Text>
					</Group>
					<Group justify="space-between">
						<Text size="sm" c="dimmed">
							{t("settings.about.stack")}
						</Text>
						<Text size="sm" fw={600} ta="right">
							{t("settings.about.stackValue")}
						</Text>
					</Group>
				</Stack>
			</SettingsCard>
		</Stack>
	);
}
