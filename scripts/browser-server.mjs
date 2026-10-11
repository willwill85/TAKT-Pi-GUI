// Local headless browser for the TAKT Pi GUI side panel.
// Speaks a tiny HTTP + SSE protocol on 127.0.0.1. Playwright (already installed
// for pi-web) drives Chromium; the user's Chrome is never launched.
import http from "node:http";
import { createRequire } from "node:module";

const require = createRequire("/Users/will/pi_gui/pi-web-custom/package.json");
const { chromium } = require("playwright");

const PORT = Number(process.env.PINATIVE_BROWSER_PORT || 0);
const HOST = "127.0.0.1";

let browser = null;
let page = null;
const clients = new Set();
let shotTimer = null;
let lastShot = "";
let lastTitle = "";

function send(event, data) {
  const line = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const res of clients) res.write(line);
}

async function ensurePage() {
  if (!browser) browser = await chromium.launch({ headless: true });
  if (!page || page.isClosed()) {
    const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1 });
    page = await context.newPage();
    page.on("framenavigated", (frame) => { if (frame === page.mainFrame()) send("nav", { url: page.url(), title: "" }); });
    page.on("console", (msg) => send("log", { text: msg.text().slice(0, 500) }));
  }
  return page;
}

async function shot() {
  const p = await ensurePage();
  const buf = await p.screenshot({ type: "jpeg", quality: 55 });
  const data = buf.toString("base64");
  if (data === lastShot) return;
  lastShot = data;
  let title = "";
  try { title = await p.title(); } catch { /* navigating */ }
  lastTitle = title;
  send("frame", { image: data, url: p.url(), title });
}

function watch(on) {
  if (shotTimer) { clearInterval(shotTimer); shotTimer = null; }
  if (on && clients.size) shotTimer = setInterval(() => { shot().catch(() => {}); }, 700);
}

async function act(body) {
  const p = await ensurePage();
  switch (body.op) {
    case "goto": {
      const url = /^https?:\/\//.test(body.url) ? body.url : "https://" + body.url;
      await p.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
      break;
    }
    case "back": await p.goBack({ timeout: 10000 }).catch(() => {}); break;
    case "forward": await p.goForward({ timeout: 10000 }).catch(() => {}); break;
    case "reload": await p.reload({ timeout: 15000 }).catch(() => {}); break;
    case "click": await p.mouse.click(body.x, body.y); break;
    case "type": await p.keyboard.type(String(body.text ?? ""), { delay: 8 }); break;
    case "key": await p.keyboard.press(body.key); break;
    case "scroll": await p.mouse.wheel(0, body.dy || 0); break;
    default: throw new Error("unknown op");
  }
  await shot();
  return { url: p.url() };
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost");
  res.setHeader("Access-Control-Allow-Origin", "*");
  if (req.method === "OPTIONS") { res.writeHead(204); res.end(); return; }
  try {
    if (url.pathname === "/events") {
      res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" });
      clients.add(res);
      watch(true);
      req.on("close", () => { clients.delete(res); if (!clients.size) watch(false); });
      send("hello", { ok: true });
      shot().catch(() => {});
      return;
    }
    if (url.pathname === "/frame") {
      await shot();
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ image: lastShot, url: page ? page.url() : "", title: lastTitle }));
      return;
    }
    if (url.pathname === "/act" && req.method === "POST") {
      const chunks = [];
      for await (const c of req) chunks.push(c);
      const body = JSON.parse(Buffer.concat(chunks).toString() || "{}");
      const result = await act(body);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(result));
      return;
    }
    res.writeHead(404); res.end();
  } catch (error) {
    send("error", { message: String(error.message || error).slice(0, 300) });
    res.writeHead(500, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: String(error.message || error) }));
  }
});

server.listen(PORT, HOST, () => {
  process.stdout.write(JSON.stringify({ port: server.address().port }) + "\n");
});

async function shutdown() {
  watch(false);
  if (browser) await browser.close().catch(() => {});
  process.exit(0);
}
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
