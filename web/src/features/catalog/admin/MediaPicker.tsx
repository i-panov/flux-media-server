import {
	Alert,
	Button,
	Card,
	Group,
	Modal,
	SimpleGrid,
	Stack,
	Text,
	TextInput,
} from "@mantine/core";
import { Search } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useVideoList } from "../../../api/media";
import { formatDuration } from "../../../core/format";
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
	const [opened, setOpened] = useState(false);
	const [search, setSearch] = useState("");
	const [selectedLabel, setSelectedLabel] = useState("");
	const query = useDebouncedValue(search);
	const list = useVideoList(query, "desc");
	const items = list.data?.pages.flatMap((page) => page.items) ?? [];

	const select = (id: string, title: string) => {
		onChange(id);
		setSelectedLabel(title);
		setOpened(false);
	};

	return (
		<Stack gap="xs">
			<Text size="sm" fw={500}>
				{label}
			</Text>
			<Group gap="xs">
				<Button variant="default" onClick={() => setOpened(true)}>
					{selectedLabel ||
						(value === null ? t("catalog.admin.pickVideo") : `#${value}`)}
				</Button>
				{value !== null && (
					<Button
						variant="subtle"
						size="xs"
						onClick={() => {
							onChange(null);
							setSelectedLabel("");
						}}
					>
						{t("common.clear")}
					</Button>
				)}
			</Group>
			<Modal
				opened={opened}
				onClose={() => setOpened(false)}
				title={label}
				size="lg"
				centered
			>
				<Stack gap="sm">
					<TextInput
						leftSection={<Search size={16} />}
						placeholder={t("catalog.admin.searchVideos")}
						value={search}
						onChange={(event) => setSearch(event.currentTarget.value)}
					/>
					{list.isPending ? (
						<Text c="dimmed">{t("common.loading")}</Text>
					) : list.isError ? (
						<Alert color="red">
							<Button size="xs" onClick={() => void list.refetch()}>
								{t("common.retry")}
							</Button>
						</Alert>
					) : items.length === 0 ? (
						<Text c="dimmed">{t("catalog.admin.noVideos")}</Text>
					) : (
						<SimpleGrid cols={{ base: 2, sm: 3 }} spacing="xs">
							{items.map((media) => (
								<Card
									key={media.id}
									withBorder
									padding="xs"
									radius="md"
									onClick={() =>
										select(String(media.id), media.title || `#${media.id}`)
									}
									style={{ cursor: "pointer" }}
								>
									{media.thumbnail_url === "" ? (
										<div className="grid aspect-video w-full place-items-center rounded bg-[var(--mantine-color-default-hover)]">
											<Text size="xs" c="dimmed">
												{t("common.emptyFallback")}
											</Text>
										</div>
									) : (
										<img
											src={media.thumbnail_url}
											alt=""
											loading="lazy"
											className="aspect-video w-full rounded object-cover"
										/>
									)}
									<Text size="sm" fw={600} lineClamp={2} mt={4}>
										{media.title || `#${media.id}`}
									</Text>
									<Text size="xs" c="dimmed">
										{formatDuration(media.duration)}
									</Text>
								</Card>
							))}
						</SimpleGrid>
					)}
					{list.hasNextPage && (
						<Button
							variant="light"
							loading={list.isFetchingNextPage}
							onClick={() => void list.fetchNextPage()}
						>
							{t("catalog.admin.loadMore")}
						</Button>
					)}
				</Stack>
			</Modal>
		</Stack>
	);
}
