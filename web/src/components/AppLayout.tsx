import {
	ActionIcon,
	AppShell,
	Container,
	Group,
	Text,
	Tooltip,
	useComputedColorScheme,
	useMantineColorScheme,
} from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { Link, useNavigate } from "@tanstack/react-router";
import { LogOut, Moon, Play, Sun } from "lucide-react";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../api/client";
import {
	clearSessionData,
	useLogoutMutation,
	useSession,
} from "../api/session";

const inactiveLink =
	"rounded-md px-3 py-1.5 text-sm font-medium text-[var(--mantine-color-dimmed)] transition-colors hover:bg-[var(--mantine-color-default-hover)] hover:text-[var(--mantine-color-text)]";
const activeLink =
	"rounded-md px-3 py-1.5 text-sm font-medium text-[var(--mantine-color-text)] bg-[var(--mantine-color-default-hover)]";

function NavItem({
	to,
	label,
	exact = true,
}: {
	to: "/" | "/video" | "/audio" | "/settings";
	label: string;
	exact?: boolean;
}) {
	return (
		<Link
			to={to}
			className={inactiveLink}
			activeProps={{ className: activeLink }}
			activeOptions={{ exact }}
		>
			{label}
		</Link>
	);
}

export function AppLayout({ children }: { children: ReactNode }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { setColorScheme } = useMantineColorScheme();
	const computed = useComputedColorScheme("dark", {
		getInitialValueInEffect: true,
	});
	const isDark = computed === "dark";
	const { data: session } = useSession();
	const logoutMutation = useLogoutMutation();

	const handleLogout = () => {
		logoutMutation.mutate(undefined, {
			onSuccess: () => {
				void navigate({ to: "/login" });
			},
			onError: (error) => {
				if (error instanceof ApiError && error.status === 401) {
					// Серверная сессия уже недействительна — выходим локально.
					clearSessionData();
					void navigate({ to: "/login" });
					return;
				}
				notifications.show({
					color: "red",
					title: t("auth.logoutFailed"),
					message:
						error instanceof ApiError && error.message.length > 0
							? error.message
							: t("auth.genericError"),
				});
			},
		});
	};

	return (
		<AppShell header={{ height: 60 }} padding="md">
			<AppShell.Header className="border-b border-[var(--mantine-color-default-border)] bg-[var(--mantine-color-body)]">
				<Container size="lg" h="100%">
					<Group h="100%" justify="space-between">
						<Group gap="xs">
							<div className="flux-brand-gradient grid h-8 w-8 place-items-center rounded-lg text-white">
								<Play size={16} fill="currentColor" />
							</div>
							<Text fw={700} size="lg">
								Flux
							</Text>
						</Group>

						<Group gap={4}>
							{session != null && (
								<>
									<NavItem to="/" label={t("nav.home")} />
									<NavItem to="/video" label={t("nav.video")} exact={false} />
									<NavItem to="/audio" label={t("nav.audio")} exact={false} />
									<NavItem to="/settings" label={t("nav.settings")} />
								</>
							)}
							{session != null && (
								<Group gap="xs">
									<Text size="sm" c="dimmed" maw={160} truncate="end">
										{session.email}
									</Text>
									<Tooltip label={t("auth.logout")} withArrow>
										<ActionIcon
											variant="default"
											size="lg"
											aria-label={t("auth.logout")}
											loading={logoutMutation.isPending}
											onClick={handleLogout}
										>
											<LogOut size={18} />
										</ActionIcon>
									</Tooltip>
								</Group>
							)}
							<Tooltip label={t("theme.toggle")} withArrow>
								<ActionIcon
									variant="default"
									size="lg"
									aria-label={t("theme.toggle")}
									onClick={() => setColorScheme(isDark ? "light" : "dark")}
								>
									{isDark ? <Sun size={18} /> : <Moon size={18} />}
								</ActionIcon>
							</Tooltip>
						</Group>
					</Group>
				</Container>
			</AppShell.Header>

			<AppShell.Main>
				<Container size="lg" py="xl">
					{children}
				</Container>
			</AppShell.Main>
		</AppShell>
	);
}
