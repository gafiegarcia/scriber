import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const runtime = require("../../desktop/runtime.cjs") as {
  isAppUrl(candidate: string, origin: string): boolean;
  isSafeExternalUrl(candidate: string): boolean;
  resolveRuntimePaths(input: {
    isPackaged: boolean;
    resourcesPath: string;
    appDir: string;
    arch: string;
    platform: string;
  }): {
    standaloneDir: string;
    serverPath: string;
    ffmpegPath: string;
    ffprobePath: string;
  };
};

test("desktop runtime resolves packaged resources outside app.asar", () => {
  const paths = runtime.resolveRuntimePaths({
    isPackaged: true,
    resourcesPath: "/Applications/Scriber.app/Contents/Resources",
    appDir: "/ignored",
    arch: "arm64",
    platform: "darwin",
  });
  assert.equal(
    paths.serverPath,
    "/Applications/Scriber.app/Contents/Resources/scriber-standalone/server.js"
  );
  assert.equal(
    paths.ffmpegPath,
    "/Applications/Scriber.app/Contents/Resources/ffmpeg/ffmpeg"
  );
});

test("desktop runtime resolves architecture-specific development helpers", () => {
  const appDir = "/repo/desktop";
  const paths = runtime.resolveRuntimePaths({
    isPackaged: false,
    resourcesPath: "/ignored",
    appDir,
    arch: "arm64",
    platform: "darwin",
  });
  assert.equal(paths.serverPath, path.join("/repo", ".next", "standalone", "server.js"));
  assert.equal(paths.ffprobePath, path.join("/repo", ".ffmpeg", "darwin-arm64", "ffprobe"));
});

test("desktop runtime rejects Intel startup", () => {
  assert.throws(
    () =>
      runtime.resolveRuntimePaths({
        isPackaged: true,
        resourcesPath: "/tmp/resources",
        appDir: "/tmp/app",
        arch: "x64",
        platform: "darwin",
      }),
    /supports Apple silicon only/
  );
});

test("desktop navigation stays on the private app origin", () => {
  const origin = "http://127.0.0.1:49152";
  assert.equal(runtime.isAppUrl(`${origin}/settings`, origin), true);
  assert.equal(runtime.isAppUrl("http://127.0.0.1:49153/settings", origin), false);
  assert.equal(runtime.isAppUrl("https://example.com", origin), false);
  assert.equal(runtime.isSafeExternalUrl("https://elevenlabs.io/docs"), true);
  assert.equal(runtime.isSafeExternalUrl("http://example.com"), false);
  assert.equal(runtime.isSafeExternalUrl("file:///etc/passwd"), false);
});

test("desktop runtime rejects non-macOS startup", () => {
  assert.throws(
    () =>
      runtime.resolveRuntimePaths({
        isPackaged: true,
        resourcesPath: "/tmp/resources",
        appDir: "/tmp/app",
        arch: "x64",
        platform: "linux",
      }),
    /supports macOS only/
  );
});

test("desktop package version matches the root package", () => {
  const rootPackage = require("../../package.json") as { version: string };
  const desktopPackage = require("../../desktop/package.json") as { version: string };
  assert.equal(desktopPackage.version, rootPackage.version);
});
