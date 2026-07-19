/* eslint-disable @typescript-eslint/no-require-imports */
const http = require("node:http");
const net = require("node:net");
const path = require("node:path");

const HOST = "127.0.0.1";

function findAvailablePort(host = HOST) {
  return new Promise((resolve, reject) => {
    const probe = net.createServer();
    probe.unref();
    probe.once("error", reject);
    probe.listen(0, host, () => {
      const address = probe.address();
      const port = typeof address === "object" && address ? address.port : null;
      probe.close(() => {
        if (port) resolve(port);
        else reject(new Error("macOS did not provide an available local port"));
      });
    });
  });
}

function probeHealth(url, options = {}) {
  const timeoutMs = options.timeoutMs ?? 750;
  const headers = options.headers ?? {};
  return new Promise((resolve) => {
    const request = http.get(
      `${url}/api/health`,
      { timeout: timeoutMs, headers },
      (response) => {
      if (response.statusCode !== 200) {
        response.resume();
        resolve(false);
        return;
      }

      let body = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => {
        body += chunk;
      });
      response.on("end", () => {
        try {
          resolve(JSON.parse(body).app === "scriber");
        } catch {
          resolve(false);
        }
      });
      }
    );
    request.on("error", () => resolve(false));
    request.on("timeout", () => {
      request.destroy();
      resolve(false);
    });
  });
}

async function waitForHealth(url, options = {}) {
  const timeoutMs = options.timeoutMs ?? 20_000;
  const intervalMs = options.intervalMs ?? 100;
  const isStopped = options.isStopped ?? (() => false);
  const headers = options.headers ?? {};
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    if (isStopped()) throw new Error("Scriber's local server stopped during startup");
    if (await probeHealth(url, { headers })) return;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }

  throw new Error(`Scriber's local server did not become ready within ${timeoutMs / 1000} seconds`);
}

function resolveRuntimePaths({ isPackaged, resourcesPath, appDir, arch, platform }) {
  if (platform !== "darwin") {
    throw new Error("The Scriber desktop shell currently supports macOS only");
  }
  if (arch !== "arm64") {
    throw new Error("The Scriber desktop shell currently supports Apple silicon only");
  }
  const standaloneDir = isPackaged
    ? path.join(resourcesPath, "scriber-standalone")
    : path.join(appDir, "..", ".next", "standalone");
  const ffmpegDir = isPackaged
    ? path.join(resourcesPath, "ffmpeg")
    : path.join(appDir, "..", ".ffmpeg", `darwin-${arch}`);

  return {
    standaloneDir,
    serverPath: path.join(standaloneDir, "server.js"),
    ffmpegPath: path.join(ffmpegDir, "ffmpeg"),
    ffprobePath: path.join(ffmpegDir, "ffprobe"),
  };
}

function isAppUrl(candidate, appOrigin) {
  try {
    return new URL(candidate).origin === appOrigin;
  } catch {
    return false;
  }
}

function isSafeExternalUrl(candidate) {
  try {
    return new URL(candidate).protocol === "https:";
  } catch {
    return false;
  }
}

module.exports = {
  HOST,
  findAvailablePort,
  isAppUrl,
  isSafeExternalUrl,
  probeHealth,
  resolveRuntimePaths,
  waitForHealth,
};
