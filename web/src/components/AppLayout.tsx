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
import {
	Film,
	Home,
	Image as ImageIcon,
	LogOut,
	Moon,
	Music,
	Play,
	Settings,
	Sun,
} from "lucide-react";
import type { ComponentType, ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { useSession } from "../api/session";
import { useLogout } from "../features/auth/useLogout";
import { AudioMiniPlayer } from "../features/player/AudioMiniPlayer";
import { useMiniPlayerVisible } from "../features/player/useMiniPlayerVisible";

type NavTo = "/" | "/video" | "/audio" | "/memes" | "/settings";

interface NavItemConfig {
	to: NavTo;
	labelKey: string;
	icon: ComponentType<{ size?: number; className?: string }>;
	exact?: boolean;
}

const MAIN_NAV: NavItemConfig[] = [
	{ to: "/", labelKey: "nav.home", icon: Home, exact: true },
	{ to: "/video", labelKey: "nav.video", icon: Film, exact: false },
	{ to: "/audio", labelKey: "nav.audio", icon: Music, exact: false },
	{ to: "/memes", labelKey: "nav.memes", icon: ImageIcon, exact: false },
];

const SETTINGS_NAV: NavItemConfig = {
	to: "/settings",
	labelKey: "nav.settings",
	icon: Settings,
};

const desktopNavClass =
	"flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium text-[var(--mantine-color-dimmed)] transition-colors hover:bg-[var(--mantine-color-default-hover)] hover:text-[var(--mantine-color-text)]";
const desktopNavActiveClass =
	"bg-[var(--mantine-color-default-hover)] text-[var(--mantine-color-text)]";

function DesktopNavItem({ item }: { item: NavItemConfig }) {
	const { t } = useTranslation();
	const Icon = item.icon;
	return (
		<Link
			to={item.to}
			className={desktopNavClass}
			activeProps={{ className: desktopNavActiveClass }}
			activeOptions={{ exact: item.exact ?? true }}
		>
			<Icon size={18} />
			<span>{t(item.labelKey)}</span>
		</Link>
	);
}

function MobileNavItem({ item }: { item: NavItemConfig }) {
	const { t } = useTranslation();
	const Icon = item.icon;
	return (
		<Link
			to={item.to}
			className="flex flex-1 flex-col items-center justify-center gap-0.5 py-1 text-[11px] font-medium text-[var(--mantine-color-dimmed)]"
			activeProps={{
				className: "text-[var(--mantine-color-violet-5)]",
			}}
			activeOptions={{ exact: item.exact ?? true }}
		>
			<Icon size={20} />
			<span>{t(item.labelKey)}</span>
		</Link>
	);
}

function Brand() {
	return (
		<Link
			to="/"
			className="flex items-center gap-2 no-underline [color:inherit]"
		>
			<div className="flux-brand-gradient grid h-8 w-8 place-items-center rounded-lg text-white">
				<Play size={16} fill="currentColor" />
			</div>
			<Text fw={700} size="lg">
				Flux
			</Text>
		</Link>
	);
}

function ThemeToggle() {
	const { t } = useTranslation();
	const { setColorScheme } = useMantineColorScheme();
	const computed = useComputedColorScheme("dark", {
		getInitialValueInEffect: true,
	});
	const isDark = computed === "dark";
	return (
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
	);
}

export function AppLayout({ children }: { children: ReactNode }) {
	const { t } = useTranslation();
	const { data: session } = useSession();
	const { logout, isPending: logoutPending } = useLogout();
	const miniPlayerVisible = useMiniPlayerVisible();

	const logoutButton = (
		<Tooltip label={t("auth.logout")} withArrow>
			<ActionIcon
				variant="default"
				size="lg"
				aria-label={t("auth.logout")}
				loading={logoutPending}
				onClick={logout}
			>
				<LogOut size={18} />
			</ActionIcon>
		</Tooltip>
	);

	const authed = session != null;
	// Конфиг навбара задаёт отступ Main даже когда самой панели нет:
	// на /login без сессии 240 px слева сдвигали карточку входа.
	const navbar = authed
		? {
				width: { base: 240, xl: 280 },
				breakpoint: "md" as const,
				collapsed: { mobile: true },
			}
		: undefined;
	const footer = authed ? { height: 64, offset: false } : undefined;

	return (
		<AppShell
			header={{ height: { base: 56, md: 64 } }}
			navbar={navbar}
			footer={footer}
			padding="md"
		>
			<AppShell.Header className="border-b border-[var(--mantine-color-default-border)] bg-[var(--mantine-color-body)]">
				<Container fluid px={{ base: "md", md: "lg", xl: "xl" }} h="100%">
					<Group h="100%" justify="space-between" wrap="nowrap">
						<Brand />
						<Group gap="xs" wrap="nowrap">
							{session != null && (
								<Text
									size="sm"
									c="dimmed"
									maw={220}
									truncate="end"
									visibleFrom="sm"
								>
									{session.email}
								</Text>
							)}
							<ThemeToggle />
							{session != null && logoutButton}
						</Group>
					</Group>
				</Container>
			</AppShell.Header>

			{session != null && (
				<AppShell.Navbar
					p="md"
					visibleFrom="md"
					className="border-r border-[var(--mantine-color-default-border)] bg-[var(--mantine-color-body)]"
				>
					<AppShell.Section grow>
						<nav className="flex flex-col gap-1" aria-label={t("nav.main")}>
							{MAIN_NAV.map((item) => (
								<DesktopNavItem key={item.to} item={item} />
							))}
						</nav>
					</AppShell.Section>
					<AppShell.Section>
						<DesktopNavItem item={SETTINGS_NAV} />
					</AppShell.Section>
				</AppShell.Navbar>
			)}

			<AppShell.Main
				className={[
					authed ? "app-shell-main-mobile" : "",
					miniPlayerVisible ? "app-shell-main-player" : "",
				]
					.filter(Boolean)
					.join(" ")}
			>
				<Container
					size="xl"
					maw={1600}
					px={{ base: "md", sm: "lg", xl: "xl" }}
					py={{ base: "md", md: "lg", xl: "xl" }}
				>
					{children}
				</Container>
			</AppShell.Main>

			{session != null && (
				<AppShell.Footer
					hiddenFrom="md"
					className="border-t border-[var(--mantine-color-default-border)] bg-[var(--mantine-color-body)]"
				>
					<Group h="100%" gap={0} wrap="nowrap">
						<nav className="flex h-full w-full" aria-label={t("nav.mobile")}>
							{[...MAIN_NAV, SETTINGS_NAV].map((item) => (
								<MobileNavItem key={item.to} item={item} />
							))}
						</nav>
					</Group>
				</AppShell.Footer>
			)}

			<AudioMiniPlayer />
		</AppShell>
	);
}
