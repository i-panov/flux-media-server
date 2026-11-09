import Ionicons from "@expo/vector-icons/Ionicons";
import { Tabs } from "expo-router";
import type { ComponentProps } from "react";
import type { ColorValue } from "react-native";
import { AuthGate } from "../../src/components/AuthGate";
import { t, useLanguage } from "../../src/i18n";
import { useTheme } from "../../src/theme/ThemeProvider";

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
					name="library"
					options={{
						title: t("library.title"),
						tabBarButtonTestID: "tab-library",
						tabBarIcon: ({ color, size, focused }) => (
							<TabIcon
								name={focused ? "library" : "library-outline"}
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
