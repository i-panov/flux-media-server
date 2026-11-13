import Ionicons from "@expo/vector-icons/Ionicons";
import { BottomTabBar, Tabs } from "expo-router/js-tabs";
import type { ComponentProps } from "react";
import { type ColorValue, View } from "react-native";
import { AuthGate } from "../../src/components/AuthGate";
import { t, useLanguage } from "../../src/i18n";
import { AudioBar } from "../../src/player/AudioBar";
import { useTheme } from "../../src/theme/ThemeProvider";
import { isTV } from "../../src/tv/profile";

type IoniconName = ComponentProps<typeof Ionicons>["name"];

function TabIcon({
	name,
	color,
	size,
}: {
	name: IoniconName;
	color: ColorValue;
	size: number;
}) {
	// ColorValue включает number (нативные цвета), а Ionicons принимает
	// string | OpaqueColorValue; null означает дефолтный цвет.
	const iconColor = typeof color === "number" ? undefined : color;
	return <Ionicons name={name} size={size} color={iconColor ?? undefined} />;
}

export default function TabsLayout() {
	useLanguage();
	const { colors } = useTheme();
	return (
		<AuthGate>
			<Tabs
				// Мини-бар — часть таб-бара, а не absolute-оверлей: высота
				// экрана сама уменьшается, список не перекрывается, а safe
				// area снизу остаётся у BottomTabBar.
				tabBar={(props) => (
					<View style={{ backgroundColor: colors.surface }}>
						<AudioBar />
						<BottomTabBar {...props} />
					</View>
				)}
				screenOptions={{
					headerShown: false,
					tabBarActiveTintColor: colors.accent,
					tabBarInactiveTintColor: colors.textMuted,
					tabBarStyle: {
						backgroundColor: colors.surface,
						borderTopColor: colors.border,
					},
					sceneStyle: { backgroundColor: colors.background },
				}}
			>
				<Tabs.Screen
					name="video"
					options={{
						title: t("video.title"),
						tabBarButtonTestID: "tab-video",
						tabBarIcon: ({ color, size, focused }) => (
							<TabIcon
								name={focused ? "videocam" : "videocam-outline"}
								color={color}
								size={size}
							/>
						),
					}}
				/>
				<Tabs.Screen
					name="audio"
					options={{
						title: t("audio.title"),
						tabBarButtonTestID: "tab-audio",
						tabBarIcon: ({ color, size, focused }) => (
							<TabIcon
								name={focused ? "musical-notes" : "musical-notes-outline"}
								color={color}
								size={size}
							/>
						),
					}}
				/>
				<Tabs.Screen
					name="memes"
					options={{
						// На TV маршрут остаётся в дереве Expo Router, но не
						// попадает в таб-бар; экран дополнительно редиректит.
						href: isTV ? null : undefined,
						title: t("memes.title"),
						tabBarButtonTestID: "tab-memes",
						tabBarIcon: ({ color, size, focused }) => (
							<TabIcon
								name={focused ? "images" : "images-outline"}
								color={color}
								size={size}
							/>
						),
					}}
				/>

				<Tabs.Screen
					name="settings"
					options={{
						title: t("settings.title"),
						tabBarButtonTestID: "tab-settings",
						tabBarIcon: ({ color, size, focused }) => (
							<TabIcon
								name={focused ? "settings" : "settings-outline"}
								color={color}
								size={size}
							/>
						),
					}}
				/>
			</Tabs>
		</AuthGate>
	);
}
