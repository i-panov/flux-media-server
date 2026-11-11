import type { ViewStyle } from "react-native";
import { isTV } from "./profile";

// Единый focus-ring для D-pad: на телефоне ничего не меняет.
export function tvFocusStyle(
	focused: boolean,
	color: string,
): ViewStyle | undefined {
	if (!isTV || !focused) {
		return undefined;
	}
	return { borderColor: color, borderWidth: 2 };
}
