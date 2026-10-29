import {
	Alert,
	Button,
	Card,
	Container,
	Stack,
	Text,
	TextInput,
	Title,
} from "@mantine/core";
import { useNavigate } from "@tanstack/react-router";
import type { TFunction } from "i18next";
import { Play } from "lucide-react";
import { type FormEvent, useState } from "react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import {
	useRequestCodeMutation,
	useVerifyCodeMutation,
} from "../../api/session";

type AuthStep = "request" | "verify";

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

export function LoginPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const [email, setEmail] = useState("");
	const [codeSent, setCodeSent] = useState(false);
	const [code, setCode] = useState("");
	const [debugCode, setDebugCode] = useState<string | null>(null);
	const [error, setError] = useState<string | null>(null);

	const requestMutation = useRequestCodeMutation();
	const verifyMutation = useVerifyCodeMutation();
	const pending = requestMutation.isPending || verifyMutation.isPending;

	const handleRequestCode = (event: FormEvent) => {
		event.preventDefault();
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

	const handleVerify = (event: FormEvent) => {
		event.preventDefault();
		setError(null);
		verifyMutation.mutate(
			{ email: email.trim(), code: code.trim() },
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

	const handleChangeEmail = () => {
		setCodeSent(false);
		setCode("");
		setDebugCode(null);
		setError(null);
	};

	return (
		<Container
			size="xs"
			px={{ base: "md", sm: "lg" }}
			py={{ base: "xl", md: 96, xl: 120 }}
		>
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
						<div className="flux-brand-gradient grid h-12 w-12 place-items-center rounded-xl text-white">
							<Play size={24} fill="currentColor" />
						</div>
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
									label={t("auth.code")}
									inputMode="numeric"
									autoComplete="one-time-code"
									required
									value={code}
									onChange={(event) => setCode(event.currentTarget.value)}
									disabled={pending}
								/>
								<Button
									type="submit"
									loading={verifyMutation.isPending}
									fullWidth
								>
									{t("auth.signIn")}
								</Button>
								<Button
									variant="subtle"
									onClick={handleChangeEmail}
									disabled={pending}
								>
									{t("auth.changeEmail")}
								</Button>
							</Stack>
						</form>
					) : (
						<form onSubmit={handleRequestCode}>
							<Stack gap="md">
								<TextInput
									label={t("auth.email")}
									placeholder={t("auth.emailPlaceholder")}
									type="email"
									autoComplete="email"
									required
									value={email}
									onChange={(event) => setEmail(event.currentTarget.value)}
									disabled={pending}
								/>
								<Button
									type="submit"
									loading={requestMutation.isPending}
									fullWidth
								>
									{t("auth.getCode")}
								</Button>
							</Stack>
						</form>
					)}
				</Stack>
			</Card>
		</Container>
	);
}
