import Ionicons from "@expo/vector-icons/Ionicons";
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
import { QrScannerModal } from "../src/components/QrScannerModal";
import { Screen } from "../src/components/Screen";
import { t, useLanguage } from "../src/i18n";
import { useTheme } from "../src/theme/ThemeProvider";
import { tvFocusStyle } from "../src/tv/focus";
import { isTV } from "../src/tv/profile";

// expo-router отдаёт массив при повторяющемся ?code=: без нормализации
// `.replace` упал бы на массиве.
function firstParam(value: string | string[] | undefined): string {
	if (typeof value === "string") {
		return value;
	}
	return Array.isArray(value) ? (value[0] ?? "") : "";
}

export default function ActivateScreen() {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const params = useLocalSearchParams<{ code?: string | string[] }>();
	// expo-router отдаёт массив при повторяющемся ?code=: без нормализации
	// `.replace` упал бы на массиве.
	const deepLinkCode = firstParam(params.code);
	const session = useSession();
	const [code, setCode] = useState(deepLinkCode);
	const [device, setDevice] = useState<DeviceInspectResponse | null>(null);
	const [inspectedCode, setInspectedCode] = useState<string | null>(null);
	const [error, setError] = useState<string | null>(null);
	const [loading, setLoading] = useState(false);
	const [done, setDone] = useState(false);
	const [scanOpen, setScanOpen] = useState(false);

	const inspect = useCallback(async (value: string) => {
		const normalized = value.replace(/\D/g, "").slice(0, 6);
		if (normalized.length !== 6) return;
		setLoading(true);
		setError(null);
		setDevice(null);
		setInspectedCode(null);
		try {
			const found = await inspectDeviceCode(normalized);
			setDevice(found);
			setInspectedCode(normalized);
		} catch {
			setError(t("auth.activateInvalid"));
		} finally {
			setLoading(false);
		}
	}, []);

	useEffect(() => {
		if (deepLinkCode !== "") {
			// eslint-disable-next-line react-hooks/set-state-in-effect -- внешний запрос при открытии deep link.
			void inspect(deepLinkCode);
		}
	}, [inspect, deepLinkCode]);

	const backLabel = t("common.back");
	const goBack = () => {
		if (router.canGoBack()) {
			router.back();
			return;
		}
		router.replace(session.data == null ? "/login" : "/settings");
	};

	const codeDigits = code.replace(/\D/g, "").slice(0, 6);
	const displayCode = formatCode(codeDigits);

	const approve = async () => {
		if (loading || device === null || inspectedCode !== codeDigits) {
			return;
		}
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
				<BackButton label={backLabel} onPress={goBack} />
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
			<BackButton label={backLabel} onPress={goBack} />
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
						onChangeText={(value) => {
							setCode(value.replace(/\D/g, "").slice(0, 6));
							setDevice(null);
							setInspectedCode(null);
						}}
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
								disabled={loading || inspectedCode !== codeDigits}
								style={[
									styles.button,
									{ backgroundColor: colors.accent },
									(loading || inspectedCode !== codeDigits) && styles.disabled,
								]}
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
					{!isTV && (
						<Pressable
							style={[
								styles.button,
								{ borderColor: colors.accent, borderWidth: 1 },
							]}
							onPress={() => setScanOpen(true)}
							testID="activate-scan"
						>
							<Text style={{ color: colors.accent, fontWeight: "600" }}>
								{t("auth.scanQr")}
							</Text>
						</Pressable>
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
			<QrScannerModal
				visible={scanOpen}
				onClose={() => setScanOpen(false)}
				onCode={(value) => {
					setScanOpen(false);
					setCode(value);
					void inspect(value);
				}}
			/>
		</Screen>
	);
}

function formatCode(code: string): string {
	return code.length > 3 ? `${code.slice(0, 3)} ${code.slice(3)}` : code;
}

function BackButton({
	label,
	onPress,
}: {
	label: string;
	onPress: () => void;
}) {
	const { colors } = useTheme();
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={label}
			onPress={onPress}
			testID="activate-back"
			hitSlop={8}
			style={({ focused }) => [
				styles.back,
				tvFocusStyle(focused, colors.accent),
			]}
		>
			<Ionicons name="chevron-back" size={24} color={colors.text} />
			<Text style={{ color: colors.text, fontSize: 16 }}>{label}</Text>
		</Pressable>
	);
}

const styles = StyleSheet.create({
	back: {
		flexDirection: "row",
		alignItems: "center",
		gap: 4,
		alignSelf: "flex-start",
	},
	disabled: { opacity: 0.5 },
	title: { fontSize: 26, fontWeight: "700" },
	input: { borderWidth: 1, padding: 12, fontSize: 18 },
	button: { borderRadius: 8, padding: 14, alignItems: "center" },
	buttonText: { fontSize: 16, fontWeight: "600" },
	device: { borderWidth: 1, borderRadius: 10, padding: 14, gap: 8 },
});
