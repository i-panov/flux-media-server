import { router } from "expo-router";
import { StyleSheet, Text, View } from "react-native";
import { useSession } from "../src/auth/session";
import { AuthGate } from "../src/components/AuthGate";
import { MaintenancePanel } from "../src/components/admin/MaintenancePanel";
import { TagsPanel } from "../src/components/admin/TagsPanel";
import { UsersPanel } from "../src/components/admin/UsersPanel";
import { EmptyState } from "../src/components/EmptyState";
import { Screen } from "../src/components/Screen";
import { t, useLanguage } from "../src/i18n";
import { useTheme } from "../src/theme/ThemeProvider";

export default function AdminScreen() {
	return (
		<AuthGate>
			<AdminContent />
		</AuthGate>
	);
}

function Section({
	title,
	children,
}: {
	title: string;
	children: React.ReactNode;
}) {
	const { colors, spacing } = useTheme();
	return (
		<View style={{ gap: spacing.sm }}>
			<Text style={[styles.sectionTitle, { color: colors.text }]}>{title}</Text>
			<View
				style={[
					styles.card,
					{
						backgroundColor: colors.surface,
						borderColor: colors.border,
						padding: spacing.md,
					},
				]}
			>
				{children}
			</View>
		</View>
	);
}

function AdminContent() {
	useLanguage();
	const { colors, spacing } = useTheme();
	const session = useSession();
	if (session.data?.is_admin !== true) {
		return (
			<Screen scroll>
				<EmptyState title={t("admin.title")} icon="lock-closed-outline" />
			</Screen>
		);
	}
	return (
		<Screen scroll>
			<View style={[styles.header, { gap: spacing.sm }]}>
				<Text
					accessibilityRole="button"
					accessibilityLabel={t("common.back")}
					onPress={() => {
						if (router.canGoBack()) router.back();
						else router.replace("/settings");
					}}
					style={{ color: colors.accent }}
					testID="admin-back"
				>
					{t("common.back")}
				</Text>
				<Text style={[styles.title, { color: colors.text }]}>
					{t("admin.title")}
				</Text>
			</View>
			<Section title={t("admin.tags")}>
				<TagsPanel />
			</Section>
			<Section title={t("admin.maintenance")}>
				<MaintenancePanel />
			</Section>
			<Section title={t("admin.users")}>
				<UsersPanel />
			</Section>
		</Screen>
	);
}

const styles = StyleSheet.create({
	header: { flexDirection: "row", alignItems: "center" },
	title: { fontSize: 24, fontWeight: "700" },
	sectionTitle: { fontSize: 17, fontWeight: "600" },
	card: { borderWidth: 1, borderRadius: 12, gap: 8 },
});
