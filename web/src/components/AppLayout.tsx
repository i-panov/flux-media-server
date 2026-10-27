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
import { Link } from "@tanstack/react-router";
import { Moon, Play, Sun } from "lucide-react";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";

const inactiveLink =
	"rounded-md px-3 py-1.5 text-sm font-medium text-[var(--mantine-color-dimmed)] transition-colors hover:bg-[var(--mantine-color-default-hover)] hover:text-[var(--mantine-color-text)]";
const activeLink =
	"rounded-md px-3 py-1.5 text-sm font-medium text-[var(--mantine-color-text)] bg-[var(--mantine-color-default-hover)]";

function NavItem({ to, label }: { to: "/" | "/settings"; label: string }) {
	return (
		<Link
			to={to}
			className={inactiveLink}
			activeProps={{ className: activeLink }}
			activeOptions={{ exact: true }}
		>
			{label}
		</Link>
	);
}

export function AppLayout({ children }: { children: ReactNode }) {
	const { t } = useTranslation();
	const { setColorScheme } = useMantineColorScheme();
	const computed = useComputedColorScheme("dark", {
		getInitialValueInEffect: true,
	});
	const isDark = computed === "dark";

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
							<NavItem to="/" label={t("nav.home")} />
							<NavItem to="/settings" label={t("nav.settings")} />
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
