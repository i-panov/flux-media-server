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

const HASH_PREFIX = /^#/;
const NON_DIGITS = /\D/g;

export function ActivatePage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const search = useSearch({ from: "/activate" });
	const session = useSession();
	const inspect = useInspectDeviceCodeMutation();
	const approve = useApproveDeviceCodeMutation();
	const [code, setCode] = useState("");
	const [done, setDone] = useState(false);
	const inspectedRef = useRef(false);

	const runInspect = useCallback(
		(value: string) => {
			const normalized = value.replace(NON_DIGITS, "").slice(0, 6);
			if (normalized.length !== 6) return;
			inspect.mutate(normalized);
		},
		[inspect],
	);

	// Код приходит во фрагменте (#code=482913): он не уходит на сервер
	// при загрузке страницы. Query оставлен для старых ссылок.
	useEffect(() => {
		if (inspectedRef.current) return;
		const hash = new URLSearchParams(
			window.location.hash.replace(HASH_PREFIX, ""),
		);
		const fromHash = hash.get("code") ?? "";
		const raw = fromHash === "" ? (search.code ?? "") : fromHash;
		const normalized = raw.replace(NON_DIGITS, "").slice(0, 6);
		if (normalized.length !== 6) return;
		inspectedRef.current = true;
		setCode(normalized);
		runInspect(normalized);
		window.history.replaceState(null, "", window.location.pathname);
	}, [runInspect, search.code]);

	const codeDigits = code.replace(/\D/g, "").slice(0, 6);
	const displayCode =
		codeDigits.length > 3
			? `${codeDigits.slice(0, 3)} ${codeDigits.slice(3)}`
			: codeDigits;

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
								<Code>{displayCode}</Code>
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
										value={displayCode}
										onChange={(event) =>
											setCode(
												event.currentTarget.value
													.replace(/\D/g, "")
													.slice(0, 6),
											)
										}
										inputMode="numeric"
										autoComplete="one-time-code"
										maxLength={7}
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
												approve.mutate(codeDigits, {
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
