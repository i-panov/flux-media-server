import Ionicons from "@expo/vector-icons/Ionicons";
import { useState } from "react";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { useFranchises, useWork, useWorks } from "../api/catalog";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

export type UploadDestinationKind =
	| "standalone"
	| "series"
	| "film_series"
	| "franchise";

export interface UploadDestinationValue {
	kind: UploadDestinationKind;
	workID: number | null;
	seasonID: number | null;
	franchiseID: number | null;
}

export const EMPTY_DESTINATION: UploadDestinationValue = {
	kind: "standalone",
	workID: null,
	seasonID: null,
	franchiseID: null,
};

type Picker = "work" | "season" | "franchise" | null;

// Куда добавить загруженное видео: сольное, в сериал (сезон), в серию
// фильмов или во франшизу. Список сезонов подтягивается по выбранному
// произведению.
export function UploadDestination({
	value,
	onChange,
}: {
	value: UploadDestinationValue;
	onChange: (next: UploadDestinationValue) => void;
}) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const [picker, setPicker] = useState<Picker>(null);
	const series = useWorks("series");
	const filmSeries = useWorks("film_series");
	const franchises = useFranchises();
	const work = useWork(value.workID ?? 0, value.workID !== null);
	const labels = {
		standalone: t("upload.destination.standalone"),
		series: t("upload.destination.series"),
		film_series: t("upload.destination.filmSeries"),
		franchise: t("upload.destination.franchise"),
		season: t("upload.destination.season"),
	};

	const works = value.kind === "series" ? series.data : filmSeries.data;
	const selectedWork = (works ?? []).find((item) => item.id === value.workID);
	const season = (work.data?.seasons ?? []).find(
		(item) => item.id === value.seasonID,
	);

	const chooseKind = (kind: UploadDestinationKind) => {
		onChange({
			kind,
			workID: null,
			seasonID: null,
			franchiseID: null,
		});
	};

	const pickerTitle =
		picker === "work"
			? value.kind === "series"
				? labels.series
				: labels.film_series
			: picker === "season"
				? labels.season
				: labels.franchise;

	const rows =
		picker === "work"
			? (works ?? []).map((item) => ({
					id: item.id,
					label: item.title,
				}))
			: picker === "season"
				? (work.data?.seasons ?? []).map((item) => ({
						id: item.id,
						label:
							item.title ||
							`${t("upload.destination.season")} ${item.season_number}`,
					}))
				: (franchises.data ?? []).map((item) => ({
						id: item.id,
						label: item.name,
					}));

	return (
		<View style={{ gap: spacing.sm }}>
			<Text style={{ color: colors.textMuted }}>
				{t("upload.destination.title")}
			</Text>
			<KindChips value={value.kind} onChange={chooseKind} labels={labels} />
			<TargetFields
				value={value}
				labels={labels}
				workTitle={selectedWork?.title}
				season={season}
				franchiseName={
					(franchises.data ?? []).find((item) => item.id === value.franchiseID)
						?.name
				}
				onOpen={setPicker}
			/>
			{picker !== null && (
				<DestinationPicker
					title={pickerTitle}
					rows={rows}
					onPick={(id) => {
						if (picker === "work") {
							onChange({ ...value, workID: id, seasonID: null });
						} else if (picker === "season") {
							onChange({ ...value, seasonID: id });
						} else {
							onChange({ ...value, franchiseID: id });
						}
						setPicker(null);
					}}
					onClose={() => setPicker(null)}
				/>
			)}
		</View>
	);
}

