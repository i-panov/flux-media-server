import {
	Alert,
	Badge,
	Button,
	Card,
	Group,
	SegmentedControl,
	Select,
	SimpleGrid,
	Stack,
	Switch,
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
import { clickNode, TVFocusScope, useTVFocusable } from "../tv/tvFocus";
import { useTVMode } from "../tv/useTVMode";
import { DevicesCard } from "./DevicesCard";

const languageNames: Record<SupportedLang, string> = {
	ru: "Русский",
	en: "English",
};

const THEME_ORDER = ["auto", "light", "dark"] as const;

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
	const { data, isError, isFetching, refetch } = useHealthQuery();
	const { data: session } = useSession();
	const { logout, isPending: logoutPending } = useLogout();
	const { tvMode, setTVMode, capabilities } = useTVMode();
	const currentLang = pickLang(i18n.language);
	// ТВ-режим: корень страницы — spatial-секция, карточки внутри —
	// контент секции.
	const { targetRef: tvRef, tvMode: tvSectionMode } =
		useTVFocusable<HTMLDivElement>("settings-page");
	// Select языка — единственный overlay в read-only ТВ, на нём проверяется
	// пультовый Назад: закрыть список, не уходя из настроек.
	const { targetRef: languageRef } = useTVFocusable<HTMLDivElement>(
		"settings-language",
		(node) => {
			// Обёртка, а не сам input: Mantine Select останавливает Enter
			// на readOnly-инпуте, и spatial-обработчик его не получает.
			const input = node?.querySelector<HTMLInputElement>('[role="combobox"]');
			input?.focus();
			input?.click();
		},
	);
	// Тема: у SegmentedControl нет одного ref на всю группу, поэтому
	// фокусируем обёртку, а Enter/влево-вправо переключают значение —
	// иначе пульт не мог бы изменить тему вообще.
	const cycleColorScheme = (delta: number) => {
		const index = THEME_ORDER.indexOf(colorScheme);
		const next =
			THEME_ORDER[(index + delta + THEME_ORDER.length) % THEME_ORDER.length];
		setColorScheme(next);
	};
	const { targetRef: themeRef } = useTVFocusable<HTMLDivElement>(
		"settings-theme",
		() => cycleColorScheme(1),
		(direction) => {
			if (direction === "left" || direction === "right") {
				cycleColorScheme(direction === "right" ? 1 : -1);
				return false;
			}
			return true;
		},
	);
	// Тумблер ТВ — обычный input: Enter повторяет click, Space работает
	// нативно. Без этого пульт не мог ни включить, ни выключить режим.
	const { targetRef: tvToggleRef } = useTVFocusable<HTMLInputElement>(
		"settings-tv-toggle",
		clickNode,
	);

	return (
		<Stack
			gap="lg"
			ref={tvRef}
			tabIndex={tvSectionMode ? -1 : undefined}
			data-tv-page-root="true"
			data-tv-focus-key="settings-page"
		>
			<TVFocusScope focusKey="settings-page">
				<Title order={1} size="h2">
					{t("settings.title")}
				</Title>

				<SimpleGrid cols={{ base: 1, md: 2 }} spacing="lg">
					<SettingsCard title={t("settings.appearance.title")}>
						<Stack gap={4}>
							<Text size="sm" c="dimmed">
								{t("settings.appearance.theme")}
							</Text>
							<div ref={themeRef} tabIndex={tvSectionMode ? -1 : undefined}>
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
							</div>
						</Stack>
						<Switch
							ref={tvToggleRef}
							label={t("settings.tv.label")}
							description={t("settings.tv.hint")}
							checked={tvMode}
							onChange={(event) => setTVMode(event.currentTarget.checked)}
						/>
					</SettingsCard>

					<SettingsCard title={t("settings.language.title")}>
						<div ref={languageRef} tabIndex={tvSectionMode ? -1 : undefined}>
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
						</div>
					</SettingsCard>

					<SettingsCard title={t("settings.account.title")}>
						<Stack gap="sm">
							<Group justify="space-between" wrap="nowrap">
								<Text size="sm" truncate>
									{session?.email ?? t("common.emptyFallback")}
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
							{capabilities.canManageTrash && (
								<Button
									component={Link}
									to="/trash"
									variant="light"
									leftSection={<Trash2 size={16} />}
									w="fit-content"
								>
									{t("settings.trash")}
								</Button>
							)}
						</Stack>
					</SettingsCard>

					<DevicesCard />

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
									{data?.version ?? t("common.emptyFallback")}
								</Text>
							</Group>
							{isError && (
								<Alert
									color="red"
									variant="light"
									title={t("settings.server.unreachable")}
								>
									{t("home.server.error")}
									<Button
										variant="light"
										size="xs"
										mt="xs"
										loading={isFetching}
										onClick={() => void refetch()}
									>
										{t("common.retry")}
									</Button>
								</Alert>
							)}
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
			</TVFocusScope>
		</Stack>
	);
}
