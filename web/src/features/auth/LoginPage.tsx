import {
	Alert,
	Card,
	Container,
	Stack,
	Text,
	TextInput,
	Title,
} from "@mantine/core";
import { setFocus } from "@noriginmedia/norigin-spatial-navigation";
import { useNavigate } from "@tanstack/react-router";
import type { TFunction } from "i18next";
import { type FormEvent, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import { getWebDeviceId } from "../../api/deviceId";
import {
	useRequestCodeMutation,
	useVerifyCodeMutation,
} from "../../api/session";
import { TVButton, TVFocusScope, useTVFocusable } from "../tv/tvFocus";
import { DeviceQrLogin } from "./DeviceQrLogin";

type AuthStep = "request" | "verify";

const ARROW_DOWN = "down";
const ARROW_UP = "up";
const LOGIN_PAGE_KEY = "login-page";
const LOGIN_EMAIL_KEY = "login-email";
const LOGIN_CODE_KEY = "login-code";
const LOGIN_SUBMIT_KEY = "login-submit";
const LOGIN_VERIFY_KEY = "login-verify";
const LOGIN_CHANGE_EMAIL_KEY = "login-change-email";

function toAuthError(t: TFunction, error: unknown, step: AuthStep): string {
	if (error instanceof ApiError) {
		if (error.status === 429) {
			return t("auth.tooManyRequests");
		}
		if (step === "verify" && error.status === 401) {
			return t("auth.invalidCode");
		}
		if (error.message.length > 0) {
			return error.message;
		}
	}
	return t("auth.genericError");
}

// eslint-disable-next-line max-lines-per-function -- экран держит OTP и QR-вход.
export function LoginPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const [email, setEmail] = useState("");
	const [codeSent, setCodeSent] = useState(false);
	const [code, setCode] = useState("");
	const [debugCode, setDebugCode] = useState<string | null>(null);
	const [error, setError] = useState<string | null>(null);
	const [qrMode, setQrMode] = useState<"auto" | "on" | "off">("auto");

	const requestMutation = useRequestCodeMutation();
	const verifyMutation = useVerifyCodeMutation();
	const pending = requestMutation.isPending || verifyMutation.isPending;
	// ТВ-режим: корень страницы — spatial-секция, форма внутри —
	// контент секции.
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>(LOGIN_PAGE_KEY);
	const showQr = qrMode === "on" || (qrMode === "auto" && tvMode);

	const requestCode = () => {
		if (pending) {
			return;
		}
		setError(null);
		requestMutation.mutate(email.trim(), {
			onSuccess: (data) => {
				setCodeSent(true);
				setDebugCode(data.code ?? null);
			},
			onError: (requestError) => {
				setError(toAuthError(t, requestError, "request"));
			},
		});
	};

	const verifyCode = () => {
		if (pending) {
			return;
		}
		setError(null);
		verifyMutation.mutate(
			{ email: email.trim(), code: code.trim(), deviceId: getWebDeviceId() },
			{
				onSuccess: () => {
					void navigate({ to: "/" });
				},
				onError: (verifyError) => {
					setError(toAuthError(t, verifyError, "verify"));
				},
			},
		);
	};

	// Поля и кнопки — самостоятельные spatial-цели: иначе на Tizen пульт
	// видел только корень страницы и шапку. Enter в поле отправляет шаг,
	// Enter на кнопке повторяет клик. Стрелки вниз/вверх ведём явно:
	// у полей ввода геометрическая навигация библиотеки не срабатывает.
	const focusOnArrow = (key: string, direction: string) => {
		return (actual: string): boolean => {
			if (actual !== direction) {
				return true;
			}
			void setFocus(key);
			return false;
		};
	};
	const { targetRef: emailRef } = useTVFocusable<HTMLInputElement>(
		LOGIN_EMAIL_KEY,
		requestCode,
		focusOnArrow(LOGIN_SUBMIT_KEY, ARROW_DOWN),
	);
	const { targetRef: codeRef } = useTVFocusable<HTMLInputElement>(
		LOGIN_CODE_KEY,
		verifyCode,
		focusOnArrow(LOGIN_VERIFY_KEY, ARROW_DOWN),
	);

	// После отправки письма фокус переезжает на код: route-focus срабатывает
	// только на смену пути, а шаг формы меняется внутри /login.
	useEffect(() => {
		if (!tvMode) {
			return;
		}
		const focusKey = codeSent ? LOGIN_CODE_KEY : LOGIN_EMAIL_KEY;
		const timer = setTimeout(() => {
			void setFocus(focusKey);
		}, 80);
		return () => clearTimeout(timer);
	}, [codeSent, tvMode]);

	const handleRequestCode = (event: FormEvent) => {
		event.preventDefault();
		requestCode();
	};

	const handleVerify = (event: FormEvent) => {
		event.preventDefault();
		verifyCode();
	};

	const handleChangeEmail = () => {
		setCodeSent(false);
		setCode("");
		setDebugCode(null);
		setError(null);
	};

	if (showQr) {
		return (
			<Container
				size="xs"
				px={{ base: "md", sm: "lg" }}
				py={{ base: "xl", md: 96, xl: 120 }}
				ref={tvRef}
				tabIndex={tvMode ? -1 : undefined}
				data-tv-page-root="true"
				data-tv-focus-key={LOGIN_PAGE_KEY}
			>
				<TVFocusScope focusKey={LOGIN_PAGE_KEY}>
					<Card
						withBorder
						padding="lg"
						radius="lg"
						shadow="sm"
						maw={480}
						mx="auto"
						data-testid="login-card"
					>
						<Stack gap="lg">
							<Title order={1} size="h2" ta="center">
								{t("auth.qrTitle")}
							</Title>
							<Text size="sm" c="dimmed" ta="center">
								{t("auth.qrSubtitle")}
							</Text>
							<DeviceQrLogin />
							<TVButton
								focusKey="login-qr-back"
								variant="subtle"
								onClick={() => setQrMode("off")}
							>
								{t("auth.qrBackToOtp")}
							</TVButton>
						</Stack>
					</Card>
				</TVFocusScope>
			</Container>
		);
	}

	return (
		<Container
			size="xs"
			px={{ base: "md", sm: "lg" }}
			py={{ base: "xl", md: 96, xl: 120 }}
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-page-root="true"
			data-tv-focus-key={LOGIN_PAGE_KEY}
		>
			<TVFocusScope focusKey={LOGIN_PAGE_KEY}>
				<Card
					withBorder
					padding="lg"
					radius="lg"
					shadow="sm"
					maw={480}
					mx="auto"
					data-testid="login-card"
				>
					<Stack gap="lg">
						<Stack gap="xs" align="center">
							<img
								src="/favicon.svg"
								alt=""
								className="h-14 w-14 shrink-0"
								aria-hidden="true"
							/>
							<Title order={1} size="h2" ta="center">
								{t("auth.title")}
							</Title>
							<Text size="sm" c="dimmed" ta="center">
								{t("auth.subtitle")}
							</Text>
						</Stack>

						{error !== null && (
							<Alert color="red" variant="light">
								{error}
							</Alert>
						)}

						{codeSent ? (
							<form onSubmit={handleVerify}>
								<Stack gap="md">
									<Text size="sm">
										{t("auth.codeSent", { email: email.trim() })}
									</Text>
									{debugCode !== null && (
										<Alert color="yellow" variant="light">
											{t("auth.devCode", { code: debugCode })}
										</Alert>
									)}
									<TextInput
										ref={codeRef}
										label={t("auth.code")}
										inputMode="numeric"
										autoComplete="one-time-code"
										autoFocus
										required
										value={code}
										onChange={(event) => setCode(event.currentTarget.value)}
										disabled={pending}
									/>
									<TVButton
										focusKey={LOGIN_VERIFY_KEY}
										type="submit"
										onTVArrowPress={focusOnArrow(LOGIN_CODE_KEY, ARROW_UP)}
										loading={verifyMutation.isPending}
										fullWidth
									>
										{t("auth.signIn")}
									</TVButton>
									<TVButton
										focusKey={LOGIN_CHANGE_EMAIL_KEY}
										variant="subtle"
										onTVArrowPress={focusOnArrow(LOGIN_VERIFY_KEY, ARROW_UP)}
										onClick={handleChangeEmail}
										disabled={pending}
									>
										{t("auth.changeEmail")}
									</TVButton>
								</Stack>
							</form>
						) : (
							<form onSubmit={handleRequestCode}>
								<Stack gap="md">
									<TextInput
										ref={emailRef}
										label={t("auth.email")}
										placeholder={t("auth.emailPlaceholder")}
										type="email"
										autoComplete="email"
										autoFocus
										required
										value={email}
										onChange={(event) => setEmail(event.currentTarget.value)}
										disabled={pending}
									/>
									<TVButton
										focusKey={LOGIN_SUBMIT_KEY}
										type="submit"
										onTVArrowPress={focusOnArrow(LOGIN_EMAIL_KEY, ARROW_UP)}
										loading={requestMutation.isPending}
										fullWidth
									>
										{t("auth.getCode")}
									</TVButton>
								</Stack>
							</form>
						)}
						<TVButton
							focusKey="login-show-qr"
							variant="subtle"
							onClick={() => setQrMode("on")}
						>
							{t("auth.qrUse")}
						</TVButton>
					</Stack>
				</Card>
			</TVFocusScope>
		</Container>
	);
}
