import { Stack, Text } from "@mantine/core";

export function MetaItem({ label, value }: { label: string; value: string }) {
	return (
		<Stack gap={2}>
			<Text size="xs" c="dimmed">
				{label}
			</Text>
			<Text size="sm" fw={600}>
				{value}
			</Text>
		</Stack>
	);
}
