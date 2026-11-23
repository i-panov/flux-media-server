import { router, useLocalSearchParams } from "expo-router";
import { useState } from "react";
import { ActivityIndicator, Pressable, Text, View } from "react-native";
import { useWork } from "../../src/api/catalog";
import { useSession } from "../../src/auth/session";
import { CatalogHeader } from "../../src/catalog/CatalogHeader";
import { parseCatalogID } from "../../src/catalog/catalogView";
import { AuthGate } from "../../src/components/AuthGate";
import { EmptyState } from "../../src/components/EmptyState";
import { ErrorState } from "../../src/components/ErrorState";
import { Screen } from "../../src/components/Screen";
import { TagsSheet } from "../../src/components/TagsSheet";
import { t, useLanguage } from "../../src/i18n";
import { useTheme } from "../../src/theme/ThemeProvider";

export default function SeriesDetailScreen() {
	return (
		<AuthGate>
			<SeriesDetailContent />
		</AuthGate>
	);
}

function SeriesDetailContent() {
	useLanguage();
	const params = useLocalSearchParams<{ id?: string | string[] }>();
	const raw = Array.isArray(params.id) ? params.id[0] : params.id;
	const parsed = parseCatalogID(raw);
	const valid = parsed !== null;
	const numeric = parsed ?? 0;
	const work = useWork(numeric, valid);
	const session = useSession();
	const [tagsOpen, setTagsOpen] = useState(false);
	const { colors, spacing } = useTheme();
	const data = work.data;
	if (!valid) {
		return (
			<Screen scroll>
				<CatalogHeader
					title={t("catalog.series")}
					onBack={() => router.replace("/series")}
				/>
				<EmptyState
					title={t("video.notFound")}
					description={t("video.notFoundDescription")}
				/>
			</Screen>
		);
	}
	return (
		<Screen scroll>
			<CatalogHeader
				title={data?.title ?? t("catalog.series")}
				onBack={() => router.replace("/series")}
			/>
			{session.data?.is_admin === true && (
				<View style={{ flexDirection: "row", gap: spacing.md }}>
					<Pressable
						onPress={() =>
							router.push(`/catalog-admin?kind=work&id=${numeric}`)
						}
					>
						<Text style={{ color: colors.accent, fontWeight: "600" }}>
							{t("catalog.adminTitle")}
						</Text>
					</Pressable>
					<Pressable onPress={() => setTagsOpen(true)} testID="work-tags">
						<Text style={{ color: colors.accent, fontWeight: "600" }}>
							{t("tags.title")}
						</Text>
					</Pressable>
				</View>
			)}
			{tagsOpen && (
				<TagsSheet
					entity="work"
					id={numeric}
					title={data?.title ?? ""}
					onClose={() => setTagsOpen(false)}
				/>
			)}
			{work.isPending ? (
				<ActivityIndicator color={colors.accent} />
			) : work.isError || !data ? (
				<ErrorState
					title={t("catalog.loadError")}
					onRetry={() => void work.refetch()}
				/>
			) : data.kind === "film_series" ? (
				(data.items ?? []).length === 0 ? (
					<EmptyState title={t("catalog.noFilms")} icon="film-outline" />
				) : (
					(data.items ?? []).map((item) => (
						<Pressable
							key={item.id}
							accessibilityRole="button"
							accessibilityLabel={item.media?.title ?? `#${item.media_id}`}
							onPress={() => router.push(`/video/${item.media_id}`)}
							style={{
								padding: spacing.md,
								backgroundColor: colors.surface,
								borderRadius: 10,
							}}
						>
							<Text style={{ color: colors.text, fontWeight: "600" }}>
								{item.media?.title || `#${item.media_id}`}
							</Text>
						</Pressable>
					))
				)
			) : (data.seasons ?? []).length === 0 ? (
				<EmptyState title={t("catalog.noSeasons")} icon="albums-outline" />
			) : (
				data.seasons?.map((season) => (
					<View key={season.id} style={{ gap: spacing.sm }}>
						<Text
							style={{ color: colors.text, fontSize: 17, fontWeight: "700" }}
						>
							{season.title ||
								t("catalog.season", { number: season.season_number })}
						</Text>
						{(season.items ?? []).length === 0 ? (
							<Text style={{ color: colors.textMuted }}>
								{t("catalog.noEpisodes")}
							</Text>
						) : (
							season.items?.map((item) => (
								<Pressable
									key={item.id}
									accessibilityRole="button"
									accessibilityLabel={item.media?.title ?? `#${item.media_id}`}
									onPress={() => router.push(`/video/${item.media_id}`)}
									style={{
										padding: spacing.md,
										backgroundColor: colors.surface,
										borderRadius: 10,
									}}
								>
									<Text style={{ color: colors.text, fontWeight: "600" }}>
										{item.episode_number == null
											? ""
											: `${item.episode_number}. `}
										{item.media?.title || `#${item.media_id}`}
									</Text>
								</Pressable>
							))
						)}
					</View>
				))
			)}
		</Screen>
	);
}
