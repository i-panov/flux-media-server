import {
	Alert,
	Button,
	Card,
	Group,
	Loader,
	Skeleton,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { Link } from "@tanstack/react-router";
import { ArrowLeft } from "lucide-react";
import { useTranslation } from "react-i18next";
import {
	useAdminUsersQuery,
	useOriginalsQuery,
	useRetryTranscode,
	useStorageQuery,
} from "../../api/admin";
import { ApiError } from "../../api/client";
import { useSession } from "../../api/session";
import { useCancelTranscode, useTranscodesQuery } from "../../api/transcode";
import { OriginalsTable } from "./OriginalsTable";
import { StorageWidget } from "./StorageWidget";
import { TranscodeQueueTable } from "./TranscodeQueueTable";
import { UsersTable } from "./UsersTable";

function SectionError({ onRetry }: { onRetry: () => void }) {
	const { t } = useTranslation();
	return (
		<Alert color="red" variant="light" title={t("admin.loadError")}>
			<Button variant="light" size="xs" mt="xs" onClick={onRetry}>
				{t("common.retry")}
			</Button>
		</Alert>
	);
}

export function AdminPage() {
	const { t } = useTranslation();
	const session = useSession();
	const isAdmin = session.data?.is_admin === true;
	const storage = useStorageQuery({ enabled: isAdmin });
	const transcodes = useTranscodesQuery({ enabled: isAdmin });
	const originals = useOriginalsQuery({ enabled: isAdmin });
	const users = useAdminUsersQuery({ enabled: isAdmin });
	const retry = useRetryTranscode();
	const cancel = useCancelTranscode();

	if (session.isPending) {
		return (
			<Group justify="center" py="xl">
				<Loader />
			</Group>
		);
	}

	if (session.data?.is_admin !== true) {
		return (
			<Stack gap="md">
				<Alert color="red" variant="light">
					{t("admin.adminOnly")}
				</Alert>
				<Button
					component={Link}
					to="/"
					variant="light"
					w="fit-content"
					leftSection={<ArrowLeft size={16} />}
				>
					{t("common.backHome")}
				</Button>
			</Stack>
		);
	}

	const notifyError = (error: unknown) => {
		notifications.show({
			color: "red",
			title: t("admin.actionError"),
			message: error instanceof ApiError ? error.message : "",
		});
	};

	return (
		<Stack gap="lg">
			<Stack gap={4}>
				<Title order={1} size="h2">
					{t("admin.title")}
				</Title>
				<Text c="dimmed">{t("admin.subtitle")}</Text>
			</Stack>

			<section aria-label={t("admin.storage.title")}>
				{storage.isPending ? (
					<Stack gap="md">
						<Skeleton height={32} width="30%" radius="sm" />
						<Skeleton height={120} radius="md" />
					</Stack>
				) : storage.isError ? (
					<SectionError onRetry={() => void storage.refetch()} />
				) : (
					storage.data && <StorageWidget data={storage.data} />
				)}
			</section>

			<section aria-label={t("admin.queue.title")}>
				<Stack gap="sm">
					<Title order={2} size="h4">
						{t("admin.queue.title")}
					</Title>
					{transcodes.isPending ? (
						<Skeleton height={160} radius="md" />
					) : transcodes.isError ? (
						<SectionError onRetry={() => void transcodes.refetch()} />
					) : (
						<TranscodeQueueTable
							items={transcodes.data ?? []}
							retryPending={retry.isPending}
							cancelPending={cancel.isPending}
							onRetry={(id) => {
								if (retry.isPending) {
									return;
								}
								retry.mutate(id, { onError: notifyError });
							}}
							onCancel={(id) => {
								if (cancel.isPending) {
									return;
								}
								cancel.mutate(id, { onError: notifyError });
							}}
						/>
					)}
				</Stack>
			</section>

			<section aria-label={t("admin.originals.title")}>
				<Stack gap="sm">
					<Title order={2} size="h4">
						{t("admin.originals.title")}
					</Title>
					{originals.isPending ? (
						<Skeleton height={160} radius="md" />
					) : originals.isError ? (
						<SectionError onRetry={() => void originals.refetch()} />
					) : (
						<OriginalsTable items={originals.data ?? []} />
					)}
				</Stack>
			</section>

			<section aria-label={t("admin.users.title")}>
				<Stack gap="sm">
					<Title order={2} size="h4">
						{t("admin.users.title")}
					</Title>
					<Text size="sm" c="dimmed">
						{t("admin.users.hint")}
					</Text>
					{users.isPending ? (
						<Skeleton height={160} radius="md" />
					) : users.isError ? (
						<SectionError onRetry={() => void users.refetch()} />
					) : (users.data ?? []).length === 0 ? (
						<Card withBorder padding="md" radius="md">
							<Text c="dimmed">{t("admin.users.empty")}</Text>
						</Card>
					) : (
						<UsersTable
							users={users.data ?? []}
							currentUserId={session.data?.id}
						/>
					)}
				</Stack>
			</section>
		</Stack>
	);
}
