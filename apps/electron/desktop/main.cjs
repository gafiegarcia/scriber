/* eslint-disable @typescript-eslint/no-require-imports */
const fs = require("node:fs");
const crypto = require("node:crypto");
const path = require("node:path");
const {
  app,
  BrowserWindow,
  dialog,
  session,
  shell,
  utilityProcess,
} = require("electron");
const {
  HOST,
  findAvailablePort,
  isAppUrl,
  isSafeExternalUrl,
  resolveRuntimePaths,
  waitForHealth,
} = require("./runtime.cjs");

const DESKTOP_TITLEBAR_CSS = `
  [data-scriber-desktop-titlebar] {
    display: block !important;
    height: 2rem;
    flex: 0 0 2rem;
    -webkit-app-region: drag;
  }
`;

let mainWindow = null;
let serverProcess = null;
let serverExitCode = null;
let serverReady = false;
let quitting = false;
let appOrigin = null;
let desktopToken = null;
let appSession = null;
const serverLog = [];

function appendServerLog(chunk) {
  const lines = String(chunk).split(/\r?\n/).filter(Boolean);
  serverLog.push(...lines);
  if (serverLog.length > 80) serverLog.splice(0, serverLog.length - 80);
}

function recentServerLog() {
  return serverLog.length ? `\n\nLocal server log:\n${serverLog.slice(-20).join("\n")}` : "";
}

function assertRuntimeFile(filePath, label) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`${label} is missing from the app at ${filePath}`);
  }
}

function cleanEnvironment(overrides) {
  const environment = Object.fromEntries(
    Object.entries(process.env).filter((entry) => typeof entry[1] === "string")
  );
  delete environment.ELECTRON_RUN_AS_NODE;
  delete environment.NODE_OPTIONS;
  return { ...environment, ...overrides };
}

async function openExternal(url) {
  if (isSafeExternalUrl(url)) await shell.openExternal(url);
}

function secureWindow(window) {
  window.webContents.on("will-navigate", (event, url) => {
    if (appOrigin && isAppUrl(url, appOrigin)) return;
    event.preventDefault();
    void openExternal(url);
  });
  window.webContents.setWindowOpenHandler(({ url }) => {
    void openExternal(url);
    return { action: "deny" };
  });
}

function configurePermissions(targetSession) {
  targetSession.setPermissionRequestHandler(
    (webContents, permission, callback, details) => {
      const fromScriber = Boolean(
        appOrigin && webContents && isAppUrl(webContents.getURL(), appOrigin)
      );
      const mediaTypes = details?.mediaTypes ?? [];
      const audioOnly = mediaTypes.length === 0 || mediaTypes.every((type) => type === "audio");
      callback(fromScriber && permission === "media" && audioOnly);
    }
  );
}

function configureApiAuthentication(targetSession) {
  if (!appOrigin || !desktopToken) throw new Error("Desktop API authentication is not ready");
  targetSession.webRequest.onBeforeSendHeaders(
    { urls: [`${appOrigin}/api/*`] },
    (details, callback) => {
      details.requestHeaders["X-Scriber-Desktop-Token"] = desktopToken;
      callback({ requestHeaders: details.requestHeaders });
    }
  );
}

