import { router } from "expo-router";
import {
	ActivityIndicator,
	FlatList,
	Pressable,
	Text,
	useWindowDimensions,
	View,
} from "react-native";
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
	const { width } = useWindowDimensions();
	// Телефон — 2 колонки, планшет — 3, ТВ/широкий экран — 4: карточки
	// тянутся по ширине, а не висят по 160 dp с пустым полем.
	const columns = width >= 900 ? 4 : width >= 600 ? 3 : 2;
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
		<FlatList
			data={works.data ?? []}
			keyExtractor={(work) => String(work.id)}
			numColumns={columns}
			style={{ flex: 1 }}
			contentContainerStyle={{ gap: spacing.md, paddingBottom: spacing.lg }}
			columnWrapperStyle={{ gap: spacing.md }}
			renderItem={({ item: work }) => (
				<View style={{ flex: 1 }}>
					<CatalogCard
						style={{ width: "100%" }}
						id={work.id}
						title={work.title}
						coverURL={work.cover_url}
						icon={work.kind === "series" ? "tv" : "film"}
						testID={`work-card-${work.id}`}
						onPress={() => router.push(`/series/${work.id}`)}
					/>
				</View>
			)}
		/>
	);
}
