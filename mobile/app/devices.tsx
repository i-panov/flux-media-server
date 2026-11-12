import { fetchDevices, revokeDevice } from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Alert, Pressable, StyleSheet, Text, View } from "react-native";
import { AuthGate } from "../src/components/AuthGate";
import { Screen } from "../src/components/Screen";
import { t, useLanguage } from "../src/i18n";
import { useTheme } from "../src/theme/ThemeProvider";

export default function DevicesScreen() {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const queryClient = useQueryClient();
	const devices = useQuery({
		queryKey: ["auth", "devices"],
		queryFn: fetchDevices,
	});
	const revoke = useMutation({
		mutationFn: (id: number) => revokeDevice(id),
		onSuccess: () =>
			queryClient.invalidateQueries({ queryKey: ["auth", "devices"] }),
		onError: () => Alert.alert(t("devices.revokeError")),
	});

	const confirmRevoke = (id: number) => {
		Alert.alert(t("devices.title"), t("devices.confirm"), [
			{ text: t("common.cancel"), style: "cancel" },
			{
				text: t("devices.revoke"),
				style: "destructive",
				onPress: () => revoke.mutate(id),
			},
		]);
	};

	return (
		<AuthGate>
			<Screen scroll testID="devices-screen">
				<Text style={[styles.title, { color: colors.text }]}>
					{t("devices.title")}
				</Text>
				<Text style={{ color: colors.textMuted }}>{t("devices.hint")}</Text>
				{devices.isPending && (
					<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
				)}
				{devices.data?.length === 0 && (
					<Text style={{ color: colors.textMuted }}>{t("devices.empty")}</Text>
				)}
				{devices.data?.map((device) => (
					<View
						key={device.id}
						style={[
							styles.card,
							{
								borderColor: colors.border,
								backgroundColor: colors.surface,
								borderRadius: radii.md,
								padding: spacing.md,
							},
						]}
					>
						<Text
							style={{ color: colors.text, fontSize: 18, fontWeight: "600" }}
						>
							{device.device_name}
						</Text>
						<Text style={{ color: colors.textMuted }}>{device.platform}</Text>
						<Pressable
							style={[styles.revoke, { borderColor: colors.danger }]}
							onPress={() => confirmRevoke(device.id)}
						>
							<Text style={{ color: colors.danger }}>
								{t("devices.revoke")}
							</Text>
						</Pressable>
					</View>
				))}
			</Screen>
		</AuthGate>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 26, fontWeight: "700" },
	card: { borderWidth: 1, gap: 6 },
	revoke: {
		borderWidth: 1,
		borderRadius: 8,
		padding: 10,
		alignSelf: "flex-start",
	},
});
