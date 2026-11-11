import { type ReactNode, useEffect, useRef } from "react";
import { isServerConfigured } from "../api/setup";
import { emitLocalReset } from "./reset";
import { useSession } from "./session";
import { nextSessionResetState } from "./sessionReset";

// Следит за переходом сессии user → null и эмитит событие очистки. На
// холодном старте без входа (undefined → null) reset=false, поэтому
// сохранённые на устройстве данные не удаляются до первого логина.
export function SessionResetProvider({ children }: { children: ReactNode }) {
	const session = useSession(isServerConfigured());
	const hadSessionRef = useRef(false);

	useEffect(() => {
		const decision = nextSessionResetState(hadSessionRef.current, session.data);
		hadSessionRef.current = decision.hadSession;
		if (decision.reset) {
			emitLocalReset();
		}
	}, [session.data]);

	return <>{children}</>;
}
