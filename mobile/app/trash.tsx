import { AuthGate } from "../src/components/AuthGate";
import { TrashScreenContent } from "../src/components/TrashScreenContent";

export default function TrashScreen() {
	return (
		<AuthGate>
			<TrashScreenContent />
		</AuthGate>
	);
}
