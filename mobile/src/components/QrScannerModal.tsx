import Ionicons from "@expo/vector-icons/Ionicons";
import { CameraView, useCameraPermissions } from "expo-camera";
import { useEffect, useRef, useState } from "react";
import {
	Linking,
	Modal,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { parseDeviceCodeFromQr } from "../auth/deviceQr";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

// Сканер QR прямо в приложении: не нужен сторонний софт и ручной ввод.
export function QrScannerModal({
	visible,
	onClose,
	onCode,
}: {
	visible: boolean;
	onClose: () => void;
	onCode: (code: string) => void;
}) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const [permission, requestPermission] = useCameraPermissions();
	const [mountError, setMountError] = useState(false);
	const handled = useRef(false);
	const asked = useRef(false);

	useEffect(() => {
		if (!visible) {
			handled.current = false;
			asked.current = false;
			return;
		}
		// Системный диалог — один раз на открытие. Повторный отказ не должен
		// снова и снова показывать запрос: для этого есть кнопка ниже.
		if (asked.current) {
			return;
		}
		if (permission !== null && !permission.granted && permission.canAskAgain) {
			asked.current = true;
			void requestPermission();
		}
	}, [visible, permission, requestPermission]);

	// Сброс ошибки камеры при новом открытии — синхронно в рендере,
	// без setState в эффекте.
	const [wasVisible, setWasVisible] = useState(visible);
	if (visible !== wasVisible) {
		setWasVisible(visible);
		if (visible) {
			setMountError(false);
		}
	}

	const handleScan = (value: string) => {
		if (handled.current) return;
		const code = parseDeviceCodeFromQr(value);
		if (code === null) return;
		handled.current = true;
		onCode(code);
	};

	return (
		<Modal
			visible={visible}
			animationType="slide"
			onRequestClose={onClose}
			testID="qr-scanner"
		>
			<SafeAreaView style={[styles.fill, { backgroundColor: "#000" }]}>
				<View style={[styles.header, { padding: spacing.md }]}>
					<Text style={styles.title}>{t("auth.scanTitle")}</Text>
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={t("common.close")}
						testID="qr-scanner-close"
						onPress={onClose}
						hitSlop={8}
					>
						<Ionicons name="close" size={26} color="#fff" />
					</Pressable>
				</View>
				{permission?.granted === true ? (
					<CameraView
						style={styles.fill}
						facing="back"
						barcodeScannerSettings={{ barcodeTypes: ["qr"] }}
						onBarcodeScanned={({ data }) => handleScan(data)}
						onMountError={() => setMountError(true)}
					/>
				) : (
					<View style={[styles.permission, { gap: spacing.md }]}>
						<Text style={styles.hint}>
							{permission?.canAskAgain === false
								? t("auth.cameraDenied")
								: t("auth.cameraHint")}
						</Text>
						{permission?.canAskAgain === false && (
							<Pressable
								accessibilityRole="button"
								style={[styles.button, { backgroundColor: colors.accent }]}
								onPress={() => void Linking.openSettings()}
								testID="qr-scanner-settings"
							>
								<Text style={[styles.buttonText, { color: colors.onAccent }]}>
									{t("auth.cameraSettings")}
								</Text>
							</Pressable>
						)}
						{permission?.canAskAgain !== false && (
							<Pressable
								accessibilityRole="button"
								style={[styles.button, { backgroundColor: colors.accent }]}
								onPress={() => void requestPermission()}
								testID="qr-scanner-allow"
							>
								<Text style={[styles.buttonText, { color: colors.onAccent }]}>
									{t("auth.cameraAllow")}
								</Text>
							</Pressable>
						)}
					</View>
				)}
				{permission?.granted === true && (
					<Text style={[styles.caption, { padding: spacing.md }]}>
						{mountError ? t("auth.cameraUnavailable") : t("auth.scanHint")}
					</Text>
				)}
			</SafeAreaView>
		</Modal>
	);
}

const styles = StyleSheet.create({
	fill: { flex: 1 },
	header: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
	},
	title: { color: "#fff", fontSize: 18, fontWeight: "600" },
	hint: { color: "rgba(255,255,255,0.85)", textAlign: "center" },
	caption: {
		color: "rgba(255,255,255,0.8)",
		textAlign: "center",
		backgroundColor: "rgba(0,0,0,0.55)",
	},
	permission: {
		flex: 1,
		alignItems: "center",
		justifyContent: "center",
		paddingHorizontal: 24,
	},
	button: { borderRadius: 8, paddingVertical: 12, paddingHorizontal: 20 },
	buttonText: { fontSize: 16, fontWeight: "600" },
});
