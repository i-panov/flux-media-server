import { Button, MantineProvider, Stack, Text, Title } from "@mantine/core";
import { Notifications } from "@mantine/notifications";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createRootRoute, Outlet, useNavigate } from "@tanstack/react-router";
import { useEffect } from "react";
import { useTranslation } from "react-i18next";
import { AppLayout } from "../components/AppLayout";
import i18n, { pickLang } from "../i18n";
import { theme } from "../theme";

const queryClient = new QueryClient({
	defaultOptions: {
		queries: {
			staleTime: 30_000,
			retry: 0,
		},
	},
});

function NotFoundPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();

	return (
		<Stack align="center" gap="md" py="xl">
			<Title order={1}>404</Title>
			<Text c="dimmed">{t("common.notFound")}</Text>
			<Button variant="light" onClick={() => void navigate({ to: "/" })}>
				{t("common.backHome")}
			</Button>
		</Stack>
	);
}

function RootDocument() {
	useEffect(() => {
		const updateLang = () => {
			document.documentElement.lang = pickLang(i18n.language);
		};
		updateLang();
		i18n.on("languageChanged", updateLang);
		return () => {
			i18n.off("languageChanged", updateLang);
		};
	}, []);

	return (
		<MantineProvider theme={theme} defaultColorScheme="auto">
			<QueryClientProvider client={queryClient}>
				<Notifications position="top-right" limit={3} />
				<AppLayout>
					<Outlet />
				</AppLayout>
			</QueryClientProvider>
		</MantineProvider>
	);
}

export const Route = createRootRoute({
	component: RootDocument,
	notFoundComponent: NotFoundPage,
});
