import { getApiConfig, useHealthQuery } from "@flux/shared";
import { useQueryClient } from "@tanstack/react-query";
import { Link, router } from "expo-router";
import {
	Pressable,
	type StyleProp,
	StyleSheet,
	Text,
	View,
	type ViewStyle,
} from "react-native";
import { version as appVersion } from "../../package.json";
import { signOutLocal } from "../../src/auth/logout";
import { useSession } from "../../src/auth/session";
import { Screen } from "../../src/components/Screen";
import { setLanguage, t, useLanguage } from "../../src/i18n";
import { useTheme } from "../../src/theme/ThemeProvider";
import { THEME_MODES, type ThemeMode } from "../../src/theme/tokens";

// Текстовые ключи для трёх режимов: THEME_MODES — единственный список
// допустимых значений, поэтому UI и типы не расходятся.
const THEME_LABELS: Record<
	ThemeMode,
	"settings.themeSystem" | "settings.themeLight" | "settings.themeDark"
> = {
	system: "settings.themeSystem",
	light: "settings.themeLight",
	dark: "settings.themeDark",
};

function SettingsButton({
	title,
	onPress,
	selected = false,
	danger = false,
	testID,
	style,
}: {
	title: string;
	onPress: () => void;
	selected?: boolean;
	danger?: boolean;
	testID?: string;
	style?: StyleProp<ViewStyle>;
}) {
	const { colors, radii, spacing } = useTheme();
	const borderColor = danger
		? colors.danger
		: selected
			? colors.accent
			: colors.borderStrong;
	const textColor = selected
		? colors.onAccent
		: danger
			? colors.danger
			: colors.text;
	return (
		<Pressable
			testID={testID}
			accessibilityRole="button"
			accessibilityLabel={title}
			accessibilityState={{ selected }}
			onPress={onPress}
			style={({ pressed }) => [
				styles.actionButton,
				{
					borderColor,
					backgroundColor: selected ? colors.accent : colors.surfaceMuted,
					borderRadius: radii.sm,
					paddingHorizontal: spacing.md,
					paddingVertical: spacing.sm,
				},
				pressed && styles.pressed,
				style,
			]}
		>
			<Text style={[styles.actionLabel, { color: textColor }]}>{title}</Text>
		</Pressable>
	);
}

