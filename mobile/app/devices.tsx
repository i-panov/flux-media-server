import Ionicons from "@expo/vector-icons/Ionicons";
import { fetchDevices, renameDevice, revokeDevice } from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { router } from "expo-router";
import { useState } from "react";
import {
	Alert,
	Pressable,
	StyleSheet,
	Text,
	TextInput,
	View,
} from "react-native";
import { getDeviceIdentity } from "../src/auth/deviceInfo";
import { AuthGate } from "../src/components/AuthGate";
import { ErrorState } from "../src/components/ErrorState";
import { Screen } from "../src/components/Screen";
import { t, useLanguage } from "../src/i18n";
import { useTheme } from "../src/theme/ThemeProvider";

export default function DevicesScreen() {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const queryClient = useQueryClient();
	const devices = useQuery({
		queryKey: ["auth", "devices"],
		queryFn: async () => {
			const device = await getDeviceIdentity();
			return fetchDevices(device.deviceId);
		},
	});
	const revoke = useMutation({
		mutationFn: (deviceId: string) => revokeDevice(deviceId),
		onSuccess: () =>
			queryClient.invalidateQueries({ queryKey: ["auth", "devices"] }),
		onError: () => Alert.alert(t("devices.revokeError")),
	});
	const rename = useMutation({
		mutationFn: ({ deviceId, name }: { deviceId: string; name: string }) =>
			renameDevice(deviceId, name),
		onSuccess: () => {
			setEditingId(null);
			void queryClient.invalidateQueries({ queryKey: ["auth", "devices"] });
		},
		onError: () => Alert.alert(t("devices.renameError")),
	});
	const [editingId, setEditingId] = useState<string | null>(null);
	const [draft, setDraft] = useState("");

	const confirmRevoke = (deviceId: string) => {
		Alert.alert(t("devices.title"), t("devices.confirm"), [
			{ text: t("common.cancel"), style: "cancel" },
			{
				text: t("devices.revoke"),
				style: "destructive",
				onPress: () => revoke.mutate(deviceId),
			},
		]);
	};

	return (
		<AuthGate>
			<Screen scroll testID="devices-screen">
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("common.back")}
					onPress={() =>
						router.canGoBack() ? router.back() : router.replace("/settings")
					}
					testID="devices-back"
					hitSlop={8}
					style={styles.back}
				>
					<Ionicons name="chevron-back" size={24} color={colors.text} />
					<Text style={{ color: colors.text, fontSize: 16 }}>
						{t("common.back")}
					</Text>
				</Pressable>
				<Text style={[styles.title, { color: colors.text }]}>
					{t("devices.title")}
				</Text>
				<Text style={{ color: colors.textMuted }}>{t("devices.hint")}</Text>
				{devices.isPending && (
					<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
				)}
				{devices.isError && !devices.data && (
					<ErrorState
						testID="devices-error"
						retryTestID="devices-retry"
						onRetry={() => void devices.refetch()}
					/>
				)}
				{devices.data?.length === 0 && (
					<Text style={{ color: colors.textMuted }}>{t("devices.empty")}</Text>
				)}
				{devices.data?.map((device) => (
					<View
						key={device.device_id}
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
						{editingId === device.device_id ? (
							<View style={{ flexDirection: "row", gap: spacing.sm }}>
								<TextInput
									value={draft}
									onChangeText={setDraft}
									maxLength={80}
									autoFocus
									style={[
										styles.input,
										{
											borderColor: colors.controlBorder,
											color: colors.text,
											flex: 1,
										},
									]}
								/>
								<Pressable
									style={[styles.revoke, { borderColor: colors.accent }]}
									onPress={() =>
										rename.mutate({
											deviceId: device.device_id,
											name: draft.trim(),
										})
									}
								>
									<Text style={{ color: colors.accent }}>
										{t("common.save")}
									</Text>
								</Pressable>
								<Pressable
									style={[styles.revoke, { borderColor: colors.border }]}
									onPress={() => setEditingId(null)}
								>
									<Text style={{ color: colors.textMuted }}>
										{t("common.cancel")}
									</Text>
								</Pressable>
							</View>
						) : (
							<View
								style={{
									flexDirection: "row",
									gap: spacing.sm,
									alignItems: "center",
								}}
							>
								<Text
									style={{
										color: colors.text,
										fontSize: 18,
										fontWeight: "600",
									}}
								>
									{device.device_name}
								</Text>
								<Pressable
									onPress={() => {
										setEditingId(device.device_id);
										setDraft(device.device_name);
									}}
								>
									<Text style={{ color: colors.accent }}>
										{t("devices.rename")}
									</Text>
								</Pressable>
							</View>
						)}
						<Text style={{ color: colors.textMuted }}>
							{device.current
								? `${device.platform} · ${t("devices.current")}`
								: device.platform}
						</Text>
						<Pressable
							style={[styles.revoke, { borderColor: colors.danger }]}
							onPress={() => confirmRevoke(device.device_id)}
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
	back: { flexDirection: "row", alignItems: "center", minHeight: 44 },
	title: { fontSize: 26, fontWeight: "700" },
	card: { borderWidth: 1, gap: 6 },
	input: { borderWidth: 1, borderRadius: 8, padding: 8 },
	revoke: {
		borderWidth: 1,
		borderRadius: 8,
		padding: 10,
		alignSelf: "flex-start",
	},
});
