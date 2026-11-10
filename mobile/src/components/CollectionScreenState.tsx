import type { ReactNode } from "react";
import { ActivityIndicator, StyleSheet, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { CollectionBackHeader } from "./CollectionBackHeader";
import { EmptyState } from "./EmptyState";
import { ErrorState } from "./ErrorState";
import { Screen } from "./Screen";

type CollectionStateKind = "loading" | "notFound" | "loadError" | "itemsError";

interface CollectionScreenStateProps {
	kind: CollectionStateKind;
	onBack: () => void;
	onRetry?: () => void;
	title?: string;
}

// Единые состояния экрана коллекции: загрузка, 404 и ошибки загрузки.
// Вынесены из основного компонента, чтобы тот не разрастался и не
// повторял разметку с бэк-хедером четыре раза.
export function CollectionScreenState({
	kind,
	onBack,
	onRetry,
	title,
}: CollectionScreenStateProps) {
	useLanguage();
	const { colors } = useTheme();
	const headerTitle = title ?? t("collections.detailTitle");

	let body: ReactNode = null;
	if (kind === "loading") {
		body = (
			<View style={styles.center}>
				<ActivityIndicator color={colors.accent} />
			</View>
		);
	} else if (kind === "notFound") {
		body = (
			<EmptyState
				icon="folder-open-outline"
				title={t("collections.notFound")}
				description={t("collections.notFoundHint")}
				testID="collection-detail-not-found"
			/>
		);
	} else if (kind === "loadError") {
		body = (
			<ErrorState
				title={t("collections.loadError")}
				onRetry={onRetry}
				testID="collection-detail-error"
			/>
		);
	} else {
		body = (
			<ErrorState
				title={t("collections.itemsError")}
				onRetry={onRetry}
				testID="collection-items-error"
			/>
		);
	}

	return (
		<Screen edges={["top", "bottom"]}>
			<CollectionBackHeader title={headerTitle} onBack={onBack} />
			{body}
		</Screen>
	);
}

const styles = StyleSheet.create({
	center: { flex: 1, alignItems: "center", justifyContent: "center" },
});
