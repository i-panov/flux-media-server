import { useState } from "react";
import { Modal, Pressable, Text, TextInput, View } from "react-native";
import {
	useCreateFranchise,
	useCreateWork,
	type WorkKind,
} from "../api/catalog";
import { useSession } from "../auth/session";
import { t } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

export function CreateCatalogButton({ mode }: { mode: "work" | "franchise" }) {
	const { colors, spacing } = useTheme();
	const session = useSession();
	const createWork = useCreateWork();
	const createFranchise = useCreateFranchise();
	const [open, setOpen] = useState(false);
	const [kind, setKind] = useState<WorkKind>("series");
	const [value, setValue] = useState("");
	const [error, setError] = useState<string | null>(null);
	if (session.data?.is_admin !== true) return null;

	const submit = async () => {
		setError(null);
		try {
			if (mode === "work") {
				await createWork.mutateAsync({ kind, title: value.trim() });
			} else {
				await createFranchise.mutateAsync({ name: value.trim() });
			}
			setOpen(false);
			setValue("");
		} catch (err) {
			setError(err instanceof Error ? err.message : t("common.error"));
		}
	};

	return (
		<>
			<Pressable onPress={() => setOpen(true)} accessibilityRole="button">
				<Text style={{ color: colors.accent, fontWeight: "600" }}>
					{t("common.create")}
				</Text>
			</Pressable>
			<Modal
				visible={open}
				transparent
				animationType="fade"
				onRequestClose={() => setOpen(false)}
			>
				<View
					style={{
						flex: 1,
						justifyContent: "center",
						padding: spacing.lg,
						backgroundColor: "rgba(0,0,0,0.4)",
					}}
				>
					<View
						style={{
							backgroundColor: colors.background,
							borderRadius: 12,
							padding: spacing.lg,
							gap: spacing.sm,
						}}
					>
						<Text
							style={{ color: colors.text, fontSize: 18, fontWeight: "700" }}
						>
							{mode === "work"
								? t("catalog.newWork")
								: t("catalog.newFranchise")}
						</Text>
						{mode === "work" && (
							<View style={{ flexDirection: "row", gap: spacing.md }}>
								<Pressable onPress={() => setKind("series")}>
									<Text
										style={{
											color:
												kind === "series" ? colors.accent : colors.textMuted,
										}}
									>
										{t("catalog.seriesOne")}
									</Text>
								</Pressable>
								<Pressable onPress={() => setKind("film_series")}>
									<Text
										style={{
											color:
												kind === "film_series"
													? colors.accent
													: colors.textMuted,
										}}
									>
										{t("catalog.filmSeries")}
									</Text>
								</Pressable>
							</View>
						)}
						<TextInput
							style={{
								color: colors.text,
								borderColor: colors.border,
								borderWidth: 1,
								borderRadius: 8,
								padding: spacing.sm,
							}}
							value={value}
							onChangeText={setValue}
							placeholder={
								mode === "work"
									? t("catalog.adminTitle")
									: t("catalog.adminTitle")
							}
						/>
						{error && <Text style={{ color: colors.danger }}>{error}</Text>}
						<Pressable
							disabled={value.trim() === ""}
							onPress={() => void submit()}
						>
							<Text
								style={{
									color: value.trim() === "" ? colors.textMuted : colors.accent,
									fontWeight: "600",
								}}
							>
								{t("common.create")}
							</Text>
						</Pressable>
						<Pressable onPress={() => setOpen(false)}>
							<Text style={{ color: colors.textMuted }}>
								{t("common.cancel")}
							</Text>
						</Pressable>
					</View>
				</View>
			</Modal>
		</>
	);
}
