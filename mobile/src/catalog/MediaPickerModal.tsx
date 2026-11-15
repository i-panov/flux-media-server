import { useMemo, useState } from "react";
import {
	ActivityIndicator,
	Modal,
	Pressable,
	ScrollView,
	Text,
	TextInput,
	View,
} from "react-native";
import { useVideoList } from "../api/media";
import { t } from "../i18n";
import { useDebouncedValue } from "../media/useDebouncedValue";
import { useTheme } from "../theme/ThemeProvider";

export function MediaPickerModal({
	visible,
	title,
	onClose,
	onSelect,
}: {
	visible: boolean;
	title: string;
	onClose: () => void;
	onSelect: (mediaID: number) => void;
}) {
	const { colors, spacing } = useTheme();
	const [search, setSearch] = useState("");
	const query = useDebouncedValue(search);
	const list = useVideoList(query, "desc");
	const items = useMemo(
		() => list.data?.pages.flatMap((page) => page.items) ?? [],
		[list.data],
	);
	return (
		<Modal
			visible={visible}
			transparent
			animationType="fade"
			onRequestClose={onClose}
		>
			<View
				style={{
					flex: 1,
					justifyContent: "center",
					padding: spacing.lg,
					backgroundColor: "rgba(0,0,0,0.45)",
				}}
			>
				<View
					style={{
						backgroundColor: colors.background,
						borderRadius: 12,
						padding: spacing.md,
						maxHeight: "85%",
						gap: spacing.sm,
					}}
				>
					<Text style={{ color: colors.text, fontSize: 18, fontWeight: "700" }}>
						{title}
					</Text>
					<TextInput
						value={search}
						onChangeText={setSearch}
						placeholder={t("catalog.adminSearch")}
						style={{
							color: colors.text,
							borderColor: colors.border,
							borderWidth: 1,
							borderRadius: 8,
							padding: spacing.sm,
						}}
					/>
					{list.isPending ? (
						<ActivityIndicator color={colors.accent} />
					) : list.isError ? (
						<Pressable onPress={() => void list.refetch()}>
							<Text style={{ color: colors.danger }}>
								{t("catalog.loadError")} · {t("common.retry")}
							</Text>
						</Pressable>
					) : items.length === 0 ? (
						<Text style={{ color: colors.textMuted }}>
							{t("catalog.adminNoVideos")}
						</Text>
					) : (
						<ScrollView>
							{items.map((media) => (
								<Pressable
									key={media.id}
									onPress={() => onSelect(media.id)}
									style={{ padding: spacing.sm }}
								>
									<Text style={{ color: colors.text }}>
										{media.title || `#${media.id}`}
									</Text>
								</Pressable>
							))}
							{list.hasNextPage && (
								<Pressable
									onPress={() => void list.fetchNextPage()}
									disabled={list.isFetchingNextPage}
								>
									<Text style={{ color: colors.accent }}>
										{list.isFetchingNextPage
											? t("common.loading")
											: t("catalog.adminLoadMore")}
									</Text>
								</Pressable>
							)}
						</ScrollView>
					)}
					<Pressable onPress={onClose}>
						<Text style={{ color: colors.accent }}>{t("common.cancel")}</Text>
					</Pressable>
				</View>
			</View>
		</Modal>
	);
}
