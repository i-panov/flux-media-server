import { z } from "zod";
import { apiFetch } from "./client";

const authUserSchema = z.object({
	id: z.number(),
	email: z.string(),
	is_admin: z.boolean(),
});

export type AuthUser = z.infer<typeof authUserSchema>;

const requestCodeSchema = z.object({
	message: z.string(),
	// Код приходит только от сервера в debug-режиме — для локальной
	// разработки без почты.
	code: z.string().optional(),
});

type RequestCodeResponse = z.infer<typeof requestCodeSchema>;

const tokenPairSchema = z.object({
	token: z.string(),
	refresh_token: z.string(),
});

const verifyCodeSchema = tokenPairSchema.extend({
	user: authUserSchema,
});

type VerifyCodeResponse = z.infer<typeof verifyCodeSchema>;

export async function requestCode(email: string): Promise<RequestCodeResponse> {
	const body = await apiFetch<unknown>("/auth/request-code", {
		method: "POST",
		body: JSON.stringify({ email }),
	});
	return requestCodeSchema.parse(body);
}

export async function verifyCode(
	email: string,
	code: string,
): Promise<VerifyCodeResponse> {
	const body = await apiFetch<unknown>("/auth/verify-code", {
		method: "POST",
		body: JSON.stringify({ email, code }),
	});
	return verifyCodeSchema.parse(body);
}

export async function fetchMe(signal?: AbortSignal): Promise<AuthUser> {
	const body = await apiFetch<unknown>("/auth/me", { signal });
	return authUserSchema.parse(body);
}

export async function logout(): Promise<void> {
	await apiFetch<unknown>("/auth/logout", {
		method: "POST",
		body: "{}",
	});
}
