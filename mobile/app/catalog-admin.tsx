/* eslint-disable max-lines-per-function, max-lines */
import Ionicons from "@expo/vector-icons/Ionicons";
import { router, useLocalSearchParams } from "expo-router";
import { useState } from "react";
import {
	ActivityIndicator,
	Alert,
	Modal,
	Pressable,
	ScrollView,
	Text,
	TextInput,
	View,
} from "react-native";
import {
	useAddEpisode,
	useAddFilm,
	useAddFranchiseEntry,
	useCreateSeason,
	useDeleteFranchise,
	useDeleteSeason,
	useDeleteWork,
	useFranchise,
	useRemoveEpisode,
	useRemoveFilm,
	useRemoveFranchiseEntry,
	useReorderEpisodes,
	useReorderFilms,
	useReorderFranchiseEntries,
	useReorderSeasons,
	useUpdateFranchise,
	useUpdateWork,
	useWork,
	useWorks,
} from "../src/api/catalog";
import { useSession } from "../src/auth/session";
import { CatalogHeader } from "../src/catalog/CatalogHeader";
import { parseCatalogID } from "../src/catalog/catalogView";
import { MediaPickerModal } from "../src/catalog/MediaPickerModal";
import { ReorderModal } from "../src/catalog/ReorderModal";
import { AuthGate } from "../src/components/AuthGate";
import { Screen } from "../src/components/Screen";
import { t } from "../src/i18n";
import { useTheme } from "../src/theme/ThemeProvider";

type Picker = "episode" | "film" | "work" | "media" | null;

export default function CatalogAdminScreen() {
	return (
		<AuthGate>
			<CatalogAdminContent />
		</AuthGate>
	);
}

// null — поле не трогали; пустая строка — осознанная очистка.
function editedValue<T>(value: T | null, original: T): T {
	return value === null ? original : value;
}

function yearFieldValue(value: string | null, original: number): string {
	if (value !== null) {
		return value;
	}
	return original > 0 ? String(original) : "";
}

function parseYearValue(value: string | null, original: number): number {
	const parsed = value === null ? original : Number(value);
	return Number.isFinite(parsed) ? parsed : 0;
}

