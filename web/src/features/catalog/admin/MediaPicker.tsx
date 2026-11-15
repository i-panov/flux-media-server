import { Alert, Button, Select, Stack, Text } from "@mantine/core";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useVideoList } from "../../../api/media";
import { useDebouncedValue } from "../../../hooks/useDebouncedValue";

export function MediaPicker({
	label,
	value,
	onChange,
}: {
	label: string;
	value: string | null;
	onChange: (value: string | null) => void;
}) {
	const { t } = useTranslation();
	const [search, setSearch] = useState("");
	const query = useDebouncedValue(search);
	const list = useVideoList(query, "desc");
	const items = list.data?.pages.flatMap((page) => page.items) ?? [];
	const data = items.map((item) => ({
		value: String(item.id),
		label: item.title || `#${item.id}`,
	}));
	return (
		<Stack gap="xs">
			<Select
				label={label}
				searchable
				filter={({ options }) => options}
				searchValue={search}
				onSearchChange={setSearch}
				data={data}
				value={value}
				onChange={onChange}
				nothingFoundMessage={t("catalog.admin.noVideos")}
			/>
			{list.isPending && (
				<Text size="xs" c="dimmed">
					{t("common.loading")}
				</Text>
			)}
			{list.isError && (
				<Alert color="red">
					<Button size="xs" variant="light" onClick={() => void list.refetch()}>
						{t("common.retry")}
					</Button>
				</Alert>
			)}
			{list.hasNextPage && (
				<Button
					size="compact-xs"
					variant="subtle"
					loading={list.isFetchingNextPage}
					onClick={() => void list.fetchNextPage()}
				>
					{t("catalog.admin.loadMore")}
				</Button>
			)}
		</Stack>
	);
}
