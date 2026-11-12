import {
	approveDeviceCode,
	type DeviceInspectResponse,
	inspectDeviceCode,
} from "@flux/shared";
import { router, useLocalSearchParams } from "expo-router";
import { useCallback, useEffect, useState } from "react";
import {
	ActivityIndicator,
	Pressable,
	StyleSheet,
	Text,
	TextInput,
	View,
} from "react-native";
import { useSession } from "../src/auth/session";
import { Screen } from "../src/components/Screen";
import { t, useLanguage } from "../src/i18n";
import { useTheme } from "../src/theme/ThemeProvider";

export default function ActivateScreen() {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const params = useLocalSearchParams<{ code?: string }>();
	const session = useSession();
	const [code, setCode] = useState(params.code ?? "");
	const [device, setDevice] = useState<DeviceInspectResponse | null>(null);
	const [error, setError] = useState<string | null>(null);
	const [loading, setLoading] = useState(false);
	const [done, setDone] = useState(false);

	const inspect = useCallback(async (value: string) => {
		const normalized = value.replace(/\D/g, "").slice(0, 6);
		if (normalized.length !== 6) return;
		setLoading(true);
		setError(null);
		try {
			setDevice(await inspectDeviceCode(normalized));
		} catch {
			setError(t("auth.activateInvalid"));
		} finally {
			setLoading(false);
		}
	}, []);

	useEffect(() => {
		if (params.code !== undefined && params.code !== "") {
			// eslint-disable-next-line react-hooks/set-state-in-effect -- внешний запрос при открытии deep link.
			void inspect(params.code);
		}
	}, [inspect, params.code]);

	const codeDigits = code.replace(/\D/g, "").slice(0, 6);
	const displayCode =
		codeDigits.length > 3
			? `${codeDigits.slice(0, 3)} ${codeDigits.slice(3)}`
			: codeDigits;

	const approve = async () => {
		setLoading(true);
		setError(null);
		try {
			await approveDeviceCode(codeDigits);
			setDone(true);
		} catch {
			setError(t("auth.activateInvalid"));
		} finally {
			setLoading(false);
		}
	};

	if (session.data === null) {
		return (
			<Screen scroll testID="activate-screen">
				<Text style={[styles.title, { color: colors.text }]}>
					{t("auth.activateTitle")}
				</Text>
				<Text style={{ color: colors.textMuted }}>
					{t("auth.activateLoginFirst")}
				</Text>
				<Pressable
					style={[styles.button, { backgroundColor: colors.accent }]}
					onPress={() => router.replace("/login")}
				>
					<Text style={[styles.buttonText, { color: colors.onAccent }]}>
						{t("login.signIn")}
					</Text>
				</Pressable>
			</Screen>
		);
	}

	return (
		<Screen scroll testID="activate-screen">
			<Text style={[styles.title, { color: colors.text }]}>
				{t("auth.activateTitle")}
			</Text>
			<Text style={{ color: colors.textMuted }}>{t("auth.activateHint")}</Text>
			{done ? (
				<View style={{ gap: spacing.md }}>
					<Text style={{ color: colors.accent, fontSize: 18 }}>
						{t("auth.activateSuccess")}
					</Text>
					<Pressable
						style={[styles.button, { backgroundColor: colors.accent }]}
						onPress={() => router.replace("/")}
					>
						<Text style={[styles.buttonText, { color: colors.onAccent }]}>
							{t("auth.activateDone")}
						</Text>
					</Pressable>
				</View>
			) : (
				<View style={{ gap: spacing.md }}>
					<TextInput
						value={displayCode}
						onChangeText={(value) =>
							setCode(value.replace(/\D/g, "").slice(0, 6))
						}
						keyboardType="number-pad"
						inputMode="numeric"
						autoComplete="one-time-code"
						autoFocus
						maxLength={7}
						placeholder={t("auth.activateCode")}
						placeholderTextColor={colors.textMuted}
						style={[
							styles.input,
							{
								borderColor: colors.controlBorder,
								backgroundColor: colors.surface,
								color: colors.text,
								borderRadius: radii.sm,
							},
						]}
					/>
					{device !== null && (
						<View
							style={[
								styles.device,
								{ borderColor: colors.border, backgroundColor: colors.surface },
							]}
						>
							<Text style={{ color: colors.text, fontSize: 18 }}>
								{device.device_name} · {device.platform}
							</Text>
							<Text style={{ color: colors.textMuted }}>
								{t("auth.activateDeviceHint")}
							</Text>
							<Pressable
								style={[styles.button, { backgroundColor: colors.accent }]}
								onPress={() => void approve()}
							>
								<Text style={[styles.buttonText, { color: colors.onAccent }]}>
									{t("auth.activateApprove")}
								</Text>
							</Pressable>
						</View>
					)}
					{error !== null && (
						<Text style={{ color: colors.danger }}>{error}</Text>
					)}
					<Pressable
						disabled={loading}
						style={[styles.button, { backgroundColor: colors.accent }]}
						onPress={() => void inspect(code)}
					>
						{loading ? (
							<ActivityIndicator color={colors.onAccent} />
						) : (
							<Text style={[styles.buttonText, { color: colors.onAccent }]}>
								{t("auth.activateCheck")}
							</Text>
						)}
					</Pressable>
				</View>
			)}
		</Screen>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 26, fontWeight: "700" },
	input: { borderWidth: 1, padding: 12, fontSize: 18 },
	button: { borderRadius: 8, padding: 14, alignItems: "center" },
	buttonText: { fontSize: 16, fontWeight: "600" },
	device: { borderWidth: 1, borderRadius: 10, padding: 14, gap: 8 },
});
