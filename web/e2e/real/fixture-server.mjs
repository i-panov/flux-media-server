import { readFileSync } from "node:fs";
import { createServer } from "node:http";

const video = readFileSync(new URL("../fixtures/video.mp4", import.meta.url));
const server = createServer((req, res) => {
	if (req.url === "/video.mp4") {
		res.writeHead(200, {
			"Content-Type": "video/mp4",
			"Content-Length": String(video.length),
			"Accept-Ranges": "bytes",
		});
		res.end(video);
		return;
	}
	res.writeHead(404).end();
});
server.listen(18082, "0.0.0.0");
