import Ionicons from "@expo/vector-icons/Ionicons";
import { ApiError, type Media } from "@flux/shared";
import { router, useLocalSearchParams } from "expo-router";
import { useCallback, useEffect, useState } from "react";
import {
	ActivityIndicator,
	Alert,
	BackHandler,
	KeyboardAvoidingView,
	Platform,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { useMedia } from "../../../src/api/media";
import {
	buildMetadataInput,
	isMetadataDraftDirty,
	type MetadataDraft,
	metadataDraftFromMedia,
	useUpdateMetadata,
	validateMetadataDraft,
} from "../../../src/api/metadata";
import { useSession } from "../../../src/auth/session";
import { AuthGate } from "../../../src/components/AuthGate";
import { EmptyState } from "../../../src/components/EmptyState";
import { ErrorState } from "../../../src/components/ErrorState";
import { MetadataArtistsEditor } from "../../../src/components/MetadataArtistsEditor";
import {
	EditHeader,
	MetadataField,
} from "../../../src/components/MetadataEditFields";
import { Screen } from "../../../src/components/Screen";
import { t, useLanguage } from "../../../src/i18n";
import { useTheme } from "../../../src/theme/ThemeProvider";

const EDIT_SCREEN_TEST_ID = "metadata-edit-screen";

function detailRoute(media: Media): string {
	if (media.type === "audio") {
		return `/audio/${media.id}`;
	}
	if (media.type === "video") {
		return `/video/${media.id}`;
	}
	return "/library";
}

// Deep link может открыть редактор первым: тогда истории нет и back ведёт
// на детали (или в библиотеку для неизвестного типа).
function closeEditor(media: Media): void {
	if (router.canGoBack()) {
		router.back();
		return;
	}
	router.replace(detailRoute(media));
}

function closeWithoutMedia(): void {
	if (router.canGoBack()) {
		router.back();
		return;
	}
	router.replace("/library");
}

function DefaultHeader({ onBack }: { onBack: () => void }) {
	return (
		<EditHeader
			title={t("metadata.title")}
			onBack={onBack}
			saving={false}
			canSave={false}
		/>
	);
}

function LoadingState() {
	const { colors, spacing } = useTheme();
	return (
		<View style={[styles.centered, { gap: spacing.sm }]}>
			<ActivityIndicator color={colors.accent} />
			<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
		</View>
	);
}

function NotFoundScreen() {
	return (
		<Screen testID={EDIT_SCREEN_TEST_ID}>
			<DefaultHeader onBack={closeWithoutMedia} />
			<EmptyState
				icon="document-text-outline"
				title={t("metadata.notFound")}
				description={t("metadata.notFoundHint")}
				testID="metadata-not-found"
			/>
		</Screen>
	);
}

function AdminOnlyState() {
	const { colors, radii, spacing } = useTheme();
	return (
		<>
			<DefaultHeader onBack={closeWithoutMedia} />
			<View
				testID="metadata-admin-only"
				accessibilityRole="alert"
				style={[
					styles.noticeCard,
					{
						borderColor: colors.danger,
						backgroundColor: colors.surface,
						borderRadius: radii.md,
						padding: spacing.md,
						gap: spacing.sm,
					},
				]}
			>
				<Ionicons name="lock-closed-outline" size={20} color={colors.danger} />
				<View style={[styles.noticeBody, { gap: spacing.xs }]}>
					<Text style={[styles.noticeTitle, { color: colors.text }]}>
						{t("metadata.adminOnlyTitle")}
					</Text>
					<Text style={[styles.noticeText, { color: colors.textMuted }]}>
						{t("metadata.adminOnly")}
					</Text>
				</View>
			</View>
		</>
	);
}

// AuthGate монтируется до запросов: deep link без сессии уходит на /login.
// Проверка is_admin — отдельный компонент, чтобы useMedia не запускался у
// обычного зрителя.
export default function EditMetadataScreen() {
	return (
		<AuthGate>
			<EditMetadataGate />
		</AuthGate>
	);
}

function EditMetadataGate() {
	useLanguage();
	const session = useSession();
	if (session.isPending) {
		return (
			<Screen testID={EDIT_SCREEN_TEST_ID}>
				<DefaultHeader onBack={closeWithoutMedia} />
				<LoadingState />
			</Screen>
		);
	}
	if (session.data?.is_admin !== true) {
		return (
			<Screen testID={EDIT_SCREEN_TEST_ID}>
				<AdminOnlyState />
			</Screen>
		);
	}
	return <EditMetadataLoader />;
}

function EditMetadataLoader() {
	useLanguage();
	const params = useLocalSearchParams<{ id?: string | string[] }>();
	const rawId = Array.isArray(params.id) ? params.id[0] : params.id;
	const mediaId = rawId === undefined ? Number.NaN : Number(rawId);
	const valid = Number.isInteger(mediaId) && mediaId > 0;
	const media = useMedia(valid ? mediaId : 0, valid);

	if (!valid) {
		return <NotFoundScreen />;
	}
	if (media.isPending) {
		return (
			<Screen testID={EDIT_SCREEN_TEST_ID}>
				<DefaultHeader onBack={closeWithoutMedia} />
				<LoadingState />
			</Screen>
		);
	}
	if (media.data === undefined) {
		const notFound =
			media.error instanceof ApiError && media.error.status === 404;
		if (notFound) {
			return <NotFoundScreen />;
		}
		return (
			<Screen testID={EDIT_SCREEN_TEST_ID}>
				<DefaultHeader onBack={closeWithoutMedia} />
				<ErrorState
					title={t("metadata.loadError")}
					onRetry={() => void media.refetch()}
					testID="metadata-load-error"
				/>
			</Screen>
		);
	}
	return <MetadataForm key={media.data.id} media={media.data} />;
}

function MetadataForm({ media }: { media: Media }) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const [initial] = useState<MetadataDraft>(() =>
		metadataDraftFromMedia(media),
	);
	const [draft, setDraft] = useState<MetadataDraft>(initial);
	const update = useUpdateMetadata(media.id);

	const validation = validateMetadataDraft(draft);
	const dirty = isMetadataDraftDirty(initial, draft);
	const saving = update.isPending;
	const canSave =
		dirty &&
		!saving &&
		validation.title &&
		validation.year &&
		validation.sourceUrl;

	const setField = (key: keyof MetadataDraft, value: string) => {
		setDraft((current) => ({ ...current, [key]: value }));
	};

	const setArtist = (index: number, value: string) => {
		setDraft((current) => ({
			...current,
			artists: current.artists.map((artist, position) =>
				position === index ? value : artist,
			),
		}));
	};

	const addArtist = () => {
		setDraft((current) => ({
			...current,
			artists: [...current.artists, ""],
		}));
	};

	const removeArtist = (index: number) => {
		setDraft((current) => ({
			...current,
			artists: current.artists.filter((_, position) => position !== index),
		}));
	};

	const leave = useCallback(() => {
		if (saving) {
			return;
		}
		if (!dirty) {
			closeEditor(media);
			return;
		}
		Alert.alert(t("metadata.discardTitle"), t("metadata.discardConfirm"), [
			{ text: t("metadata.stay"), style: "cancel" },
			{
				text: t("metadata.discard"),
				style: "destructive",
				onPress: () => closeEditor(media),
			},
		]);
	}, [dirty, media, saving]);

	// Android hardware back: при несохранённых правках спрашиваем
	// подтверждение, при сохранении не выпускаем из экрана.
	useEffect(() => {
		const subscription = BackHandler.addEventListener(
			"hardwareBackPress",
			() => {
				leave();
				return true;
			},
		);
		return () => subscription.remove();
	}, [leave]);

	const save = () => {
		if (!validation.title || !validation.year || !validation.sourceUrl) {
			return;
		}
		update.mutate(buildMetadataInput(draft), {
			onSuccess: () => closeEditor(media),
		});
	};

	const titleError = validation.title ? undefined : t("metadata.required");
	const yearError =
		draft.year.trim() !== "" && !validation.year
			? t("metadata.invalidYear")
			: undefined;
	const sourceError =
		draft.sourceUrl.trim() !== "" && !validation.sourceUrl
			? t("metadata.invalidSourceUrl")
			: undefined;
	const saveError =
		update.error instanceof ApiError && update.error.status === 404
			? t("metadata.notFound")
			: t("metadata.saveError");

	return (
		<KeyboardAvoidingView
			behavior={Platform.OS === "ios" ? "padding" : undefined}
			style={styles.fill}
		>
			<Screen scroll testID={EDIT_SCREEN_TEST_ID} edges={["top", "bottom"]}>
				<EditHeader
					title={t("metadata.title")}
					onBack={leave}
					saving={saving}
					canSave={canSave}
					onSave={save}
				/>
				<MetadataField
					label={t("metadata.name")}
					value={draft.title}
					onChangeText={(value) => setField("title", value)}
					testID="metadata-field-title"
					editable={!saving}
					required
					error={titleError}
				/>
				<MetadataArtistsEditor
					artists={draft.artists}
					editable={!saving}
					onChange={setArtist}
					onAdd={addArtist}
					onRemove={removeArtist}
				/>
				<MetadataField
					label={t("metadata.album")}
					value={draft.album}
					onChangeText={(value) => setField("album", value)}
					testID="metadata-field-album"
					editable={!saving}
				/>
				<MetadataField
					label={t("metadata.genre")}
					value={draft.genre}
					onChangeText={(value) => setField("genre", value)}
					testID="metadata-field-genre"
					editable={!saving}
				/>
				<MetadataField
					label={t("metadata.year")}
					value={draft.year}
					onChangeText={(value) => setField("year", value)}
					testID="metadata-field-year"
					editable={!saving}
					hint={t("metadata.yearHint")}
					error={yearError}
					keyboardType="number-pad"
				/>
				<MetadataField
					label={t("metadata.description")}
					value={draft.description}
					onChangeText={(value) => setField("description", value)}
					testID="metadata-field-description"
					editable={!saving}
					multiline
				/>
				<MetadataField
					label={t("metadata.sourceUrl")}
					value={draft.sourceUrl}
					onChangeText={(value) => setField("sourceUrl", value)}
					testID="metadata-field-source"
					editable={!saving}
					hint={t("metadata.sourceHint")}
					error={sourceError}
					keyboardType="url"
					autoCapitalize="none"
					autoCorrect={false}
				/>
				{update.isError && (
					<Text
						accessibilityRole="alert"
						accessibilityLiveRegion="polite"
						testID="metadata-save-error"
						style={[styles.saveError, { color: colors.danger }]}
					>
						{saveError}
					</Text>
				)}
				{saving && (
					<View
						style={[styles.savingStatus, { gap: spacing.sm }]}
						accessibilityLiveRegion="polite"
						testID="metadata-saving"
					>
						<ActivityIndicator size="small" color={colors.accent} />
						<Text style={{ color: colors.textMuted }}>
							{t("metadata.saving")}
						</Text>
					</View>
				)}
			</Screen>
		</KeyboardAvoidingView>
	);
}

const styles = StyleSheet.create({
	fill: { flex: 1 },
	centered: { flex: 1, alignItems: "center", justifyContent: "center" },
	noticeCard: {
		flexDirection: "row",
		alignItems: "flex-start",
		borderWidth: 1,
	},
	noticeBody: { flex: 1 },
	noticeTitle: { fontSize: 15, fontWeight: "600" },
	noticeText: { fontSize: 14, lineHeight: 20 },
	saveError: { fontSize: 14 },
	savingStatus: {
		flexDirection: "row",
		alignItems: "center",
		minHeight: 44,
	},
});
