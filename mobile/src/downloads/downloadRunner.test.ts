import type { Media } from "@flux/shared";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { DownloadEntry, DownloadFailure } from "./downloadStore";
import { serializeDownloadIndex } from "./downloadStore";

interface FsInfo {
	exists: boolean;
	isDirectory: boolean;
	size: number;
}

interface MockTask {
	readonly uri: string;
	readonly fileUri: string;
	readonly options: unknown;
	readonly callback: (progress: {
		totalBytesWritten: number;
		totalBytesExpectedToWrite: number;
	}) => void;
}

const state = vi.hoisted(() => {
	const fs = new Map<string, FsInfo>();
	const children = new Map<string, string[]>();
	return {
		documentDirectory: "file:///docs/" as string | null,
		fs,
		children,
		deleted: [] as string[],
		deleteRejects: false,
		moved: [] as { from: string; to: string }[],
		cancelCalls: 0,
		authCalls: [] as string[],
		indexValue: null as string | null,
		persistValue: null as string | null,
		downloadFactory: (() => Promise.resolve(undefined)) as (
			task: MockTask,
		) => Promise<unknown>,
		lastTask: null as MockTask | null,
	};
});

vi.mock("expo-file-system/legacy", () => ({
	get documentDirectory() {
		return state.documentDirectory;
	},
	getInfoAsync: (path: string) => {
		return Promise.resolve(
			state.fs.get(path) ?? { exists: false, isDirectory: false },
		);
	},
	makeDirectoryAsync: (path: string) => {
		state.fs.set(path, { exists: true, isDirectory: true, size: 0 });
		state.children.set(path, state.children.get(path) ?? []);
		return Promise.resolve();
	},
	deleteAsync: (path: string) => {
		if (state.deleteRejects) {
			return Promise.reject(new Error("fs"));
		}
		state.deleted.push(path);
		state.fs.delete(path);
		state.children.delete(path);
		return Promise.resolve();
	},
	readDirectoryAsync: (path: string) => {
		return Promise.resolve(state.children.get(path) ?? []);
	},
	moveAsync: ({ from, to }: { from: string; to: string }) => {
		state.moved.push({ from, to });
		const info = state.fs.get(from);
		if (info !== undefined) {
			state.fs.delete(from);
			state.fs.set(to, info);
		}
		return Promise.resolve();
	},
	createDownloadResumable: (
		uri: string,
		fileUri: string,
		options: unknown,
		callback: MockTask["callback"],
	) => {
		const task: MockTask = { uri, fileUri, options, callback };
		state.lastTask = task;
		return {
			downloadAsync: () => state.downloadFactory(task),
			cancelAsync: () => {
				state.cancelCalls += 1;
				return Promise.resolve();
			},
		};
	},
}));

vi.mock("@react-native-async-storage/async-storage", () => ({
	default: {
		getItem: () => Promise.resolve(state.indexValue),
		setItem: (_key: string, value: string) => {
			state.persistValue = value;
			return Promise.resolve();
		},
	},
}));

vi.mock("../media/source", () => ({
	authSource: (path: string) => {
		state.authCalls.push(path);
		return Promise.resolve({
			uri: `https://srv${path}`,
			headers: { Authorization: "Bearer t" },
		});
	},
	streamPath: (id: number) => `/media/${id}/stream`,
}));

const { hydrateDownloads, removeFile, runDownload } = await import(
	"./downloadRunner"
);

const DOCUMENT_DIRECTORY = "file:///docs/";
const DOWNLOADS_DIRECTORY = "file:///docs/downloads/";
const MEDIA_5 = "media-5.mp4";
const MEDIA_1_M4A = "media-1.m4a";
const MEDIA_1_MP4 = "media-1.mp4";

function media(overrides: Partial<Media> = {}): Media {
	return {
		id: 1,
		title: "Трек",
		filename: "track.m4a",
		year: 2026,
		description: "",
		type: "audio",
		artists: [],
		album: "",
		genre: "",
		duration: 120,
		width: 0,
		height: 0,
		file_size: 1,
		thumbnail_url: "",
		cover_url: "",
		view_count: 0,
		created_at: "2026-01-01T00:00:00Z",
		source_url: "",
		...overrides,
	};
}

function seedDirectory(path = DOWNLOADS_DIRECTORY): void {
	state.fs.set(path, { exists: true, isDirectory: true, size: 0 });
	state.children.set(path, []);
}

