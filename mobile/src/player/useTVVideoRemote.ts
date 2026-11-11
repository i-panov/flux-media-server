import { useTVEventHandler } from "react-native";
import { isTV } from "../tv/profile";

// D-pad/медиа-клавиши телевизора: play/pause и seek без фокуса на кнопках.
export function useTVVideoRemote({
	position,
	seek,
	toggle,
}: {
	position: number;
	seek: (seconds: number) => void;
	toggle: () => void;
}): void {
	useTVEventHandler((event) => {
		if (!isTV) {
			return;
		}
		switch (event.eventType) {
			case "playPause":
				toggle();
				break;
			case "left":
				seek(position - 10);
				break;
			case "right":
				seek(position + 10);
				break;
			case "rewind":
				seek(position - 30);
				break;
			case "fastForward":
				seek(position + 30);
				break;
			default:
				break;
		}
	});
}
