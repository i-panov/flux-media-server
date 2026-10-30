import "../src/api/setup";
import { createQueryClient } from "@flux/shared";
import { QueryClientProvider } from "@tanstack/react-query";
import { Slot } from "expo-router";
import { useState } from "react";

export default function RootLayout() {
	const [client] = useState(createQueryClient);
	return (
		<QueryClientProvider client={client}>
			<Slot />
		</QueryClientProvider>
	);
}