function TargetFields({
	value,
	labels,
	workTitle,
	season,
	franchiseName,
	onOpen,
}: {
	value: UploadDestinationValue;
	labels: { season: string };
	workTitle: string | undefined;
	season: { id: number; title: string; season_number: number } | undefined;
	franchiseName: string | undefined;
	onOpen: (picker: Picker) => void;
}) {
	const { colors, radii } = useTheme();
	const isWorkKind = value.kind === "series" || value.kind === "film_series";
	const seasonLabel =
		season?.title !== undefined && season.title !== ""
			? season.title
			: `${labels.season} ${season?.season_number ?? ""}`;
	return (
		<>
			{isWorkKind && (
				<Pressable
					testID="upload-destination-work"
					onPress={() => onOpen("work")}
					style={[
						styles.field,
						{ borderColor: colors.border, borderRadius: radii.md },
					]}
				>
					<Text style={{ color: workTitle ? colors.text : colors.textMuted }}>
						{workTitle ?? t("upload.destination.pickWork")}
					</Text>
					<Ionicons name="chevron-down" size={16} color={colors.textMuted} />
				</Pressable>
			)}
			{value.kind === "series" && value.workID !== null && (
				<Pressable
					testID="upload-destination-season"
					onPress={() => onOpen("season")}
					style={[
						styles.field,
						{ borderColor: colors.border, borderRadius: radii.md },
					]}
				>
					<Text style={{ color: season ? colors.text : colors.textMuted }}>
						{season ? seasonLabel : t("upload.destination.pickSeason")}
					</Text>
					<Ionicons name="chevron-down" size={16} color={colors.textMuted} />
				</Pressable>
			)}
			{value.kind === "franchise" && (
				<Pressable
					testID="upload-destination-franchise"
					onPress={() => onOpen("franchise")}
					style={[
						styles.field,
						{ borderColor: colors.border, borderRadius: radii.md },
					]}
				>
					<Text style={{ color: colors.text }}>
						{franchiseName ?? t("upload.destination.pickFranchise")}
					</Text>
					<Ionicons name="chevron-down" size={16} color={colors.textMuted} />
				</Pressable>
			)}
		</>
	);
}

function KindChips({
	value,
	onChange,
	labels,
}: {
	value: UploadDestinationKind;
	onChange: (kind: UploadDestinationKind) => void;
	labels: Record<UploadDestinationKind, string>;
}) {
	const { colors, radii } = useTheme();
	const kinds: UploadDestinationKind[] = [
		"standalone",
		"series",
		"film_series",
		"franchise",
	];
	return (
		<View style={[styles.wrap, { gap: 6 }]}>
			{kinds.map((kind) => {
				const active = value === kind;
				return (
					<Pressable
						key={kind}
						testID={`upload-destination-${kind}`}
						onPress={() => onChange(kind)}
						style={[
							styles.chip,
							{
								borderRadius: radii.md,
								borderColor: active ? colors.accent : colors.border,
								backgroundColor: active ? colors.surfaceMuted : colors.surface,
							},
						]}
					>
						<Text style={{ color: active ? colors.accent : colors.text }}>
							{labels[kind]}
						</Text>
					</Pressable>
				);
			})}
		</View>
	);
}

function DestinationPicker({
	title,
	rows,
	onPick,
	onClose,
}: {
	title: string;
	rows: { id: number; label: string }[];
	onPick: (id: number) => void;
	onClose: () => void;
}) {
	const { colors } = useTheme();
	return (
		<View
			style={[
				styles.list,
				{ borderColor: colors.border, backgroundColor: colors.surface },
			]}
		>
			<View style={[styles.row, styles.between]}>
				<Text style={{ color: colors.text, fontWeight: "600" }}>{title}</Text>
				<Pressable onPress={onClose} testID="upload-picker-close">
					<Ionicons name="close" size={18} color={colors.textMuted} />
				</Pressable>
			</View>
			<ScrollView style={{ maxHeight: 220 }}>
				{rows.length === 0 && (
					<Text style={{ color: colors.textMuted, padding: 8 }}>
						{t("search.noResults")}
					</Text>
				)}
				{rows.map((row) => (
					<Pressable
						key={row.id}
						testID={`upload-pick-${row.id}`}
						onPress={() => onPick(row.id)}
						style={styles.row}
					>
						<Text style={{ color: colors.text }}>{row.label}</Text>
					</Pressable>
				))}
			</ScrollView>
		</View>
	);
}

const styles = StyleSheet.create({
	wrap: { flexDirection: "row", flexWrap: "wrap" },
	chip: { borderWidth: 1, paddingHorizontal: 10, paddingVertical: 6 },
	field: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
		borderWidth: 1,
		paddingHorizontal: 10,
		paddingVertical: 10,
	},
	list: { borderWidth: 1, borderRadius: 10, padding: 8, gap: 4 },
	row: { flexDirection: "row", paddingVertical: 8 },
	between: { justifyContent: "space-between", alignItems: "center" },
});
