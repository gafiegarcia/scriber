#!/usr/bin/env node
/* eslint-disable @typescript-eslint/no-require-imports */

const fs = require("node:fs");
const http = require("node:http");
const net = require("node:net");
const path = require("node:path");
const { parseArgs } = require("node:util");

const ROOT = path.resolve(__dirname, "..");
const STANDALONE_DIR = path.join(ROOT, ".next", "standalone");
const STANDALONE_SERVER = path.join(STANDALONE_DIR, "server.js");
const CLI_BUNDLE = path.join(ROOT, ".scriber-cli", "index.cjs");

const HELP = `
scriber — local voice transcription powered by ElevenLabs Scribe v2

USAGE
  scriber [command] [options]

COMMANDS
  serve                          Start the web UI on localhost (default)
  transcribe <file>              Headless: transcribe an audio file, print JSON to stdout
  credits                        Show remaining ElevenLabs credits for the stored key
  help        (-h, --help)       Show this message
  version     (-v, --version)    Print the installed version

OPTIONS (serve)
  -p, --port <n>                 Preferred port (default: 7337, falls back to n+1 then random)
      --no-open                  Don't open the browser automatically

OPTIONS (transcribe)
  Input formats: .mp3, .m4a, .mp4, .wav, .webm, .ogg, .flac
  Output formats: .json, .srt, .md, .txt (picked from -o file extension)

  -o, --output <path...>         One or more output file paths; extension picks format.
                                 Repeat -o or list multiple paths after a single -o.
      --no-store                 Skip saving the result as a Note in ~/.scriber/.
      --language <code>          BCP-47 code (e.g. "en", "id"), or "auto".
                                 Overrides config default for this run.
      --diarize                  Enable speaker diarization (Speaker A/B/...).
      --num-speakers <n>         Speaker count hint (positive integer; requires --diarize).
      --tag-audio-events         Tag non-speech events (laughter, music, applause).
      --keyterm <term>           Add a keyterm for this run (repeatable; appended to
                                 the dictionary in ~/.scriber/config.json).
      --no-keyterms              Disable all keyterms for this run (ignores config dict).
      --title <text>             Note title override (default: input basename without ext).
  -q, --quiet                    Suppress stderr progress output.
  -h, --help                     Show transcribe-specific help.

  Exit codes: 0 ok · 1 usage/input error · 2 ElevenLabs/transcription error.

DATA
  Notes, audio, and config live in ~/.scriber/ (override with $SCRIBER_HOME).
  On macOS, the ElevenLabs API key lives in Keychain. Other platforms keep it in
  config.json. Set it once via the web UI (\`scriber\` → first-run modal or
  Settings → API Key).
`.trimStart();

function printHelp() {
  process.stdout.write(HELP);
}

function printVersion() {
  const pkg = require(path.join(ROOT, "package.json"));
  process.stdout.write(`${pkg.version}\n`);
}

function log(msg) {
  process.stdout.write(`${msg}\n`);
}

function logError(msg) {
  process.stderr.write(`${msg}\n`);
}

function isPortFree(port, host) {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.unref();
    server.once("error", () => resolve(false));
    server.once("listening", () => {
      server.close(() => resolve(true));
    });
    server.listen(port, host);
  });
}

async function findAvailablePort(preferred, host) {
  const candidates = [preferred, preferred + 1];
  for (const port of candidates) {
    if (await isPortFree(port, host)) return port;
    log(`Port ${port} is in use, trying the next one...`);
  }
  return new Promise((resolve, reject) => {
    const probe = net.createServer();
    probe.unref();
    probe.once("error", reject);
    probe.listen(0, host, () => {
      const address = probe.address();
      const port = typeof address === "object" && address ? address.port : null;
      probe.close(() => (port ? resolve(port) : reject(new Error("No free port"))));
    });
  });
}

function probeScriber(port, host) {
  return new Promise((resolve) => {
    const req = http.get(
      { host, port, path: "/api/health", timeout: 500 },
      (res) => {
        if (res.statusCode !== 200) {
          res.resume();
          return resolve(false);
        }
        let body = "";
        res.setEncoding("utf8");
        res.on("data", (chunk) => (body += chunk));
        res.on("end", () => {
          try {
            const parsed = JSON.parse(body);
            resolve(parsed.app === "scriber");
          } catch {
            resolve(false);
          }
        });
      }
    );
    req.on("error", () => resolve(false));
    req.on("timeout", () => {
      req.destroy();
      resolve(false);
    });
  });
}

