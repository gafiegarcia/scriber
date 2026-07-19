/* eslint-disable @typescript-eslint/no-require-imports */
const fs = require("node:fs");
const path = require("node:path");
const { Arch } = require("builder-util");
const {
  flipFuses,
  FuseVersion,
  FuseV1Options,
} = require("@electron/fuses");
const { findDeveloperIdIdentity } = require("./scripts/check-desktop-release-env.js");
const rootPackage = require("./package.json");

const ROOT = __dirname;
const releaseBuild = process.env.SCRIBER_DESKTOP_RELEASE === "1";
const keychainIdentity = releaseBuild ? findDeveloperIdIdentity() : null;
const signingSource = process.env.CSC_LINK || process.env.CSC_NAME || keychainIdentity;

if (releaseBuild && !signingSource) {
  throw new Error(
    "Release build refused: no Developer ID Application certificate is configured"
  );
}

function copyStandaloneServer(context) {
  const source = path.join(ROOT, ".next", "standalone");
  const destination = path.join(
    context.appOutDir,
    `${context.packager.appInfo.productFilename}.app`,
    "Contents",
    "Resources",
    "scriber-standalone"
  );
  const blockedRoots = [
    path.join("node_modules", "ffmpeg-static"),
    path.join("node_modules", "@derhuerst", "ffprobe-static"),
    path.join("node_modules", "sharp"),
    path.join("node_modules", "@img"),
  ];
  fs.cpSync(source, destination, {
    recursive: true,
    filter: (candidate) => {
      const relative = path.relative(source, candidate);
      return !blockedRoots.some(
        (blocked) => relative === blocked || relative.startsWith(`${blocked}${path.sep}`)
      );
    },
  });
}

async function hardenElectron(context) {
  const productName = context.packager.appInfo.productFilename;
  const executable = path.join(
    context.appOutDir,
    `${productName}.app`,
    "Contents",
    "MacOS",
    productName
  );
  await flipFuses(executable, {
    version: FuseVersion.V1,
    // Fuse changes invalidate Electron's executable signature. Re-seal the
    // local arm64 build ad hoc; release signing still runs after this hook and
    // replaces it with the configured Developer ID signature.
    resetAdHocDarwinSignature: true,
    strictlyRequireAllFuses: true,
    [FuseV1Options.RunAsNode]: false,
    // Scriber uses an ephemeral, cookie-free Chromium session. Enabling this
    // fuse creates an unnecessary Safe Storage Keychain item and causes
    // password prompts whenever an ad-hoc development build changes identity.
    [FuseV1Options.EnableCookieEncryption]: false,
    [FuseV1Options.EnableNodeOptionsEnvironmentVariable]: false,
    [FuseV1Options.EnableNodeCliInspectArguments]: false,
    [FuseV1Options.EnableEmbeddedAsarIntegrityValidation]: true,
    [FuseV1Options.OnlyLoadAppFromAsar]: true,
    // Electron 43 ships only v8_context_snapshot.<arch>.bin. Enabling this fuse
    // without a browser_v8_context_snapshot.bin makes the app fail at launch.
    [FuseV1Options.LoadBrowserProcessSpecificV8Snapshot]: false,
    [FuseV1Options.GrantFileProtocolExtraPrivileges]: false,
    [FuseV1Options.WasmTrapHandlers]: true,
  });
}

async function finishDesktopBundle(context) {
  if (context.arch !== Arch.arm64) {
    throw new Error("Scriber desktop builds support Apple-silicon macOS only");
  }
  copyStandaloneServer(context);
  await hardenElectron(context);
}

module.exports = {
  appId: "com.gafiegarcia.scriber",
  productName: "Scriber",
  electronVersion: "43.1.1",
  asar: true,
  // The shell has no runtime npm dependencies. Mark dependency handling as
  // external so electron-builder never walks the root project's node_modules.
  beforeBuild: () => false,
  directories: {
    app: "desktop",
    output: "dist-desktop",
  },
  extraMetadata: {
    version: rootPackage.version,
  },
  files: ["main.cjs", "runtime.cjs", "package.json"],
  extraResources: [
    {
      from: path.join(ROOT, ".ffmpeg", "darwin-${arch}"),
      to: "ffmpeg",
      filter: ["**/*"],
    },
    {
      from: path.join(ROOT, "docs", "FFMPEG_DISTRIBUTION.md"),
      to: "legal/FFMPEG_DISTRIBUTION.md",
    },
  ],
  afterPack: finishDesktopBundle,
  mac: {
    target: ["dir"],
    category: "public.app-category.productivity",
    icon: path.join(ROOT, "public", "icon.svg"),
    minimumSystemVersion: "12.0",
    darkModeSupport: true,
    identity: releaseBuild ? process.env.CSC_NAME || keychainIdentity || undefined : null,
    hardenedRuntime: releaseBuild,
    notarize: releaseBuild,
    binaries: [
      "Contents/Resources/ffmpeg/ffmpeg",
      "Contents/Resources/ffmpeg/ffprobe",
    ],
    extendInfo: {
      LSMultipleInstancesProhibited: true,
      NSMicrophoneUsageDescription:
        "Scriber uses the microphone only when you choose to record audio for transcription.",
    },
  },
  dmg: {
    artifactName: "Scriber-${version}-Apple-Silicon.${ext}",
    title: "Scriber ${version}",
    contents: [
      { x: 140, y: 220, type: "file" },
      { x: 410, y: 220, type: "link", path: "/Applications" },
    ],
  },
};
