import type { ReactNode } from "react";
import {
	ScrollView,
	type StyleProp,
	StyleSheet,
	View,
	type ViewStyle,
} from "react-native";
import { type Edge, SafeAreaView } from "react-native-safe-area-context";
import { useTheme } from "../theme/ThemeProvider";
import { isTV } from "../tv/profile";

interface ScreenProps {
	children: ReactNode;
	testID?: string;
	/** Прокручиваемый экран (настройки, формы); по умолчанию — обычный View. */
	scroll?: boolean;
	edges?: readonly Edge[];
	style?: StyleProp<ViewStyle>;
	contentContainerStyle?: StyleProp<ViewStyle>;
}

// Общая обёртка экрана: фон темы, safe area и единые отступы. Экраны со
// списками передают scroll={false} и держат FlatList дочерним элементом.
export function Screen({
	children,
	testID,
	scroll = false,
	edges = ["top"],
	style,
	contentContainerStyle,
}: ScreenProps) {
	const { colors, spacing } = useTheme();
	// 10-foot UI: на ТВ больше воздуха и крупнее базовый отступ.
	const padding: ViewStyle = isTV
		? { padding: spacing.xl, gap: spacing.lg }
		: { padding: spacing.lg, gap: spacing.md };

	return (
		<SafeAreaView
			style={[styles.safe, { backgroundColor: colors.background }]}
			edges={edges}
			testID={testID}
		>
			{scroll ? (
				<ScrollView
					style={style}
					contentContainerStyle={[padding, contentContainerStyle]}
					keyboardShouldPersistTaps="handled"
				>
					{children}
				</ScrollView>
			) : (
				<View style={[styles.fill, padding, style, contentContainerStyle]}>
					{children}
				</View>
			)}
		</SafeAreaView>
	);
}

const styles = StyleSheet.create({
	safe: { flex: 1 },
	fill: { flex: 1 },
});
