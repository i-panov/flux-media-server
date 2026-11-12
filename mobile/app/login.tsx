import {
	ACCESS_TOKEN_KEY,
	ApiError,
	REFRESH_TOKEN_KEY,
	requestCode,
	verifyCode,
} from "@flux/shared";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Redirect, router } from "expo-router";
import { useState } from "react";
import {
	ActivityIndicator,
	Pressable,
	StyleSheet,
	Text,
	TextInput,
	View,
} from "react-native";
import { getDeviceIdentity } from "../src/auth/deviceInfo";
import { sessionQueryKey, useSession } from "../src/auth/session";
import { TVDeviceLogin } from "../src/auth/TVDeviceLogin";
import { Screen } from "../src/components/Screen";
import { t, useLanguage } from "../src/i18n";
import { secureStore } from "../src/storage/secureStore";
import { useTheme } from "../src/theme/ThemeProvider";
import { tvFocusStyle } from "../src/tv/focus";
import { isTV } from "../src/tv/profile";

// eslint-disable-next-line max-lines-per-function -- экран держит OTP и TV QR-вход.
export default function LoginScreen() {
	useLanguage();
	const { colors } = useTheme();
	const session = useSession();
	const queryClient = useQueryClient();
	const [email, setEmail] = useState("");
	const [code, setCode] = useState("");
	const [codeSent, setCodeSent] = useState(false);
	const [debugCode, setDebugCode] = useState<string | null>(null);
	const [tvQr, setTvQr] = useState(true);
	const [error, setError] = useState<string | null>(null);
	const [focusedField, setFocusedField] = useState<"email" | "code" | null>(
		null,
	);

	const request = useMutation({
		mutationFn: requestCode,
		onSuccess: (data) => {
			setCodeSent(true);
			setDebugCode(data.code ?? null);
			setError(null);
		},
		onError: () => setError(t("login.error")),
	});

	const verify = useMutation({
		mutationFn: async ({
			email: value,
			code: value2,
		}: {
			email: string;
			code: string;
		}) => {
			const device = await getDeviceIdentity();
			return verifyCode(value, value2, device);
		},
		onSuccess: async (data) => {
			await secureStore.set(ACCESS_TOKEN_KEY, data.token);
			await secureStore.set(REFRESH_TOKEN_KEY, data.refresh_token);
			// Кэш прошлого пользователя не должен переехать в новую сессию;
			// removeQueries также отменяет висящий /auth/me со старым токеном.
			queryClient.removeQueries();
			queryClient.setQueryData(sessionQueryKey, data.user);
			// Login мог быть открыт поверх /server (ссылка «Вход»): replace
			// оставил бы server/login в истории. Схлопываем стек до входа.
			if (router.canDismiss()) {
				router.dismissAll();
			}
			router.replace("/");
		},
		onError: (failure) => {
			setError(
				failure instanceof ApiError && failure.status === 401
					? t("login.invalid")
					: t("login.error"),
			);
		},
	});

	if (session.data) {
		return <Redirect href="/" />;
	}

	if (isTV && tvQr) {
		return (
			<Screen testID="auth-entry" contentContainerStyle={styles.screen}>
				<TVDeviceLogin onUseOtp={() => setTvQr(false)} />
			</Screen>
		);
	}

	const pending = request.isPending || verify.isPending;
	const signInDisabled = pending || code.trim() === "";
	const requestCodeDisabled = pending || email.trim() === "";
	const inputStyle = [
		styles.input,
		{
			borderColor: focusedField === null ? colors.controlBorder : colors.accent,
			backgroundColor: colors.surface,
			color: colors.text,
		},
	];

	return (
		<Screen testID="auth-entry" contentContainerStyle={styles.screen}>
			<View style={styles.card}>
				<Text style={[styles.title, { color: colors.text }]}>
					{t("login.title")}
				</Text>
				<Text style={[styles.subtitle, { color: colors.textMuted }]}>
					{t("login.subtitle")}
				</Text>
				{error !== null && (
					<Text style={{ color: colors.danger }}>{error}</Text>
				)}
				{codeSent ? (
					<>
						<Text style={[styles.label, { color: colors.textMuted }]}>
							{t("login.code")}
						</Text>
						<TextInput
							testID="login-code"
							style={inputStyle}
							value={code}
							onChangeText={setCode}
							onFocus={() => setFocusedField("code")}
							onBlur={() => setFocusedField(null)}
							keyboardType="number-pad"
							autoComplete="one-time-code"
							placeholderTextColor={colors.textMuted}
						/>
						{debugCode !== null && (
							<Text
								testID="login-debug-code"
								style={[styles.debug, { color: colors.accent }]}
							>
								{t("login.devCode", { code: debugCode })}
							</Text>
						)}
						<Pressable
							testID="login-sign-in"
							accessibilityRole="button"
							accessibilityState={{ disabled: signInDisabled }}
							style={({ pressed, focused }) => [
								styles.button,
								{
									backgroundColor: colors.accent,
									opacity: signInDisabled ? 0.5 : 1,
								},
								pressed && !signInDisabled && styles.pressed,
								tvFocusStyle(focused, colors.accent),
							]}
							disabled={signInDisabled}
							onPress={() =>
								verify.mutate({ email: email.trim(), code: code.trim() })
							}
						>
							{pending ? (
								<ActivityIndicator color={colors.onAccent} />
							) : (
								<Text style={[styles.buttonText, { color: colors.onAccent }]}>
									{t("login.signIn")}
								</Text>
							)}
						</Pressable>
						<Pressable
							accessibilityRole="button"
							hitSlop={8}
							style={styles.linkButton}
							onPress={() => setCodeSent(false)}
						>
							<Text style={[styles.link, { color: colors.accent }]}>
								{t("login.changeEmail")}
							</Text>
						</Pressable>
					</>
				) : (
					<>
						<Text style={[styles.label, { color: colors.textMuted }]}>
							{t("login.email")}
						</Text>
						<TextInput
							testID="login-email"
							style={inputStyle}
							value={email}
							onChangeText={setEmail}
							onFocus={() => setFocusedField("email")}
							onBlur={() => setFocusedField(null)}
							hasTVPreferredFocus={isTV}
							autoCapitalize="none"
							autoCorrect={false}
							keyboardType="email-address"
							placeholderTextColor={colors.textMuted}
						/>
						<Pressable
							testID="login-request-code"
							accessibilityRole="button"
							accessibilityState={{ disabled: requestCodeDisabled }}
							style={({ pressed, focused }) => [
								styles.button,
								{
									backgroundColor: colors.accent,
									opacity: requestCodeDisabled ? 0.5 : 1,
								},
								pressed && !requestCodeDisabled && styles.pressed,
								tvFocusStyle(focused, colors.accent),
							]}
							disabled={requestCodeDisabled}
							onPress={() => request.mutate(email.trim())}
						>
							{pending ? (
								<ActivityIndicator color={colors.onAccent} />
							) : (
								<Text style={[styles.buttonText, { color: colors.onAccent }]}>
									{t("login.getCode")}
								</Text>
							)}
						</Pressable>
					</>
				)}
				{isTV && (
					<Pressable
						accessibilityRole="button"
						style={styles.linkButton}
						onPress={() => setTvQr(true)}
					>
						<Text style={[styles.link, { color: colors.accent }]}>
							{t("auth.qrUse")}
						</Text>
					</Pressable>
				)}
				<Pressable
					testID="login-open-server"
					accessibilityRole="button"
					hitSlop={8}
					style={styles.linkButton}
					onPress={() => router.push("/server")}
				>
					<Text style={[styles.link, { color: colors.accent }]}>
						{t("server.open")}
					</Text>
				</Pressable>
			</View>
		</Screen>
	);
}

const styles = StyleSheet.create({
	screen: { justifyContent: "center" },
	card: { gap: 12 },
	title: { fontSize: 28, fontWeight: "700" },
	subtitle: { fontSize: 15, marginBottom: 8 },
	label: { fontSize: 13 },
	input: {
		borderWidth: 1,
		borderRadius: 8,
		padding: 12,
		fontSize: 16,
	},
	button: {
		borderRadius: 8,
		padding: 14,
		minHeight: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	buttonText: { fontWeight: "600", fontSize: 16 },
	linkButton: {
		minHeight: 44,
		justifyContent: "center",
	},
	link: { textAlign: "center" },
	debug: { fontSize: 12 },
	pressed: { opacity: 0.7 },
});
