import { Alert, Pressable, StyleSheet, Switch, Text, View } from "react-native";
import { useAdminUsers, useDeleteUser, useSetUserAdmin } from "../../api/admin";
import { useSession } from "../../auth/session";
import { t, useLanguage } from "../../i18n";
import { useTheme } from "../../theme/ThemeProvider";

export function UsersPanel() {
	useLanguage();
	const { colors, spacing } = useTheme();
	const errorLabel = t("common.error");
	const users = useAdminUsers();
	const session = useSession();
	const setAdmin = useSetUserAdmin();
	const remove = useDeleteUser();
	const deleteLabel = t("admin.users.delete");
	if (users.isPending) {
		return (
			<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
		);
	}
	if (users.isError) {
		return <Text style={{ color: colors.danger }}>{errorLabel}</Text>;
	}
	if ((users.data ?? []).length === 0) {
		return (
			<Text style={{ color: colors.textMuted }}>{t("admin.users.empty")}</Text>
		);
	}
	return (
		<View style={{ gap: spacing.sm }}>
			{(users.data ?? []).map((user) => {
				const self = session.data?.id === user.id;
				return (
					<View key={user.id} style={[styles.row, { gap: spacing.sm }]}>
						<Text style={{ color: colors.text, flex: 1 }} numberOfLines={1}>
							{user.email}
						</Text>
						<Switch
							value={user.is_admin}
							disabled={self || setAdmin.isPending}
							testID={`admin-user-admin-${user.id}`}
							onValueChange={(value) =>
								setAdmin.mutate(
									{ id: user.id, isAdmin: value },
									{
										onError: () => Alert.alert(t("admin.users"), errorLabel),
									},
								)
							}
						/>
						{!self && (
							<Pressable
								accessibilityRole="button"
								testID={`admin-user-delete-${user.id}`}
								onPress={() =>
									Alert.alert(deleteLabel, user.email, [
										{ text: t("common.cancel"), style: "cancel" },
										{
											text: deleteLabel,
											style: "destructive",
											onPress: () =>
												remove.mutate(user.id, {
													onError: () =>
														Alert.alert(t("admin.users"), errorLabel),
												}),
										},
									])
								}
							>
								<Text style={{ color: colors.danger }}>{deleteLabel}</Text>
							</Pressable>
						)}
					</View>
				);
			})}
		</View>
	);
}

const styles = StyleSheet.create({
	row: { flexDirection: "row", alignItems: "center" },
});