export default function SettingsScreen() {
	const health = useHealthQuery();
	const session = useSession();
	const language = useLanguage();
	const { colors, mode, persistedMode, radii, setMode, spacing } = useTheme();
	const queryClient = useQueryClient();

	let backendStatus: string;
	if (health.isPending) {
		backendStatus = t("common.loading");
	} else if (health.isError) {
		backendStatus = t("home.offline");
	} else {
		backendStatus = `${health.data.status} · ${health.data.version}`;
	}

	const themeOptions = THEME_MODES.map((value) => ({
		value,
		label: t(THEME_LABELS[value]),
		testID: `settings-theme-${value}`,
	}));

	const signOut = async () => {
		await signOutLocal(queryClient);
		router.replace("/login");
	};

	return (
		<Screen scroll testID="settings-screen">
			<Text style={[styles.title, { color: colors.text }]}>
				{t("settings.title")}
			</Text>
			{session.data?.email !== undefined && (
				<Text style={[styles.muted, { color: colors.textMuted }]}>
					{session.data.email}
				</Text>
			)}

			<View
				style={[
					styles.card,
					{ borderColor: colors.borderStrong, backgroundColor: colors.surface },
				]}
			>
				<Text style={[styles.cardTitle, { color: colors.text }]}>
					{t("home.server")}
				</Text>
				<Text style={[styles.muted, { color: colors.textMuted }]}>
					{backendStatus}
				</Text>
				<Text
					style={[styles.muted, { color: colors.textMuted }]}
					numberOfLines={1}
				>
					{getApiConfig().baseUrl}
				</Text>
				<Link href="/server" asChild>
					<Pressable
						testID="settings-open-server"
						accessibilityRole="button"
						hitSlop={8}
						style={styles.linkButton}
					>
						<Text style={[styles.link, { color: colors.accent }]}>
							{t("server.open")}
						</Text>
					</Pressable>
				</Link>
			</View>

			<View
				style={[
					styles.card,
					{ borderColor: colors.borderStrong, backgroundColor: colors.surface },
				]}
			>
				<Text style={[styles.cardTitle, { color: colors.text }]}>
					{t("settings.version")}
				</Text>
				<Text style={[styles.muted, { color: colors.textMuted }]}>
					{appVersion}
				</Text>
			</View>

			<View
				style={[
					styles.card,
					{ borderColor: colors.borderStrong, backgroundColor: colors.surface },
				]}
			>
				<Text style={[styles.cardTitle, { color: colors.text }]}>
					{t("settings.language")}
				</Text>
				<View style={{ flexDirection: "row", gap: spacing.sm }}>
					<SettingsButton
						title="Русский"
						onPress={() => setLanguage("ru")}
						selected={language === "ru"}
						testID="settings-language-ru"
						style={styles.languageButton}
					/>
					<SettingsButton
						title="English"
						onPress={() => setLanguage("en")}
						selected={language === "en"}
						testID="settings-language-en"
						style={styles.languageButton}
					/>
				</View>
			</View>

			<View
				style={[
					styles.card,
					{ borderColor: colors.borderStrong, backgroundColor: colors.surface },
				]}
			>
				<Text style={[styles.cardTitle, { color: colors.text }]}>
					{t("settings.theme")}
				</Text>
				<View style={{ flexDirection: "row", gap: spacing.sm, marginTop: 2 }}>
					{themeOptions.map((option) => {
						const selected = mode === option.value;
						return (
							<Pressable
								key={option.value}
								testID={option.testID}
								accessibilityRole="button"
								accessibilityLabel={option.label}
								accessibilityState={{ selected }}
								onPress={() => setMode(option.value)}
								style={({ pressed }) => [
									styles.segment,
									{
										borderColor: selected ? colors.accent : colors.borderStrong,
										backgroundColor: selected
											? colors.accent
											: colors.surfaceMuted,
										borderRadius: radii.sm,
										paddingHorizontal: spacing.xs,
										paddingVertical: spacing.sm,
									},
									pressed && styles.pressed,
								]}
							>
								<Text
									style={[
										styles.segmentLabel,
										{ color: selected ? colors.onAccent : colors.text },
									]}
								>
									{option.label}
								</Text>
							</Pressable>
						);
					})}
				</View>
				<View style={styles.persistedRow}>
					<Text style={[styles.muted, { color: colors.textMuted }]}>
						{t("settings.themeSaved")}:
					</Text>
					<Text
						testID="settings-theme-persisted"
						style={[styles.muted, { color: colors.text }]}
					>
						{persistedMode === null ? "—" : t(THEME_LABELS[persistedMode])}
					</Text>
				</View>
			</View>

			{(session.data || session.isError) && (
				<SettingsButton
					title={t("home.logout")}
					onPress={() => void signOut()}
					danger
					testID="settings-logout"
				/>
			)}
		</Screen>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 24, fontWeight: "700" },
	card: {
		borderWidth: 1,
		borderRadius: 10,
		padding: 14,
		gap: 6,
	},
	cardTitle: { fontSize: 15, fontWeight: "600" },
	muted: { fontSize: 13 },
	link: { fontWeight: "600" },
	actionButton: {
		minHeight: 44,
		alignItems: "center",
		justifyContent: "center",
		borderWidth: 1,
	},
	actionLabel: { fontSize: 14, fontWeight: "600", textAlign: "center" },
	languageButton: { flex: 1 },
	linkButton: { minHeight: 44, justifyContent: "center" },
	segment: {
		flex: 1,
		minHeight: 44,
		alignItems: "center",
		justifyContent: "center",
		borderWidth: 1,
	},
	persistedRow: { flexDirection: "row", gap: 4 },
	segmentLabel: { fontSize: 13, fontWeight: "600" },
	pressed: { opacity: 0.75 },
});
