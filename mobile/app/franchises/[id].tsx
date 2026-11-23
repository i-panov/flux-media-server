import { router, useLocalSearchParams } from "expo-router";
import { useState } from "react";
import { ActivityIndicator, Pressable, Text, View } from "react-native";
import { useFranchise } from "../../src/api/catalog";
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

export default function FranchiseDetailScreen() {
	return (
		<AuthGate>
			<FranchiseDetailContent />
		</AuthGate>
	);
}

function FranchiseDetailContent() {
	useLanguage();
	const params = useLocalSearchParams<{ id?: string | string[] }>();
	const raw = Array.isArray(params.id) ? params.id[0] : params.id;
	const parsed = parseCatalogID(raw);
	const valid = parsed !== null;
	const numeric = parsed ?? 0;
	const franchise = useFranchise(numeric, valid);
	const session = useSession();
	const [tagsOpen, setTagsOpen] = useState(false);
	const { colors, spacing } = useTheme();
	const data = franchise.data;
	const entries = (data?.entries ?? []).filter(
		(entry) => entry.work != null || entry.media_id != null,
	);
	if (!valid) {
		return (
			<Screen scroll>
				<CatalogHeader
					title={t("catalog.franchises")}
					onBack={() => router.replace("/franchises")}
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
				title={data?.name ?? t("catalog.franchises")}
				onBack={() => router.replace("/franchises")}
			/>
			{session.data?.is_admin === true && (
				<View style={{ flexDirection: "row", gap: spacing.md }}>
					<Pressable
						onPress={() =>
							router.push(`/catalog-admin?kind=franchise&id=${numeric}`)
						}
					>
						<Text style={{ color: colors.accent, fontWeight: "600" }}>
							{t("catalog.adminTitle")}
						</Text>
					</Pressable>
					<Pressable onPress={() => setTagsOpen(true)} testID="franchise-tags">
						<Text style={{ color: colors.accent, fontWeight: "600" }}>
							{t("tags.title")}
						</Text>
					</Pressable>
				</View>
			)}
			{tagsOpen && (
				<TagsSheet
					entity="franchise"
					id={numeric}
					title={data?.name ?? ""}
					onClose={() => setTagsOpen(false)}
				/>
			)}
			{franchise.isPending ? (
				<ActivityIndicator color={colors.accent} />
			) : franchise.isError || !data ? (
				<ErrorState
					title={t("catalog.loadError")}
					onRetry={() => void franchise.refetch()}
				/>
			) : entries.length === 0 ? (
				<EmptyState title={t("catalog.emptyFranchise")} icon="film-outline" />
			) : (
				entries.map((entry) => {
					const title =
						entry.work?.title || entry.media?.title || `#${entry.id}`;
					return (
						<Pressable
							key={entry.id}
							accessibilityRole="button"
							accessibilityLabel={title}
							onPress={() => {
								if (entry.work) router.push(`/series/${entry.work.id}`);
								else if (entry.media_id)
									router.push(`/video/${entry.media_id}`);
							}}
							style={{
								padding: spacing.md,
								backgroundColor: colors.surface,
								borderRadius: 10,
							}}
						>
							<Text style={{ color: colors.text, fontWeight: "600" }}>
								{title}
							</Text>
							<Text style={{ color: colors.textMuted, fontSize: 12 }}>
								{entry.work?.kind === "series"
									? t("catalog.seriesOne")
									: entry.work
										? t("catalog.filmSeries")
										: t("catalog.movie")}
							</Text>
						</Pressable>
					);
				})
			)}
		</Screen>
	);
}
