export type CollectionDialog =
	| { kind: "create" }
	| { kind: "rename" }
	| { kind: "move" }
	| { kind: "delete" }
	| { kind: "moveItems"; mediaIds: number[] }
	| null;