function seedFile(path: string, size: number): void {
	state.fs.set(path, { exists: true, isDirectory: false, size });
	const slash = path.lastIndexOf("/");
	const directory = path.slice(0, slash + 1);
	const name = path.slice(slash + 1);
	state.children.set(directory, [
		...(state.children.get(directory) ?? []),
		name,
	]);
}

function entry(mediaId: number, filename: string): DownloadEntry {
	return {
		mediaId,
		title: `Медиа ${mediaId}`,
		type: "video",
		filename,
		size: 100,
		updatedAt: 100,
	};
}

interface RunCalls {
	readonly failures: DownloadFailure[];
	readonly updates: (number | null)[];
	readonly removed: number[];
	readonly entries: DownloadEntry[][];
	readonly persisted: DownloadEntry[][];
}

function makeRun(
	calls: RunCalls = {
		failures: [],
		updates: [],
		removed: [],
		entries: [],
		persisted: [],
	},
) {
	const run = {
		isCurrent: (mediaId: number, token: number) => mediaId === 1 && token === 1,
		fail: (_mediaId: number, failure: DownloadFailure) => {
			calls.failures.push(failure);
		},
		updateActive: (_mediaId: number, patch: { progress: number | null }) => {
			calls.updates.push(patch.progress);
		},
		removeActive: (mediaId: number) => {
			calls.removed.push(mediaId);
		},
		setEntries: (entries: DownloadEntry[]) => {
			calls.entries.push(entries);
		},
		persist: (entries: readonly DownloadEntry[]) => {
			calls.persisted.push([...entries]);
		},
		tasks: new Map(),
		partPaths: new Map(),
		entries: () => [],
		active: () => [{ media: { id: 1 }, status: "downloading" as const }],
	};
	return { run, calls };
}

interface HydrationCalls {
	readonly entries: DownloadEntry[][];
	readonly persisted: DownloadEntry[][];
}

function makeHydration(calls: HydrationCalls = { entries: [], persisted: [] }) {
	return {
		context: {
			isMounted: () => true,
			setEntries: (entries: DownloadEntry[]) => {
				calls.entries.push(entries);
			},
			persist: (entries: readonly DownloadEntry[]) => {
				calls.persisted.push([...entries]);
			},
			activeCount: () => 0,
		},
		calls,
	};
}

beforeEach(() => {
	state.documentDirectory = DOCUMENT_DIRECTORY;
	state.fs.clear();
	state.children.clear();
	state.deleted = [];
	state.deleteRejects = false;
	state.moved = [];
	state.cancelCalls = 0;
	state.authCalls = [];
	state.indexValue = null;
	state.persistValue = null;
	state.lastTask = null;
	seedDirectory();
	state.downloadFactory = (task) => {
		task.callback({ totalBytesWritten: 100, totalBytesExpectedToWrite: 100 });
		seedFile(task.fileUri, 100);
		return Promise.resolve({
			status: 200,
			headers: { "content-length": "100" },
			uri: task.fileUri,
			mimeType: "audio/mp4",
		});
	};
});

describe("runDownload", () => {
	it("публикует неизвестную длину как null, а не 0%", async () => {
		state.downloadFactory = (task) => {
			task.callback({ totalBytesWritten: 10, totalBytesExpectedToWrite: -1 });
			seedFile(task.fileUri, 100);
			return Promise.resolve({
				status: 200,
				headers: { "content-length": "100" },
				uri: task.fileUri,
				mimeType: null,
			});
		};
		state.documentDirectory = DOCUMENT_DIRECTORY;
		const { run, calls } = makeRun();

		await runDownload(media(), 1, run);

		expect(calls.updates).toContain(null);
		expect(calls.updates).not.toContain(0);
		expect(state.moved[0]?.to).toBe(`${DOWNLOADS_DIRECTORY}media-1.m4a`);
	});

	it("отвергает не-2xx статус и удаляет .part", async () => {
		state.downloadFactory = (task) => {
			seedFile(task.fileUri, 12);
			return Promise.resolve({
				status: 500,
				headers: {},
				uri: task.fileUri,
				mimeType: null,
			});
		};
		const { run, calls } = makeRun();

		await runDownload(media(), 1, run);

		expect(calls.failures).toEqual(["status"]);
		expect(state.moved).toHaveLength(0);
		expect(state.deleted).toContain(`${DOWNLOADS_DIRECTORY}media-1.m4a.part`);
	});

	it("не коммитит 206-фрагмент как целый файл", async () => {
		state.downloadFactory = (task) => {
			seedFile(task.fileUri, 50);
			return Promise.resolve({
				status: 206,
				headers: {
					"content-length": "50",
					"content-range": "bytes 0-49/100",
				},
				uri: task.fileUri,
				mimeType: null,
			});
		};
		const { run, calls } = makeRun();

		await runDownload(media(), 1, run);

		expect(calls.failures).toEqual(["size"]);
		expect(state.moved).toHaveLength(0);
	});

	it("принимает полный 206 с Content-Range от 0 до total-1", async () => {
		state.downloadFactory = (task) => {
			seedFile(task.fileUri, 100);
			return Promise.resolve({
				status: 206,
				headers: {
					"content-length": "100",
					"content-range": "bytes 0-99/100",
				},
				uri: task.fileUri,
				mimeType: null,
			});
		};
		const { run, calls } = makeRun();

		await runDownload(media(), 1, run);

		expect(calls.failures).toEqual([]);
		expect(state.moved).toHaveLength(1);
		expect(state.moved[0]?.to).toBe(`${DOWNLOADS_DIRECTORY}media-1.m4a`);
		expect(calls.persisted[0]?.[0]?.filename).toBe(MEDIA_1_M4A);
	});

	it("прерывает зависшую загрузку по таймауту", async () => {
		state.downloadFactory = () => new Promise(() => undefined);
		const { run, calls } = makeRun();

		await runDownload(media(), 1, run, 5);

		expect(calls.failures).toEqual(["timeout"]);
		expect(state.cancelCalls).toBeGreaterThan(0);
		expect(state.moved).toHaveLength(0);
	});
});

