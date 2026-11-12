import {
	Alert,
	Button,
	Card,
	Code,
	Container,
	Group,
	Stack,
	Text,
	TextInput,
	Title,
} from "@mantine/core";
import { Link, useNavigate, useSearch } from "@tanstack/react-router";
import { useCallback, useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import {
	useApproveDeviceCodeMutation,
	useInspectDeviceCodeMutation,
	useSession,
} from "../../api/session";

export function ActivatePage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const search = useSearch({ from: "/activate" });
	const session = useSession();
	const inspect = useInspectDeviceCodeMutation();
	const approve = useApproveDeviceCodeMutation();
	const [code, setCode] = useState(search.code ?? "");
	const [done, setDone] = useState(false);
	const inspectedRef = useRef(false);

	const runInspect = useCallback(
		(value: string) => {
			const normalized = value.trim().toUpperCase();
			if (normalized === "") return;
			inspect.mutate(normalized);
		},
		[inspect],
	);

	useEffect(() => {
		if (inspectedRef.current) return;
		if (search.code !== undefined && search.code !== "") {
			inspectedRef.current = true;
			runInspect(search.code);
		}
	}, [runInspect, search.code]);

	if (session.data === null || session.data === undefined) {
		return (
			<Container size="xs" py="xl">
				<Card withBorder padding="lg" radius="lg" maw={480} mx="auto">
					<Stack gap="md">
						<Title order={1} size="h2">
							{t("auth.activateTitle")}
						</Title>
						<Alert color="yellow" variant="light">
							{t("auth.activateLoginFirst")}
						</Alert>
						<Button component={Link} to="/login">
							{t("auth.signIn")}
						</Button>
					</Stack>
				</Card>
			</Container>
		);
	}

	const device = inspect.data;

	return (
		<Container size="xs" py="xl">
			<Card withBorder padding="lg" radius="lg" maw={520} mx="auto">
				<Stack gap="md">
					<Title order={1} size="h2">
						{t("auth.activateTitle")}
					</Title>
					<Text size="sm" c="dimmed">
						{t("auth.activateHint")}
					</Text>
					{inspect.isError && (
						<Alert color="red" variant="light">
							{t("auth.activateInvalid")}
						</Alert>
					)}
					{done ? (
						<>
							<Alert color="green" variant="light">
								{t("auth.activateSuccess")}
							</Alert>
							<Group>
								<Button
									variant="light"
									onClick={() => void navigate({ to: "/" })}
								>
									{t("auth.activateDone")}
								</Button>
								<Code>{code.trim().toUpperCase()}</Code>
							</Group>
						</>
					) : (
						<>
							<form
								onSubmit={(event) => {
									event.preventDefault();
									runInspect(code);
								}}
							>
								<Stack gap="sm">
									<TextInput
										label={t("auth.activateCode")}
										value={code}
										onChange={(event) => setCode(event.currentTarget.value)}
										autoCapitalize="characters"
										maxLength={12}
										required
									/>
									<Button type="submit" loading={inspect.isPending}>
										{t("auth.activateCheck")}
									</Button>
								</Stack>
							</form>
							{device !== undefined && (
								<Card withBorder padding="md" radius="md">
									<Stack gap="xs">
										<Text fw={600}>
											{device.device_name} · {device.platform}
										</Text>
										<Text size="sm" c="dimmed">
											{t("auth.activateDeviceHint")}
										</Text>
										<Button
											color="green"
											loading={approve.isPending}
											onClick={() =>
												approve.mutate(code.trim().toUpperCase(), {
													onSuccess: () => setDone(true),
												})
											}
										>
											{t("auth.activateApprove")}
										</Button>
									</Stack>
								</Card>
							)}
						</>
					)}
				</Stack>
			</Card>
		</Container>
	);
}
