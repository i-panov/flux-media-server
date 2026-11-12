import {
	ACCESS_TOKEN_KEY,
	createDeviceCode,
	type DeviceCodeResponse,
	pollDeviceCode,
	qrMatrix,
	REFRESH_TOKEN_KEY,
} from "@flux/shared";
import { useQueryClient } from "@tanstack/react-query";
import { router } from "expo-router";
import { useCallback, useEffect, useState } from "react";
import {
	ActivityIndicator,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { t, useLanguage } from "../i18n";
import { secureStore } from "../storage/secureStore";
import { useTheme } from "../theme/ThemeProvider";
import { tvFocusStyle } from "../tv/focus";
import { getDeviceIdentity } from "./deviceInfo";
import { sessionQueryKey } from "./session";

function QrGrid({ value }: { value: string }) {
	const matrix = qrMatrix(value);
	const size = 232;
	const cell = size / matrix.size;
	return (
		<View
			accessibilityLabel={t("auth.qrLabel")}
			style={{ width: size, height: size, backgroundColor: "#fff" }}
		>
			{matrix.cells.map((dark, index) =>
				dark ? (
					<View
						// biome-ignore lint/suspicious/noArrayIndexKey: матрица QR неизменяемая.
						key={`${Math.floor(index / matrix.size)}-${index % matrix.size}`}
						style={{
							position: "absolute",
							left: (index % matrix.size) * cell,
							top: Math.floor(index / matrix.size) * cell,
							width: cell,
							height: cell,
							backgroundColor: "#000",
						}}
					/>
				) : null,
			)}
		</View>
	);
}

type Status = "loading" | "waiting" | "expired" | "error" | "approved";

export function TVDeviceLogin({ onUseOtp }: { onUseOtp: () => void }) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const queryClient = useQueryClient();
	const [data, setData] = useState<DeviceCodeResponse | null>(null);
	const [status, setStatus] = useState<Status>("loading");

	const start = useCallback(async () => {
		setStatus("loading");
		try {
			const device = await getDeviceIdentity();
			const result = await createDeviceCode({
				deviceId: device.deviceId,
				deviceName: device.deviceName,
				platform: device.platform,
			});
			setData(result);
			setStatus("waiting");
		} catch {
			setStatus("error");
		}
	}, []);

	useEffect(() => {
		// eslint-disable-next-line react-hooks/set-state-in-effect -- старт внешнего запроса при монтировании.
		void start();
	}, [start]);

	useEffect(() => {
		if (data === null || status !== "waiting") return;
		let cancelled = false;
		let timer: ReturnType<typeof setTimeout> | undefined;
		const tick = async () => {
			try {
				const result = await pollDeviceCode(data.device_code);
				if (cancelled) return;
				if (result.status === "ok") {
					await secureStore.set(ACCESS_TOKEN_KEY, result.token);
					await secureStore.set(REFRESH_TOKEN_KEY, result.refresh_token);
					queryClient.removeQueries();
					queryClient.setQueryData(sessionQueryKey, result.user);
					setStatus("approved");
					router.replace("/");
					return;
				}
				if (result.status === "pending") {
					timer = setTimeout(tick, data.interval * 1000);
					return;
				}
				setStatus(result.status === "expired" ? "expired" : "error");
			} catch {
				if (!cancelled) setStatus("error");
			}
		};
		timer = setTimeout(tick, data.interval * 1000);
		return () => {
			cancelled = true;
			if (timer !== undefined) clearTimeout(timer);
		};
	}, [data, status, queryClient]);

	const button = (label: string, onPress: () => void, testID?: string) => (
		<Pressable
			accessibilityRole="button"
			onPress={onPress}
			testID={testID}
			style={({ focused }) => [
				styles.button,
				{
					backgroundColor: colors.accent,
					borderRadius: radii.md,
					padding: spacing.md,
				},
				tvFocusStyle(focused, colors.accent),
			]}
		>
			<Text style={[styles.buttonText, { color: colors.onAccent }]}>
				{label}
			</Text>
		</Pressable>
	);

	if (status === "loading") {
		return (
			<View style={styles.center}>
				<ActivityIndicator color={colors.accent} />
				<Text style={{ color: colors.textMuted }}>{t("auth.qrLoading")}</Text>
			</View>
		);
	}

	const retryLabel = t("auth.qrRetry");

	if (status === "error" || data === null) {
		return (
			<View style={styles.center}>
				<Text style={[styles.title, { color: colors.text }]}>
					{t("auth.qrError")}
				</Text>
				{button(retryLabel, () => void start(), "tv-qr-retry")}
			</View>
		);
	}

	if (status === "expired") {
		return (
			<View style={styles.center}>
				<Text style={[styles.title, { color: colors.text }]}>
					{t("auth.qrExpired")}
				</Text>
				{button(retryLabel, () => void start(), "tv-qr-retry")}
			</View>
		);
	}

	if (status === "approved") {
		return (
			<View style={styles.center}>
				<Text style={[styles.title, { color: colors.text }]}>
					{t("auth.activateSuccess")}
				</Text>
			</View>
		);
	}

	return (
		<View style={[styles.card, { gap: spacing.md }]}>
			<Text style={[styles.title, { color: colors.text }]}>
				{t("auth.qrTitle")}
			</Text>
			<Text style={{ color: colors.textMuted }}>{t("auth.qrHint")}</Text>
			<QrGrid value={data.verification_uri_complete} />
			<Text style={[styles.code, { color: colors.text }]}>
				{t("auth.qrCode")} {data.user_code}
			</Text>
			<Text style={{ color: colors.textMuted }}>{data.verification_uri}</Text>
			{button(retryLabel, () => void start(), "tv-qr-new")}
			{button(t("auth.qrBackToOtp"), onUseOtp, "tv-qr-otp")}
		</View>
	);
}

const styles = StyleSheet.create({
	card: { alignItems: "center", paddingVertical: 12 },
	center: { alignItems: "center", gap: 12, paddingVertical: 24 },
	title: { fontSize: 26, fontWeight: "700", textAlign: "center" },
	code: { fontSize: 22, fontWeight: "700", letterSpacing: 2 },
	button: { minWidth: 260, alignItems: "center" },
	buttonText: { fontSize: 18, fontWeight: "600" },
});
