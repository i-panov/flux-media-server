import {
	Alert,
	Button,
	Container,
	MantineProvider,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { Notifications } from "@mantine/notifications";
import { type QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
	createRootRouteWithContext,
	Outlet,
	redirect,
	useNavigate,
	useRouter,
} from "@tanstack/react-router";
import { useEffect } from "react";
import { useTranslation } from "react-i18next";
import { sessionQueryOptions } from "../api/session";
import { AppLayout } from "../components/AppLayout";
import { AudioPlayerProvider } from "../features/player/AudioPlayerProvider";
import i18n, { pickLang } from "../i18n";
import { queryClient } from "../queryClient";
import { theme } from "../theme";

interface RouterContext {
	queryClient: QueryClient;
}

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

// Экран ошибки guard'а (сервер недоступен, 500, ...). Рендерится вместо
// RootDocument, поэтому со своим MantineProvider — провайдеры документа
// в этот момент уже размонтированы. Повтор — через router.invalidate():
// reset() границы лишь гасит флаг ошибки, а матч так и остался бы
// в статусе error с тем же исключением.
function RootError() {
	const { t } = useTranslation();
	const router = useRouter();

	const handleRetry = () => {
		void router.invalidate();
	};

	return (
		<MantineProvider theme={theme} defaultColorScheme="auto">
			<Container size="xs" py="xl">
				<Stack gap="md">
					<Alert color="red" variant="light" title={t("error.title")}>
						{t("home.server.error")}
					</Alert>
					<Button variant="light" onClick={handleRetry} w="fit-content">
						{t("error.retry")}
					</Button>
				</Stack>
			</Container>
		</MantineProvider>
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
				<AudioPlayerProvider>
					<Notifications position="top-right" limit={3} />
					<AppLayout>
						<Outlet />
					</AppLayout>
				</AudioPlayerProvider>
			</QueryClientProvider>
		</MantineProvider>
	);
}

export const Route = createRootRouteWithContext<RouterContext>()({
	beforeLoad: async ({ context, location }) => {
		const session = await context.queryClient.ensureQueryData({
			...sessionQueryOptions(),
			revalidateIfStale: true,
		});
		if (session === null && location.pathname !== "/login") {
			// TanStack Router управляет редиректами брошенными объектами,
			// а не Error: точечно гасим only-throw-error.
			// eslint-disable-next-line @typescript-eslint/only-throw-error
			throw redirect({ to: "/login" });
		}
	},
	component: RootDocument,
	errorComponent: RootError,
	notFoundComponent: NotFoundPage,
});