describe("removeFile", () => {
	it("удаляет файл идемпотентно", async () => {
		const path = `${DOWNLOADS_DIRECTORY}media-1.mp4`;
		seedFile(path, 100);

		await removeFile(path);

		expect(state.deleted).toContain(path);
	});

	it("проглатывает ошибку удаления: индекс уже очищен вызывающим", async () => {
		state.deleteRejects = true;

		await expect(
			removeFile(`${DOWNLOADS_DIRECTORY}media-1.mp4`),
		).resolves.toBeUndefined();
		expect(state.deleted).toEqual([]);
	});
});

describe("hydrateDownloads", () => {
	it("удаляет осиротевшие final-файлы и .part, оставляя записи индекса", async () => {
		const kept = entry(1, MEDIA_1_MP4);
		state.indexValue = serializeDownloadIndex(
			[kept],
			"https://srv.example/api",
		);
		seedFile(`${DOWNLOADS_DIRECTORY}media-1.mp4`, 100);
		seedFile(`${DOWNLOADS_DIRECTORY}media-9.mp4`, 20);
		seedFile(`${DOWNLOADS_DIRECTORY}media-9.mp4.part`, 5);
		const { context, calls } = makeHydration();

		await hydrateDownloads(context, "https://srv.example/api");

		expect(calls.entries[0]?.map((item) => item.mediaId)).toEqual([1]);
		expect(state.deleted).toContain(`${DOWNLOADS_DIRECTORY}media-9.mp4`);
		expect(state.deleted).toContain(`${DOWNLOADS_DIRECTORY}media-9.mp4.part`);
		expect(state.deleted).not.toContain(`${DOWNLOADS_DIRECTORY}media-1.mp4`);
	});

	it("игнорирует индекс другого сервера и удаляет его файлы", async () => {
		state.indexValue = serializeDownloadIndex(
			[entry(1, MEDIA_1_MP4)],
			"https://old.example/api",
		);
		seedFile(`${DOWNLOADS_DIRECTORY}media-1.mp4`, 100);
		const { context, calls } = makeHydration();

		await hydrateDownloads(context, "https://new.example/api");

		expect(calls.entries[0]).toEqual([]);
		expect(state.deleted).toContain(`${DOWNLOADS_DIRECTORY}media-1.mp4`);
		expect(calls.persisted[0]).toEqual([]);
	});

	it("восстанавливает legacy path в filename после переезда контейнера", async () => {
		state.indexValue = JSON.stringify({
			version: 1,
			items: [
				{
					...entry(5, MEDIA_5),
					filename: undefined,
					path: "file:///old/container/downloads/media-5.mp4",
				},
			],
		});
		seedFile(`${DOWNLOADS_DIRECTORY}${MEDIA_5}`, 100);
		const { context, calls } = makeHydration();

		await hydrateDownloads(context, "https://new.example/api");

		expect(calls.entries[0]?.[0]?.filename).toBe(MEDIA_5);
		expect(calls.persisted[0]?.[0]?.filename).toBe(MEDIA_5);
	});
});
