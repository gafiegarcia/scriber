"use client";

import { useEffect, useState } from "react";
import { Check, Loader2, Eye, EyeOff, AlertCircle, ExternalLink } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { getConfig, saveConfig, testApiKey } from "@/lib/config-client";
import { useKeyStatus } from "@/lib/key-status-context";
import { CreditsPanel } from "@/components/credits-panel";

type TestState = "idle" | "testing" | "valid" | "invalid";

export function ApiKeySettings() {
  const [hasKey, setHasKey] = useState<boolean | null>(null);
  const [apiKeyStorage, setApiKeyStorage] = useState<
    "keychain" | "config-file" | null
  >(null);
  const [draft, setDraft] = useState("");
  const [reveal, setReveal] = useState(false);
  const [saving, setSaving] = useState(false);
  const [testState, setTestState] = useState<TestState>("idle");
  const [testMessage, setTestMessage] = useState<string | null>(null);
  const { recheck } = useKeyStatus();

  useEffect(() => {
    getConfig()
      .then((cfg) => {
        setHasKey(cfg.hasApiKey);
        setApiKeyStorage(cfg.apiKeyStorage);
      })
      .catch(() => setHasKey(false));
  }, []);

  async function handleSave() {
    const trimmed = draft.trim();
    if (!trimmed) return;

    setSaving(true);
    setTestState("testing");
    setTestMessage(null);

    try {
      const result = await testApiKey(trimmed);
      if (!result.ok) {
        setTestState("invalid");
        setTestMessage(result.error || "Key test failed");
        setSaving(false);
        return;
      }
      const config = await saveConfig({ apiKey: trimmed });
      setHasKey(true);
      setApiKeyStorage(config.apiKeyStorage);
      setDraft("");
      setTestState("valid");
      setTestMessage(
        result.subscription
          ? `Connected (${result.subscription} tier)`
          : "Connected"
      );
      toast.success("API key saved");
      await recheck();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to save key");
    } finally {
      setSaving(false);
    }
  }

  async function handleSaveAnyway() {
    const trimmed = draft.trim();
    if (!trimmed) return;
    setSaving(true);
    try {
      const config = await saveConfig({ apiKey: trimmed });
      setHasKey(true);
      setApiKeyStorage(config.apiKeyStorage);
      setDraft("");
      toast.success("API key saved (untested)");
      await recheck();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to save key");
    } finally {
      setSaving(false);
    }
  }

  async function handleTest() {
    setTestState("testing");
    setTestMessage(null);
    const result = await testApiKey(draft.trim() || undefined);
    if (result.ok) {
      setTestState("valid");
      setTestMessage(
        result.subscription
          ? `Connected (${result.subscription} tier)`
          : "Connected"
      );
    } else {
      setTestState("invalid");
      setTestMessage(result.error || "Key test failed");
    }
  }

  async function handleRemove() {
    setSaving(true);
    try {
      const config = await saveConfig({ apiKey: "" });
      setHasKey(false);
      setApiKeyStorage(config.apiKeyStorage);
      toast.success("API key removed");
      await recheck();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to remove key");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="flex flex-col gap-3">
      {hasKey && !draft && (
        <>
          <div className="flex flex-col gap-2.5 rounded-lg border border-border bg-muted/30 px-3 py-2.5 text-sm text-muted-foreground">
            <span className="flex items-center gap-2">
              <Check className="h-4 w-4 text-foreground/70" />
              Key configured — stored in {apiKeyStorage === "keychain"
                ? "macOS Keychain"
                : apiKeyStorage === "config-file"
                  ? "~/.scriber/config.json"
                  : "secure storage"}
            </span>
            <button
              type="button"
              onClick={handleTest}
              disabled={testState === "testing"}
              className="self-start text-xs text-muted-foreground underline underline-offset-2 hover:text-foreground disabled:opacity-50"
            >
              {testState === "testing" ? "Testing…" : "Test stored key"}
            </button>
          </div>
          <CreditsPanel />
        </>
      )}

      <p className="text-sm text-muted-foreground/70">
        {hasKey
          ? "Paste a new key to replace the stored one."
          : "Paste your ElevenLabs API key to enable transcription."}
      </p>

      <div className="flex gap-2">
        <div className="relative flex-1">
          <input
            type={reveal ? "text" : "password"}
            autoComplete="off"
            spellCheck={false}
            placeholder="sk_..."
            value={draft}
            onChange={(e) => {
              setDraft(e.target.value);
              setTestState("idle");
              setTestMessage(null);
            }}
            className="h-10 w-full rounded-xl border border-border bg-muted/30 pr-10 pl-3 font-mono text-sm outline-none placeholder:text-muted-foreground/40 focus:border-foreground/20"
          />
          {draft && (
            <button
              type="button"
              onClick={() => setReveal((v) => !v)}
              className="absolute right-2 top-1/2 -translate-y-1/2 p-1 text-muted-foreground hover:text-foreground"
              aria-label={reveal ? "Hide key" : "Show key"}
            >
              {reveal ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
            </button>
          )}
        </div>
        <Button
          size="sm"
          className="h-10 rounded-xl"
          onClick={handleSave}
          disabled={!draft.trim() || saving}
        >
          {saving && testState === "testing" ? (
            <>
              <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
              Verifying
            </>
          ) : (
            "Save"
          )}
        </Button>
      </div>

      <div className="flex items-center gap-2">
        <Button
          variant="outline"
          size="sm"
          className="h-9 rounded-xl text-sm"
          onClick={handleTest}
          disabled={testState === "testing" || !draft.trim()}
        >
          {testState === "testing" ? (
            <>
              <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
              Testing...
            </>
          ) : (
            "Test key"
          )}
        </Button>
        {testState === "valid" && testMessage && (
          <span className="flex items-center gap-1 text-xs text-foreground/70">
            <Check className="h-3.5 w-3.5" />
            {testMessage}
          </span>
        )}
        {testState === "invalid" && testMessage && (
          <span className="flex items-center gap-1 text-xs text-destructive">
            <AlertCircle className="h-3.5 w-3.5" />
            {testMessage}
          </span>
        )}
        {testState === "invalid" && draft.trim() && (
          <button
            type="button"
            onClick={handleSaveAnyway}
            disabled={saving}
            className="text-[11px] text-destructive underline underline-offset-2 hover:no-underline"
          >
            Save anyway
          </button>
        )}
      </div>

      <a
        href="https://elevenlabs.io/app/settings/api-keys"
        target="_blank"
        rel="noreferrer"
        className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
      >
        Manage keys on ElevenLabs
        <ExternalLink className="h-3 w-3" />
      </a>

      {hasKey && (
        <button
          onClick={handleRemove}
          disabled={saving}
          className="mt-1 self-start text-xs text-destructive/70 transition-colors hover:text-destructive"
        >
          Remove stored key
        </button>
      )}
    </div>
  );
}
