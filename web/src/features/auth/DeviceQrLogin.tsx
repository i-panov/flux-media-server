import { Alert, Button, Code, Group, Loader, Stack, Text } from "@mantine/core";
import { useNavigate } from "@tanstack/react-router";
import { useCallback, useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import type { DeviceCodeResponse } from "../../api/auth";
import { pollDeviceCode } from "../../api/auth";
import { getWebDeviceId } from "../../api/deviceId";
import {
	adoptSessionUser,
	useCreateDeviceCodeMutation,
} from "../../api/session";
import { QrCode } from "./QrCode";

// QR-вход для ТВ/приставки: показываем QR и короткий код, опрашиваем
// сервер, пока пользователь не подтвердит вход на телефоне/десктопе.
export function DeviceQrLogin() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const create = useCreateDeviceCodeMutation();
	const [data, setData] = useState<DeviceCodeResponse | null>(null);
	const [status, setStatus] = useState<
		"loading" | "waiting" | "expired" | "error"
	>("loading");
	const startedRef = useRef(false);

	const start = useCallback(() => {
		setStatus("loading");
		create.mutate(
			{ deviceId: getWebDeviceId(), deviceName: "Web TV", platform: "web-tv" },
			{
				onSuccess: (result) => {
					setData(result);
					setStatus("waiting");
				},
				onError: () => setStatus("error"),
			},
		);
	}, [create]);

	useEffect(() => {
		if (startedRef.current) return;
		startedRef.current = true;
		start();
	}, [start]);

	useEffect(() => {
		if (data === null || status !== "waiting") return;
		let cancelled = false;
		let timer: ReturnType<typeof setTimeout> | undefined;
		const tick = async () => {
			try {
				const result = await pollDeviceCode(data.device_code);
				if (cancelled) return;
				if (result.status === "ok") {
					adoptSessionUser(result.user);
					void navigate({ to: "/" });
					return;
				}
				if (result.status === "pending") {
					timer = setTimeout(() => void tick(), data.interval * 1000);
					return;
				}
				setStatus(result.status === "expired" ? "expired" : "error");
			} catch {
				if (!cancelled) setStatus("error");
			}
		};
		timer = setTimeout(() => void tick(), data.interval * 1000);
		return () => {
			cancelled = true;
			if (timer !== undefined) clearTimeout(timer);
		};
	}, [data, status, navigate]);

	if (status === "loading" || create.isPending) {
		return (
			<Stack align="center" gap="sm" py="md">
				<Loader />
				<Text size="sm" c="dimmed">
					{t("auth.qrLoading")}
				</Text>
			</Stack>
		);
	}

	if (status === "error" || data === null) {
		return (
			<Alert color="red" variant="light">
				{t("auth.qrError")}
			</Alert>
		);
	}

	if (status === "expired") {
		return (
			<Stack align="center" gap="sm">
				<Alert color="yellow" variant="light">
					{t("auth.qrExpired")}
				</Alert>
				<Button onClick={start}>{t("auth.qrRetry")}</Button>
			</Stack>
		);
	}

	return (
		<Stack align="center" gap="sm">
			<QrCode
				value={data.verification_uri_complete}
				label={t("auth.qrLabel")}
			/>
			<Text size="sm" c="dimmed" ta="center">
				{t("auth.qrHint")}
			</Text>
			<Group gap="xs">
				<Text size="sm">{t("auth.qrCode")}</Text>
				<Code fz="lg" data-testid="device-user-code">
					{data.user_code}
				</Code>
			</Group>
			<Text size="xs" c="dimmed" ta="center">
				{data.verification_uri}
			</Text>
			<Button variant="subtle" size="xs" onClick={start}>
				{t("auth.qrRetry")}
			</Button>
		</Stack>
	);
}
