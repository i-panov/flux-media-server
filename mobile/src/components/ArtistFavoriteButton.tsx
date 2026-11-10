import Ionicons from "@expo/vector-icons/Ionicons";
import { Pressable, StyleSheet } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface ArtistFavoriteButtonProps {
	artistName: string;
	active: boolean;
	disabled?: boolean;
	/** База testID: к ней добавляется -on/-off/-disabled. */
	testID: string;
	onPress: () => void;
}

// Сердечко артиста: общее для списка и экрана артиста, чтобы разметка,
// размер тапа и a11y-состояние не расходились.
export function ArtistFavoriteButton({
	artistName,
	active,
	disabled = false,
	testID,
	onPress,
}: ArtistFavoriteButtonProps) {
	useLanguage();
	const { colors } = useTheme();
	const label = active ? t("media.unfavorite") : t("media.favorite");
	// Пока избранное грузится/переключается, отдельный testID не даёт
	// Maestro нажать кнопку раньше, чем она станет активной.
	const state = disabled ? "disabled" : active ? "on" : "off";

	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={`${label}: ${artistName}`}
			accessibilityState={{ disabled, selected: active }}
			disabled={disabled}
			onPress={onPress}
			testID={`${testID}-${state}`}
			hitSlop={4}
			style={({ pressed }) => [
				styles.button,
				disabled && styles.disabled,
				pressed && styles.pressed,
			]}
		>
			<Ionicons
				name={active ? "heart" : "heart-outline"}
				size={22}
				color={active ? colors.favorite : colors.textMuted}
			/>
		</Pressable>
	);
}

const styles = StyleSheet.create({
	button: {
		width: 44,
		height: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	disabled: { opacity: 0.5 },
	pressed: { opacity: 0.7 },
});