function CatalogAdminContent() {
	const params = useLocalSearchParams<{ kind?: string; id?: string }>();
	const kind = params.kind === "franchise" ? "franchise" : "work";
	const id = parseCatalogID(params.id) ?? 0;
	const session = useSession();
	const { colors, spacing } = useTheme();
	const work = useWork(kind === "work" ? id : 0, kind === "work");
	const franchise = useFranchise(
		kind === "franchise" ? id : 0,
		kind === "franchise",
	);
	const works = useWorks("series");
	const films = useWorks("film_series");
	const updateWork = useUpdateWork();
	const deleteWork = useDeleteWork();
	const updateFranchise = useUpdateFranchise();
	const deleteFranchise = useDeleteFranchise();
	const createSeason = useCreateSeason();
	const deleteSeason = useDeleteSeason();
	const addEpisode = useAddEpisode();
	const removeEpisode = useRemoveEpisode();
	const reorderEpisodes = useReorderEpisodes();
	const reorderFilms = useReorderFilms();
	const reorderSeasons = useReorderSeasons();
	const addFilm = useAddFilm();
	const removeFilm = useRemoveFilm();
	const addEntry = useAddFranchiseEntry();
	const removeEntry = useRemoveFranchiseEntry();
	const reorderEntries = useReorderFranchiseEntries();
	const [title, setTitle] = useState("");
	// null — «не трогали», пустая строка — осознанная очистка.
	const [description, setDescription] = useState<string | null>(null);
	const [coverURL, setCoverURL] = useState<string | null>(null);
	const [year, setYear] = useState<string | null>(null);
	const [picker, setPicker] = useState<Picker>(null);
	const [pickerSeason, setPickerSeason] = useState<number | null>(null);
	const [sortKind, setSortKind] = useState<
		"seasons" | "episodes" | "films" | null
	>(null);
	const [sortSeason, setSortSeason] = useState<number | null>(null);
	const [franchiseSort, setFranchiseSort] = useState(false);

	if (session.data?.is_admin !== true) {
		return (
			<Screen>
				<CatalogHeader
					title={t("catalog.adminTitle")}
					onBack={() => router.back()}
				/>
				<Text style={{ color: colors.danger }}>{t("catalog.adminOnly")}</Text>
			</Screen>
		);
	}

	const confirm = (message: string, action: () => void) => {
		Alert.alert(t("catalog.confirmDelete"), message, [
			{ text: t("common.cancel"), style: "cancel" },
			{
				text: t("catalog.confirmDelete"),
				style: "destructive",
				onPress: action,
			},
		]);
	};
	const run = async (action: () => Promise<unknown>) => {
		try {
			await action();
		} catch (error) {
			Alert.alert(
				t("common.error"),
				error instanceof Error ? error.message : "",
			);
		}
	};
	const move = <T,>(rows: T[], index: number, direction: -1 | 1): T[] => {
		const next = [...rows];
		const target = index + direction;
		if (target < 0 || target >= next.length) return rows;
		[next[index], next[target]] = [next[target], next[index]];
		return next;
	};
	const allWorks = [...(works.data ?? []), ...(films.data ?? [])];
	const deleteItemConfirm = t("catalog.deleteItemConfirm");
	const sortLabel = t("catalog.sort");
	const handleMedia = (mediaID: number) =>
		void run(async () => {
			if (picker === "film" && work.data) {
				await addFilm.mutateAsync({ workID: work.data.id, mediaID });
			} else if (picker === "episode" && pickerSeason !== null) {
				await addEpisode.mutateAsync({ seasonID: pickerSeason, mediaID });
			} else if (picker === "media" && franchise.data) {
				await addEntry.mutateAsync({ franchiseID: franchise.data.id, mediaID });
			}
			setPicker(null);
		});

	if (kind === "work") {
		const data = work.data;
		if (work.isPending)
			return (
				<Screen>
					<ActivityIndicator color={colors.accent} />
				</Screen>
			);
		if (!data)
			return (
				<Screen>
					<Text style={{ color: colors.danger }}>{t("catalog.loadError")}</Text>
				</Screen>
			);
		return (
			<Screen scroll>
				<CatalogHeader title={data.title} onBack={() => router.back()} />
				<TextInput
					style={{
						color: colors.text,
						borderColor: colors.border,
						borderWidth: 1,
						borderRadius: 8,
						padding: spacing.sm,
					}}
					value={title || data.title}
					onChangeText={setTitle}
					placeholder={t("catalog.adminTitle")}
				/>
				<TextInput
					style={{
						color: colors.text,
						borderColor: colors.border,
						borderWidth: 1,
						borderRadius: 8,
						padding: spacing.sm,
					}}
					value={editedValue(description, data.description)}
					onChangeText={setDescription}
					placeholder={t("catalog.description")}
					multiline
				/>
				<TextInput
					style={{
						color: colors.text,
						borderColor: colors.border,
						borderWidth: 1,
						borderRadius: 8,
						padding: spacing.sm,
					}}
					value={editedValue(coverURL, data.cover_url)}
					onChangeText={setCoverURL}
					placeholder={t("catalog.coverUrl")}
					autoCapitalize="none"
					autoCorrect={false}
				/>
				<TextInput
					style={{
						color: colors.text,
						borderColor: colors.border,
						borderWidth: 1,
						borderRadius: 8,
						padding: spacing.sm,
					}}
					value={yearFieldValue(year, data.year)}
					onChangeText={setYear}
					placeholder={t("catalog.year")}
					keyboardType="number-pad"
				/>
				<View style={{ flexDirection: "row", gap: spacing.md }}>
					<Pressable
						onPress={() =>
							void run(() =>
								updateWork.mutateAsync({
									id: data.id,
									title: (title || data.title).trim(),
									description: editedValue(
										description,
										data.description,
									).trim(),
									cover_url: editedValue(coverURL, data.cover_url).trim(),
									year: parseYearValue(year, data.year),
								}),
							)
						}
					>
						<Text style={{ color: colors.accent }}>{t("common.save")}</Text>
					</Pressable>
					<Pressable
						onPress={() =>
							confirm(
								deleteItemConfirm,
								() =>
									void run(async () => {
										await deleteWork.mutateAsync(data.id);
										router.dismissAll();
										router.replace("/series");
									}),
							)
						}
					>
						<Text style={{ color: colors.danger }}>
							{t("catalog.adminDelete")}
						</Text>
					</Pressable>
				</View>
				{data.kind === "series" ? (
					<>
						<View style={{ flexDirection: "row", gap: spacing.md }}>
							<Pressable
								onPress={() =>
									void run(() =>
										createSeason.mutateAsync({
											workID: data.id,
											seasonNumber:
												Math.max(
													0,
													...(data.seasons ?? []).map((s) => s.season_number),
												) + 1,
										}),
									)
								}
							>
								<Text style={{ color: colors.accent }}>
									{t("catalog.adminAddSeason")}
								</Text>
							</Pressable>
							<Pressable onPress={() => setSortKind("seasons")}>
								<Text style={{ color: colors.accent }}>{sortLabel}</Text>
							</Pressable>
						</View>
						{(data.seasons ?? []).map((season, index) => (
							<View
								key={season.id}
								style={{
									gap: spacing.xs,
									borderBottomWidth: 1,
									borderColor: colors.border,
									paddingBottom: spacing.sm,
								}}
							>
								<View
									style={{
										flexDirection: "row",
										alignItems: "center",
										gap: spacing.xs,
									}}
								>
									<Text
										style={{ color: colors.text, fontWeight: "700", flex: 1 }}
									>
										{season.title ||
											t("catalog.season", { number: season.season_number })}
									</Text>
									<Pressable
										disabled={index === 0}
										onPress={() => {
											const rows = data.seasons ?? [];
											const next = move(rows, index, -1);
											if (next !== rows)
												void run(() =>
													reorderSeasons.mutateAsync({
														workID: data.id,
														ids: next.map((s) => s.id),
													}),
												);
										}}
									>
										<Ionicons
											name="chevron-up"
											size={20}
											color={index === 0 ? colors.border : colors.text}
										/>
									</Pressable>
									<Pressable
										disabled={index === (data.seasons?.length ?? 1) - 1}
										onPress={() => {
											const rows = data.seasons ?? [];
											const next = move(rows, index, 1);
											if (next !== rows) {
												// порядок сезонов: отдельный endpoint
												void run(() =>
													reorderSeasons.mutateAsync({
														workID: data.id,
														ids: next.map((s) => s.id),
													}),
												);
											}
										}}
									>
										<Ionicons
											name="chevron-down"
											size={20}
											color={colors.text}
										/>
									</Pressable>
									<Pressable
										disabled={(data.seasons?.length ?? 0) <= 1}
										onPress={() =>
											confirm(
												t("catalog.deleteSeasonConfirm"),
												() =>
													void run(() => deleteSeason.mutateAsync(season.id)),
											)
										}
									>
										<Ionicons
											name="trash-outline"
											size={20}
											color={colors.danger}
										/>
									</Pressable>
								</View>
								<View style={{ flexDirection: "row", gap: spacing.md }}>
									<Pressable
										onPress={() => {
											setPickerSeason(season.id);
											setPicker("episode");
										}}
									>
										<Text style={{ color: colors.accent }}>
											{t("catalog.adminAddEpisode")}
										</Text>
									</Pressable>
									<Pressable
										onPress={() => {
											setSortSeason(season.id);
											setSortKind("episodes");
										}}
									>
										<Text style={{ color: colors.accent }}>{sortLabel}</Text>
									</Pressable>
								</View>
								{(season.items ?? []).map((item, itemIndex) => (
									<View
										key={item.id}
										style={{
											flexDirection: "row",
											alignItems: "center",
											gap: spacing.xs,
										}}
									>
										<Text style={{ color: colors.text, flex: 1 }}>
											{item.media?.title || `#${item.media_id}`}
										</Text>
										<Pressable
											disabled={itemIndex === 0}
											onPress={() => {
												const rows = season.items ?? [];
												const next = move(rows, itemIndex, -1);
												if (next !== rows)
													void run(() =>
														reorderEpisodes.mutateAsync({
															seasonID: season.id,
															ids: next.map((i) => i.id),
														}),
													);
											}}
										>
											<Ionicons
												name="chevron-up"
												size={18}
												color={itemIndex === 0 ? colors.border : colors.text}
											/>
										</Pressable>
										<Pressable
											onPress={() =>
												confirm(
													deleteItemConfirm,
													() =>
														void run(() =>
															removeEpisode.mutateAsync({
																seasonID: season.id,
																mediaID: item.media_id,
															}),
														),
												)
											}
										>
											<Ionicons name="close" size={18} color={colors.danger} />
										</Pressable>
									</View>
								))}
							</View>
						))}
					</>
				) : (
					<>
						<View style={{ flexDirection: "row", gap: spacing.md }}>
							<Pressable onPress={() => setPicker("film")}>
								<Text style={{ color: colors.accent }}>
									{t("catalog.adminAddFilm")}
								</Text>
							</Pressable>
							<Pressable onPress={() => setSortKind("films")}>
								<Text style={{ color: colors.accent }}>{sortLabel}</Text>
							</Pressable>
						</View>
						{(data.items ?? []).map((item, index) => (
							<View
								key={item.id}
								style={{ flexDirection: "row", alignItems: "center" }}
							>
								<Text style={{ color: colors.text, flex: 1 }}>
									{item.media?.title || `#${item.media_id}`}
								</Text>
								<Pressable
									disabled={index === 0}
									onPress={() => {
										const rows = data.items ?? [];
										const next = move(rows, index, -1);
										if (next !== rows) {
											void run(() =>
												reorderFilms.mutateAsync({
													workID: data.id,
													ids: next.map((i) => i.id),
												}),
											);
										}
									}}
								>
									<Ionicons
										name="chevron-up"
										size={18}
										color={index === 0 ? colors.border : colors.text}
									/>
								</Pressable>
								<Pressable
									onPress={() =>
										confirm(
											deleteItemConfirm,
											() =>
												void run(() =>
													removeFilm.mutateAsync({
														workID: data.id,
														mediaID: item.media_id,
													}),
												),
										)
									}
								>
									<Ionicons name="close" size={18} color={colors.danger} />
								</Pressable>
							</View>
						))}
					</>
				)}
				<ReorderModal
					visible={sortKind !== null}
					title={sortLabel}
					rows={
						sortKind === "seasons"
							? (data.seasons ?? []).map((season) => ({
									id: season.id,
									label:
										season.title ||
										t("catalog.season", { number: season.season_number }),
								}))
							: sortKind === "films"
								? (data.items ?? []).map((item) => ({
										id: item.id,
										label: item.media?.title || `#${item.media_id}`,
									}))
								: (
										data.seasons?.find((season) => season.id === sortSeason)
											?.items ?? []
									).map((item) => ({
										id: item.id,
										label: item.media?.title || `#${item.media_id}`,
									}))
					}
					onClose={() => setSortKind(null)}
					onSave={(ids) => {
						if (sortKind === "seasons") {
							void run(() =>
								reorderSeasons.mutateAsync({ workID: data.id, ids }),
							);
						} else if (sortKind === "films") {
							void run(() =>
								reorderFilms.mutateAsync({ workID: data.id, ids }),
							);
						} else if (sortSeason !== null) {
							void run(() =>
								reorderEpisodes.mutateAsync({ seasonID: sortSeason, ids }),
							);
						}
					}}
				/>
				<MediaPickerModal
					visible={picker === "episode" || picker === "film"}
					title={
						picker === "film"
							? t("catalog.adminAddFilm")
							: t("catalog.adminAddEpisode")
					}
					onClose={() => setPicker(null)}
					onSelect={handleMedia}
				/>
			</Screen>
		);
	}

	const data = franchise.data;
	if (franchise.isPending)
		return (
			<Screen>
				<ActivityIndicator color={colors.accent} />
			</Screen>
		);
	if (!data)
		return (
			<Screen>
				<Text style={{ color: colors.danger }}>{t("catalog.loadError")}</Text>
			</Screen>
		);
	return (
		<Screen scroll>
			<CatalogHeader title={data.name} onBack={() => router.back()} />
			<TextInput
				style={{
					color: colors.text,
					borderColor: colors.border,
					borderWidth: 1,
					borderRadius: 8,
					padding: spacing.sm,
				}}
				value={title || data.name}
				onChangeText={setTitle}
				placeholder={t("catalog.newFranchise")}
			/>
			<TextInput
				style={{
					color: colors.text,
					borderColor: colors.border,
					borderWidth: 1,
					borderRadius: 8,
					padding: spacing.sm,
				}}
				value={editedValue(description, data.description)}
				onChangeText={setDescription}
				placeholder={t("catalog.description")}
				multiline
			/>
			<TextInput
				style={{
					color: colors.text,
					borderColor: colors.border,
					borderWidth: 1,
					borderRadius: 8,
					padding: spacing.sm,
				}}
				value={editedValue(coverURL, data.cover_url)}
				onChangeText={setCoverURL}
				placeholder={t("catalog.coverUrl")}
				autoCapitalize="none"
				autoCorrect={false}
			/>
			<View style={{ flexDirection: "row", gap: spacing.md }}>
				<Pressable
					onPress={() =>
						void run(() =>
							updateFranchise.mutateAsync({
								id: data.id,
								name: (title || data.name).trim(),
								description: editedValue(description, data.description).trim(),
								cover_url: editedValue(coverURL, data.cover_url).trim(),
							}),
						)
					}
				>
					<Text style={{ color: colors.accent }}>{t("common.save")}</Text>
				</Pressable>
				<Pressable
					onPress={() =>
						confirm(
							deleteItemConfirm,
							() =>
								void run(async () => {
									await deleteFranchise.mutateAsync(data.id);
									router.dismissAll();
									router.replace("/franchises");
								}),
						)
					}
				>
					<Text style={{ color: colors.danger }}>
						{t("catalog.adminDelete")}
					</Text>
				</Pressable>
			</View>
			<View style={{ flexDirection: "row", gap: spacing.md }}>
				<Pressable onPress={() => setPicker("work")}>
					<Text style={{ color: colors.accent }}>
						{t("catalog.adminAddEntry")}
					</Text>
				</Pressable>
				<Pressable onPress={() => setFranchiseSort(true)}>
					<Text style={{ color: colors.accent }}>{sortLabel}</Text>
				</Pressable>
			</View>
			{(data.entries ?? []).map((entry, index) => {
				const label = entry.work?.title || entry.media?.title || `#${entry.id}`;
				return (
					<View
						key={entry.id}
						style={{ flexDirection: "row", alignItems: "center" }}
					>
						<Text style={{ color: colors.text, flex: 1 }}>{label}</Text>
						<Pressable
							disabled={index === 0}
							onPress={() => {
								const rows = data.entries ?? [];
								const next = move(rows, index, -1);
								if (next !== rows)
									void run(() =>
										reorderEntries.mutateAsync({
											franchiseID: data.id,
											ids: next.map((e) => e.id),
										}),
									);
							}}
						>
							<Ionicons
								name="chevron-up"
								size={18}
								color={index === 0 ? colors.border : colors.text}
							/>
						</Pressable>
						<Pressable
							onPress={() =>
								confirm(
									deleteItemConfirm,
									() =>
										void run(() =>
											removeEntry.mutateAsync({
												franchiseID: data.id,
												entryID: entry.id,
											}),
										),
								)
							}
						>
							<Ionicons name="close" size={18} color={colors.danger} />
						</Pressable>
					</View>
				);
			})}
			<Modal
				visible={picker === "work"}
				transparent
				animationType="fade"
				onRequestClose={() => setPicker(null)}
			>
				<ScrollView
					style={{
						backgroundColor: colors.background,
						padding: spacing.lg,
						marginTop: 60,
					}}
				>
					<Text
						style={{
							color: colors.text,
							fontWeight: "700",
							marginBottom: spacing.sm,
						}}
					>
						{t("catalog.adminAddEntry")}
					</Text>
					{allWorks
						.map((w) => ({ id: w.id, label: `${w.title}` }))
						.map((row) => (
							<Pressable
								key={row.id}
								onPress={() => {
									void run(async () => {
										await addEntry.mutateAsync({
											franchiseID: data.id,
											workID: row.id,
										});
										setPicker(null);
									});
								}}
								style={{ padding: spacing.sm }}
							>
								<Text style={{ color: colors.text }}>{row.label}</Text>
							</Pressable>
						))}
					<Pressable onPress={() => setPicker("media")}>
						<Text style={{ color: colors.accent }}>
							{t("catalog.adminPickMovie")}
						</Text>
					</Pressable>
					<Pressable onPress={() => setPicker(null)}>
						<Text style={{ color: colors.accent }}>{t("common.cancel")}</Text>
					</Pressable>
				</ScrollView>
			</Modal>
			<ReorderModal
				visible={franchiseSort}
				title={sortLabel}
				rows={(data.entries ?? []).map((entry) => ({
					id: entry.id,
					label: entry.work?.title || entry.media?.title || `#${entry.id}`,
				}))}
				onClose={() => setFranchiseSort(false)}
				onSave={(ids) =>
					void run(() =>
						reorderEntries.mutateAsync({ franchiseID: data.id, ids }),
					)
				}
			/>
			<MediaPickerModal
				visible={picker === "media"}
				title={t("catalog.adminPickMovie")}
				onClose={() => setPicker(null)}
				onSelect={handleMedia}
			/>
		</Screen>
	);
}
