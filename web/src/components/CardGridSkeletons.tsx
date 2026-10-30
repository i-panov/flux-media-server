import { SimpleGrid, Skeleton, Stack } from "@mantine/core";

const GRID_SKELETON_COUNT = 12;

// Скелетоны списков: одна сетка на разделы и пикер коллекций.
// Квадрат без строк — мемы, иначе карточка с высотой картинки.
export function CardGridSkeletons({
	count = GRID_SKELETON_COUNT,
	imageHeight = 140,
	square = false,
	textLines = 1,
}: {
	count?: number;
	imageHeight?: number;
	square?: boolean;
	textLines?: 0 | 1 | 2;
}) {
	return (
		<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5, xl: 6 }} spacing="md">
			{Array.from({ length: count }, (_, index) =>
				square ? (
					// Скелетоны без данных: индекс — стабильный
					// идентификатор позиции, а не сущности.
					// biome-ignore lint/suspicious/noArrayIndexKey: skeleton placeholder
					<Skeleton key={index} className="aspect-square" radius="md" />
				) : (
					// biome-ignore lint/suspicious/noArrayIndexKey: skeleton placeholder
					<Stack key={index} gap="xs">
						<Skeleton height={imageHeight} radius="md" />
						{textLines >= 1 && <Skeleton height={14} width="80%" radius="sm" />}
						{textLines >= 2 && <Skeleton height={12} width="50%" radius="sm" />}
					</Stack>
				),
			)}
		</SimpleGrid>
	);
}
