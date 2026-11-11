import {
	ActionIcon,
	Badge,
	Button,
	Card,
	Group,
	Modal,
	Stack,
	Switch,
	Table,
	Text,
	Tooltip,
} from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { Trash2 } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	type AdminUser,
	useDeleteUser,
	useSetUserAdmin,
} from "../../api/admin";
import { ApiError } from "../../api/client";

export function UsersTable({
	users,
	currentUserId,
}: {
	users: AdminUser[];
	currentUserId: number | undefined;
}) {
	const { t } = useTranslation();
	const setAdmin = useSetUserAdmin();
	const remove = useDeleteUser();
	const [pendingId, setPendingId] = useState<number | null>(null);
	const [confirm, setConfirm] = useState<AdminUser | null>(null);
	const deleteLabel = t("admin.users.delete");

	if (users.length === 0) {
		return (
			<Card withBorder padding="md" radius="md">
				<Text c="dimmed">{t("admin.users.empty")}</Text>
			</Card>
		);
	}

	const notifyError = (error: unknown) => {
		notifications.show({
			color: "red",
			title: t("admin.actionError"),
			message: error instanceof ApiError ? error.message : "",
		});
	};

	const handleDelete = (user: AdminUser) => {
		if (pendingId !== null) {
			return;
		}
		setPendingId(user.id);
		remove.mutate(user.id, {
			onSuccess: () => setConfirm(null),
			onError: notifyError,
			onSettled: () => setPendingId(null),
		});
	};

	return (
		<>
			<div className="admin-table-scroll">
				<Table striped highlightOnHover>
					<Table.Thead>
						<Table.Tr>
							<Table.Th>{t("admin.users.email")}</Table.Th>
							<Table.Th>{t("admin.users.admin")}</Table.Th>
							<Table.Th>{t("admin.users.created")}</Table.Th>
							<Table.Th>{t("admin.users.actions")}</Table.Th>
						</Table.Tr>
					</Table.Thead>
					<Table.Tbody>
						{users.map((user) => {
							const isSelf = currentUserId === user.id;
							return (
								<Table.Tr key={user.id}>
									<Table.Td>
										<Group gap="xs">
											<Text fw={600} truncate maw={240}>
												{user.email}
											</Text>
											{user.is_admin && (
												<Badge variant="light" color="violet">
													{t("settings.account.admin")}
												</Badge>
											)}
										</Group>
									</Table.Td>
									<Table.Td>
										{isSelf ? (
											<Text size="sm" c="dimmed">
												{t("common.emptyFallback")}
											</Text>
										) : (
											<Switch
												checked={user.is_admin}
												disabled={setAdmin.isPending}
												aria-label={t("admin.users.admin")}
												onChange={(event) => {
													setAdmin.mutate(
														{
															id: user.id,
															isAdmin: event.currentTarget.checked,
														},
														{ onError: notifyError },
													);
												}}
											/>
										)}
									</Table.Td>
									<Table.Td>
										<Text size="sm" c="dimmed">
											{user.created_at}
										</Text>
									</Table.Td>
									<Table.Td>
										{isSelf ? (
											<Text size="sm" c="dimmed">
												{t("common.emptyFallback")}
											</Text>
										) : (
											<Tooltip label={deleteLabel} withArrow>
												<ActionIcon
													variant="light"
													color="red"
													aria-label={deleteLabel}
													loading={pendingId === user.id}
													onClick={() => setConfirm(user)}
												>
													<Trash2 size={16} />
												</ActionIcon>
											</Tooltip>
										)}
									</Table.Td>
								</Table.Tr>
							);
						})}
					</Table.Tbody>
				</Table>
			</div>
			<Modal
				opened={confirm !== null}
				onClose={() => setConfirm(null)}
				title={t("admin.users.deleteTitle")}
				centered
			>
				<Stack gap="md">
					<Text size="sm">
						{confirm === null
							? ""
							: t("admin.users.deleteConfirm", { email: confirm.email })}
					</Text>
					<Group justify="flex-end">
						<Button variant="default" onClick={() => setConfirm(null)}>
							{t("collections.cancel")}
						</Button>
						<Button
							color="red"
							loading={remove.isPending}
							onClick={() => {
								if (confirm !== null) {
									handleDelete(confirm);
								}
							}}
						>
							{deleteLabel}
						</Button>
					</Group>
				</Stack>
			</Modal>
		</>
	);
}
