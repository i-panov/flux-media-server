import {
	type AudioQueueState,
	emptyQueue,
	type RepeatMode,
} from "@flux/shared";
import {
	type Dispatch,
	type SetStateAction,
	useCallback,
	useEffect,
	useRef,
	useState,
} from "react";
import {
	clearAudioQueue,
	loadAudioQueue,
	saveAudioQueue,
} from "./audioQueueStorage";

export interface PersistedAudioQueue {
	queueState: AudioQueueState;
	setQueueState: Dispatch<SetStateAction<AudioQueueState>>;
	played: ReadonlySet<number>;
	setPlayed: Dispatch<SetStateAction<ReadonlySet<number>>>;
	shuffle: boolean;
	setShuffle: Dispatch<SetStateAction<boolean>>;
	repeat: RepeatMode;
	setRepeat: Dispatch<SetStateAction<RepeatMode>>;
	hydrated: boolean;
	/** Любое действие пользователя с очередью/режимами. */
	markUserAction: () => void;
}

// Очередь и режимы хранятся одним снимком в AsyncStorage. Восстановление
// не должно перетирать действие, которое пользователь успел сделать, пока
// AsyncStorage отвечал, а записи должны идти строго по порядку: иначе
// старый снимок мог бы финишировать после нового.
export function useAudioQueueState(): PersistedAudioQueue {
	const [queueState, setQueueState] = useState<AudioQueueState>(emptyQueue);
	const [played, setPlayed] = useState<ReadonlySet<number>>(new Set());
	const [shuffle, setShuffle] = useState(false);
	const [repeat, setRepeat] = useState<RepeatMode>("off");
	const [hydrated, setHydrated] = useState(false);
	const userTouchedRef = useRef(false);
	const persistChain = useRef<Promise<void>>(Promise.resolve());

	const markUserAction = useCallback(() => {
		userTouchedRef.current = true;
	}, []);

	useEffect(() => {
		let active = true;
		void loadAudioQueue().then((restored) => {
			if (!active) {
				return;
			}
			// Пользователь уже поставил трек/изменил режим — поздний ответ
			// хранилища не должен вернуть старую очередь поверх его выбора.
			if (restored !== null && !userTouchedRef.current) {
				setQueueState(restored.queue);
				setPlayed(restored.played);
				setShuffle(restored.shuffle);
				setRepeat(restored.repeat);
			}
			setHydrated(true);
		});
		return () => {
			active = false;
		};
	}, []);

	// Очередь/режимы пишутся одним ключом, пока очередь не пуста. Пустую
	// очередь не храним: после clear рестарт не должен воскрешать трек.
	// Promise-цепочка сохраняет порядок записей при быстрой смене треков.
	useEffect(() => {
		if (!hydrated) {
			return;
		}
		const empty = queueState.items.length === 0;
		const snapshot = { queue: queueState, played, shuffle, repeat };
		const write = empty
			? () => clearAudioQueue()
			: () => saveAudioQueue(snapshot);
		persistChain.current = persistChain.current.then(write).catch(() => {
			// Ошибки хранилища уже подавлены в audioQueueStorage.
		});
	}, [hydrated, played, queueState, repeat, shuffle]);

	return {
		queueState,
		setQueueState,
		played,
		setPlayed,
		shuffle,
		setShuffle,
		repeat,
		setRepeat,
		hydrated,
		markUserAction,
	};
}
