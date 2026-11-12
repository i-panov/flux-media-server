import {
	ActionIcon,
	Badge,
	Button,
	Card,
	Group,
	Stack,
	Text,
	TextInput,
	Title,
	Tooltip,
} from "@mantine/core";
import { Check, Pencil, X } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	useDevicesQuery,
	useRenameDeviceMutation,
	useRevokeDeviceMutation,
} from "../../api/session";

export function DevicesCard() {
	const { t } = useTranslation();
	const devices = useDevicesQuery();
	const revoke = useRevokeDeviceMutation();
	const rename = useRenameDeviceMutation();
	const [editing, setEditing] = useState<string | null>(null);
	const [draft, setDraft] = useState("");
	const [error, setError] = useState<string | null>(null);

	const startRename = (deviceId: string, name: string) => {
		setEditing(deviceId);
		setDraft(name);
		setError(null);
	};

	const saveRename = () => {
		if (editing === null) return;
		rename.mutate(
			{ deviceId: editing, name: draft.trim() },
			{
				onSuccess: () => {
					setEditing(null);
					setError(null);
				},
				onError: () => setError(t("devices.renameError")),
			},
		);
	};

	return (
		<Card withBorder padding="lg" radius="md" h="100%">
			<Stack gap="md">
				<Title order={2} size="h4">
					{t("devices.title")}
				</Title>
				<Text size="sm" c="dimmed">
					{t("devices.hint")}
				</Text>
				{devices.isPending && <Text size="sm">{t("common.loading")}</Text>}
				{devices.data?.length === 0 && (
					<Text size="sm" c="dimmed">
						{t("devices.empty")}
					</Text>
				)}
				{error !== null && (
					<Text size="sm" c="red">
						{error}
					</Text>
				)}
				{devices.data?.map((device) => (
					<Group key={device.device_id} justify="space-between" wrap="nowrap">
						<Stack gap={2} style={{ flex: 1, minWidth: 0 }}>
							{editing === device.device_id ? (
								<Group gap="xs" wrap="nowrap">
									<TextInput
										size="xs"
										value={draft}
										maxLength={80}
										autoFocus
										onChange={(event) => setDraft(event.currentTarget.value)}
										onKeyDown={(event) => {
											if (event.key === "Enter") saveRename();
											if (event.key === "Escape") setEditing(null);
										}}
									/>
									<Tooltip label={t("common.save")} withArrow>
										<ActionIcon
											size="sm"
											color="green"
											aria-label={t("common.save")}
											onClick={saveRename}
											loading={rename.isPending}
										>
											<Check size={14} />
										</ActionIcon>
									</Tooltip>
									<Tooltip label={t("common.cancel")} withArrow>
										<ActionIcon
											size="sm"
											variant="subtle"
											aria-label={t("common.cancel")}
											onClick={() => setEditing(null)}
										>
											<X size={14} />
										</ActionIcon>
									</Tooltip>
								</Group>
							) : (
								<Group gap="xs" wrap="nowrap">
									<Text size="sm" fw={600} truncate>
										{device.device_name}
									</Text>
									<Tooltip label={t("devices.rename")} withArrow>
										<ActionIcon
											size="xs"
											variant="subtle"
											aria-label={t("devices.rename")}
											onClick={() =>
												startRename(device.device_id, device.device_name)
											}
										>
											<Pencil size={12} />
										</ActionIcon>
									</Tooltip>
									{device.platform !== "" && device.platform !== "unknown" && (
										<Badge size="xs" variant="light">
											{device.platform}
										</Badge>
									)}
								</Group>
							)}
							<Text size="xs" c="dimmed">
								{device.last_used_at ?? device.created_at}
							</Text>
						</Stack>
						<Button
							variant="subtle"
							color="red"
							size="xs"
							loading={
								revoke.isPending && revoke.variables === device.device_id
							}
							onClick={() => {
								if (window.confirm(t("devices.confirm"))) {
									revoke.mutate(device.device_id);
								}
							}}
						>
							{t("devices.revoke")}
						</Button>
					</Group>
				))}
			</Stack>
		</Card>
	);
}
