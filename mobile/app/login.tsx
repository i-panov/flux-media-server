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
import { SafeAreaView } from "react-native-safe-area-context";
import { sessionQueryKey, useSession } from "../src/auth/session";
import { t, useLanguage } from "../src/i18n";
import { secureStore } from "../src/storage/secureStore";

export default function LoginScreen() {
	useLanguage();
	const session = useSession();
	const queryClient = useQueryClient();
	const [email, setEmail] = useState("");
	const [code, setCode] = useState("");
	const [codeSent, setCodeSent] = useState(false);
	const [debugCode, setDebugCode] = useState<string | null>(null);
	const [error, setError] = useState<string | null>(null);

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
		mutationFn: ({
			email: value,
			code: value2,
		}: {
			email: string;
			code: string;
		}) => verifyCode(value, value2),
		onSuccess: async (data) => {
			await secureStore.set(ACCESS_TOKEN_KEY, data.token);
			await secureStore.set(REFRESH_TOKEN_KEY, data.refresh_token);
			// Кэш прошлого пользователя не должен переехать в новую сессию;
			// removeQueries также отменяет висящий /auth/me со старым токеном.
			queryClient.removeQueries();
			queryClient.setQueryData(sessionQueryKey, data.user);
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

	const pending = request.isPending || verify.isPending;

	return (
		<SafeAreaView style={styles.screen}>
			<View style={styles.card}>
				<Text style={styles.title}>{t("login.title")}</Text>
				<Text style={styles.subtitle}>{t("login.subtitle")}</Text>
				{error !== null && <Text style={styles.error}>{error}</Text>}
				{codeSent ? (
					<>
						<Text style={styles.label}>{t("login.code")}</Text>
						<TextInput
							style={styles.input}
							value={code}
							onChangeText={setCode}
							keyboardType="number-pad"
							autoComplete="one-time-code"
						/>
						{debugCode !== null && (
							<Text style={styles.debug}>
								{t("login.devCode", { code: debugCode })}
							</Text>
						)}
						<Pressable
							style={styles.button}
							disabled={pending || code.trim() === ""}
							onPress={() =>
								verify.mutate({ email: email.trim(), code: code.trim() })
							}
						>
							{pending ? (
								<ActivityIndicator />
							) : (
								<Text style={styles.buttonText}>{t("login.signIn")}</Text>
							)}
						</Pressable>
						<Pressable onPress={() => setCodeSent(false)}>
							<Text style={styles.link}>{t("login.changeEmail")}</Text>
						</Pressable>
					</>
				) : (
					<>
						<Text style={styles.label}>{t("login.email")}</Text>
						<TextInput
							style={styles.input}
							value={email}
							onChangeText={setEmail}
							autoCapitalize="none"
							autoCorrect={false}
							keyboardType="email-address"
						/>
						<Pressable
							style={styles.button}
							disabled={pending || email.trim() === ""}
							onPress={() => request.mutate(email.trim())}
						>
							{pending ? (
								<ActivityIndicator />
							) : (
								<Text style={styles.buttonText}>{t("login.getCode")}</Text>
							)}
						</Pressable>
					</>
				)}
				<Pressable onPress={() => router.push("/settings")}>
					<Text style={styles.link}>{t("home.settings")}</Text>
				</Pressable>
			</View>
		</SafeAreaView>
	);
}

const styles = StyleSheet.create({
	screen: { flex: 1, justifyContent: "center", padding: 24 },
	card: { gap: 12 },
	title: { fontSize: 28, fontWeight: "700" },
	subtitle: { fontSize: 15, opacity: 0.6, marginBottom: 8 },
	label: { fontSize: 13, opacity: 0.6 },
	input: {
		borderWidth: 1,
		borderColor: "#8884",
		borderRadius: 8,
		padding: 12,
		fontSize: 16,
	},
	button: {
		backgroundColor: "#7048e8",
		borderRadius: 8,
		padding: 14,
		alignItems: "center",
	},
	buttonText: { color: "#fff", fontWeight: "600", fontSize: 16 },
	link: { textAlign: "center", marginTop: 8 },
	error: { color: "#e03131" },
	debug: { color: "#e8590c", fontSize: 12 },
});
