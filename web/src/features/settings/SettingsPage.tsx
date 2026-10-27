import {
	Card,
	Group,
	SegmentedControl,
	Select,
	Stack,
	Text,
	Title,
	useMantineColorScheme,
} from "@mantine/core";
import { useTranslation } from "react-i18next";
import { useHealthQuery } from "../../api/health";
import { pickLang, SUPPORTED_LANGS, type SupportedLang } from "../../i18n";

const languageNames: Record<SupportedLang, string> = {
	ru: "Русский",
	en: "English",
};

export function SettingsPage() {
	const { t, i18n } = useTranslation();
	const { colorScheme, setColorScheme } = useMantineColorScheme();
	const { data } = useHealthQuery();
	const currentLang = pickLang(i18n.language);

	return (
		<Stack gap="lg">
			<Title order={1} size="h2">
				{t("settings.title")}
			</Title>

			<Card withBorder padding="lg" radius="md">
				<Stack gap="md">
					<Title order={2} size="h4">
						{t("settings.appearance.title")}
					</Title>
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
							w="fit-content"
						/>
					</Stack>
				</Stack>
			</Card>

			<Card withBorder padding="lg" radius="md">
				<Stack gap="md">
					<Title order={2} size="h4">
						{t("settings.language.title")}
					</Title>
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
				</Stack>
			</Card>

			<Card withBorder padding="lg" radius="md">
				<Stack gap="md">
					<Title order={2} size="h4">
						{t("settings.about.title")}
					</Title>
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
								{t("settings.about.backendVersion")}
							</Text>
							<Text size="sm" fw={600}>
								{data?.version ?? "—"}
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
				</Stack>
			</Card>
		</Stack>
	);
}