async function startServer() {
  serverExitCode = null;
  serverReady = false;
  const runtime = resolveRuntimePaths({
    isPackaged: app.isPackaged,
    resourcesPath: process.resourcesPath,
    appDir: __dirname,
    arch: process.arch,
    platform: process.platform,
  });
  assertRuntimeFile(runtime.serverPath, "Scriber's local server");
  assertRuntimeFile(runtime.ffmpegPath, "Scriber's FFmpeg helper");
  assertRuntimeFile(runtime.ffprobePath, "Scriber's FFprobe helper");

  const port = await findAvailablePort();
  appOrigin = `http://${HOST}:${port}`;
  desktopToken = crypto.randomBytes(32).toString("hex");
  const environment = cleanEnvironment({
    HOSTNAME: HOST,
    PORT: String(port),
    NODE_ENV: "production",
    NEXT_TELEMETRY_DISABLED: "1",
    NODE_PATH: path.join(runtime.standaloneDir, "node_modules"),
    SCRIBER_DESKTOP: "1",
    SCRIBER_DESKTOP_TOKEN: desktopToken,
    SCRIBER_FFMPEG_PATH: runtime.ffmpegPath,
    SCRIBER_FFPROBE_PATH: runtime.ffprobePath,
  });

  serverProcess = utilityProcess.fork(runtime.serverPath, [], {
    cwd: runtime.standaloneDir,
    env: environment,
    stdio: "pipe",
    serviceName: "Scriber Local Server",
  });
  serverProcess.stdout?.on("data", appendServerLog);
  serverProcess.stderr?.on("data", appendServerLog);
  serverProcess.once("exit", (code) => {
    serverExitCode = code;
    serverProcess = null;
    if (quitting) return;
    if (!serverReady) return;
    if (code === 0) {
      app.quit();
      return;
    }
    dialog.showErrorBox(
      "Scriber stopped unexpectedly",
      `The private local server exited with code ${code}.${recentServerLog()}`
    );
    app.quit();
  });

  await waitForHealth(appOrigin, {
    isStopped: () => serverExitCode !== null,
    headers: { "X-Scriber-Desktop-Token": desktopToken },
  });
  serverReady = true;
  return appOrigin;
}

async function createWindow(url) {
  const window = new BrowserWindow({
    title: "Scriber",
    width: 1280,
    height: 820,
    minWidth: 760,
    minHeight: 560,
    show: false,
    backgroundColor: "#0a0a0a",
    titleBarStyle: "hiddenInset",
    webPreferences: {
      contextIsolation: true,
      devTools: !app.isPackaged,
      nodeIntegration: false,
      sandbox: true,
      session: appSession,
      webviewTag: false,
    },
  });
  mainWindow = window;
  secureWindow(window);
  window.webContents.on("did-finish-load", () => {
    void window.webContents
      .insertCSS(DESKTOP_TITLEBAR_CSS)
      .catch((error) => console.error("Could not apply desktop title-bar spacing", error))
      .finally(() => {
        if (!window.isDestroyed() && !window.isVisible()) window.show();
      });
  });
  window.on("closed", () => {
    if (mainWindow === window) mainWindow = null;
  });
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      await window.loadURL(url);
      return;
    } catch (error) {
      const isTransientNavigationFailure = String(error).includes("ERR_FAILED");
      if (attempt === 3 || !isTransientNavigationFailure || window.isDestroyed()) {
        throw error;
      }
      await new Promise((resolve) => setTimeout(resolve, 250 * attempt));
    }
  }
}

function focusWindow() {
  if (!mainWindow) {
    if (appOrigin) void createWindow(appOrigin);
    return;
  }
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.show();
  mainWindow.focus();
}

const ownsInstance = app.requestSingleInstanceLock();
if (!ownsInstance) {
  app.quit();
} else {
  app.on("second-instance", focusWindow);
  app.on("before-quit", () => {
    quitting = true;
    serverProcess?.kill();
    serverProcess = null;
  });
  app.on("window-all-closed", () => {
    if (process.platform !== "darwin") app.quit();
  });
  app.on("activate", () => {
    if (!mainWindow && appOrigin) void createWindow(appOrigin);
  });

  app.whenReady().then(async () => {
    try {
      // Scriber has no browser login or cookie-based state. An in-memory
      // session avoids persisting Chromium credentials and prevents Electron
      // from creating an unnecessary "Safe Storage" Keychain item.
      appSession = session.fromPartition("scriber", { cache: false });
      configurePermissions(appSession);
      const url = await startServer();
      configureApiAuthentication(appSession);
      await createWindow(url);
    } catch (error) {
      serverProcess?.kill();
      const message = error instanceof Error ? error.message : String(error);
      dialog.showErrorBox("Scriber could not start", `${message}${recentServerLog()}`);
      app.quit();
    }
  });
}
