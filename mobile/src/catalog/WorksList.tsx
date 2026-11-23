import { router } from "expo-router";
import { ActivityIndicator, Pressable, Text, View } from "react-native";
import { useWorks, type WorkKind } from "../api/catalog";
import { EmptyState } from "../components/EmptyState";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { CatalogCard } from "./CatalogCard";

// Список произведений одного типа: используется и отдельными экранами,
// и вкладками видео-раздела.
export function WorksList({ kind }: { kind: WorkKind }) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const works = useWorks(kind);
	if (works.isPending) {
		return <ActivityIndicator color={colors.accent} />;
	}
	if (works.isError) {
		return (
			<Pressable onPress={() => void works.refetch()}>
				<Text style={{ color: colors.danger }}>
					{t("catalog.loadError")} · {t("common.retry")}
				</Text>
			</Pressable>
		);
	}
	if ((works.data ?? []).length === 0) {
		return (
			<EmptyState
				title={
					kind === "series"
						? t("catalog.emptySeries")
						: t("catalog.emptyFilmSeries")
				}
				icon={kind === "series" ? "tv-outline" : "film-outline"}
			/>
		);
	}
	return (
		<View style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.md }}>
			{works.data?.map((work) => (
				<CatalogCard
					key={work.id}
					id={work.id}
					title={work.title}
					coverURL={work.cover_url}
					icon={work.kind === "series" ? "tv" : "film"}
					testID={`work-card-${work.id}`}
					onPress={() => router.push(`/series/${work.id}`)}
				/>
			))}
		</View>
	);
}