async function findExistingScriber(preferred, host) {
  for (const port of [preferred, preferred + 1]) {
    if (await probeScriber(port, host)) return port;
  }
  return null;
}

async function openBrowser(url) {
  try {
    const { default: open } = await import("open");
    await open(url);
  } catch (err) {
    logError(`Could not open browser automatically: ${err.message}`);
    log(`Open ${url} in your browser.`);
  }
}

async function serve({ port: preferredPort, open: shouldOpen }) {
  if (!fs.existsSync(STANDALONE_SERVER)) {
    logError(
      `Scriber's production build is missing at ${STANDALONE_SERVER}.\n` +
        `If you installed via npm, please reinstall. If you're running from source, run \`npm run build\` first.`
    );
    process.exit(1);
  }

  const host = "127.0.0.1";

  const existingPort = await findExistingScriber(preferredPort, host);
  if (existingPort) {
    const existingUrl = `http://${host}:${existingPort}`;
    log("");
    log(`  Scriber is already running at ${existingUrl}.`);
    log(`  Reusing that instance — close the existing terminal to stop it.`);
    log("");
    if (shouldOpen) {
      await openBrowser(existingUrl);
    }
    return;
  }

  const port = await findAvailablePort(preferredPort, host);

  process.env.HOSTNAME = host;
  process.env.PORT = String(port);
  process.env.NODE_ENV = "production";

  const url = `http://${host}:${port}`;
  log("");
  log(`  Scriber is running at ${url}`);
  log("  DON'T CLOSE THIS TERMINAL — it keeps the app alive.");
  log("  Press Ctrl+C to stop.");
  log("");

  if (shouldOpen) {
    openBrowser(url);
  }

  const shutdown = (signal) => () => {
    log(`\nReceived ${signal}, shutting down...`);
    process.exit(0);
  };
  process.on("SIGINT", shutdown("SIGINT"));
  process.on("SIGTERM", shutdown("SIGTERM"));

  // Hand off to the Next.js standalone server.
  require(STANDALONE_SERVER);
}

async function main() {
  const [subcommand = "serve", ...rest] = process.argv.slice(2);

  if (subcommand === "help" || subcommand === "--help" || subcommand === "-h") {
    printHelp();
    return;
  }
  if (subcommand === "version" || subcommand === "--version" || subcommand === "-v") {
    printVersion();
    return;
  }

  if (subcommand === "transcribe") {
    if (!fs.existsSync(CLI_BUNDLE)) {
      logError(
        `Scriber's CLI bundle is missing at ${CLI_BUNDLE}.\n` +
          `If you installed via npm, please reinstall. If you're running from source, run \`npm run prepack\` first.`
      );
      process.exit(1);
    }
    const { runTranscribeCommand } = require(CLI_BUNDLE);
    await runTranscribeCommand(rest);
    return;
  }

  if (subcommand === "credits") {
    if (!fs.existsSync(CLI_BUNDLE)) {
      logError(
        `Scriber's CLI bundle is missing at ${CLI_BUNDLE}.\n` +
          `If you installed via npm, please reinstall. If you're running from source, run \`npm run prepack\` first.`
      );
      process.exit(1);
    }
    const { runCreditsCommand } = require(CLI_BUNDLE);
    await runCreditsCommand(rest);
    return;
  }

  if (subcommand !== "serve") {
    logError(`Unknown command: ${subcommand}`);
    printHelp();
    process.exit(1);
  }

  let parsed;
  try {
    parsed = parseArgs({
      args: rest,
      options: {
        port: { type: "string", short: "p" },
        "no-open": { type: "boolean" },
        help: { type: "boolean", short: "h" },
      },
      allowPositionals: false,
      strict: true,
    });
  } catch (err) {
    logError(err.message);
    process.exit(1);
  }

  if (parsed.values.help) {
    printHelp();
    return;
  }

  const port = parsed.values.port ? Number.parseInt(parsed.values.port, 10) : 7337;
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    logError(`Invalid port: ${parsed.values.port}`);
    process.exit(1);
  }

  await serve({
    port,
    open: !parsed.values["no-open"],
  });
}

main().catch((err) => {
  logError(err.stack || err.message);
  process.exit(1);
});
