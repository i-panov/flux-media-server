import { router } from "expo-router";
import {
	ActivityIndicator,
	FlatList,
	Pressable,
	Text,
	useWindowDimensions,
} from "react-native";
import { useWorks, type WorkKind } from "../api/catalog";
import { EmptyState } from "../components/EmptyState";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { isTV } from "../tv/profile";
import { CatalogCard } from "./CatalogCard";
import { catalogCardWidth, catalogColumns, catalogPadding } from "./grid";

// Список произведений одного типа: используется и отдельными экранами,
// и вкладками видео-раздела.
export function WorksList({
	kind,
	tagIDs = [],
}: {
	kind: WorkKind;
	tagIDs?: number[];
}) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const works = useWorks(kind, tagIDs);
	const { width } = useWindowDimensions();
	const columns = catalogColumns(width);
	// Отступы берём те же, что Screen: на TV они больше, иначе строка
	// шире контента и правая карточка обрезается.
	const padding = catalogPadding(isTV);
	const cardWidth = catalogCardWidth(width, columns, padding, spacing.md);
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
			key={`works-${columns}`}
			data={works.data ?? []}
			keyExtractor={(work) => String(work.id)}
			numColumns={columns}
			style={{ flex: 1 }}
			contentContainerStyle={{ gap: spacing.md, paddingBottom: spacing.lg }}
			columnWrapperStyle={{ gap: spacing.md }}
			renderItem={({ item: work }) => (
				<CatalogCard
					style={{ width: cardWidth }}
					id={work.id}
					title={work.title}
					coverURL={work.cover_url}
					icon={work.kind === "series" ? "tv" : "film"}
					testID={`work-card-${work.id}`}
					onPress={() => router.push(`/series/${work.id}`)}
				/>
			)}
		/>
	);
}
