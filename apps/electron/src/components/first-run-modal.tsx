"use client";

import { useEffect, useState } from "react";
import { KeyRound, Loader2, ExternalLink, Check, AlertCircle, Eye, EyeOff } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { getConfig, saveConfig, testApiKey } from "@/lib/config-client";
import { useKeyStatus } from "@/lib/key-status-context";

type Status = "idle" | "testing" | "valid" | "invalid";

export function FirstRunModal() {
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [apiKey, setApiKey] = useState("");
  const [reveal, setReveal] = useState(false);
  const [saving, setSaving] = useState(false);
  const [apiKeyStorage, setApiKeyStorage] = useState<
    "keychain" | "config-file" | null
  >(null);
  const [status, setStatus] = useState<Status>("idle");
  const [error, setError] = useState<string | null>(null);
  const { recheck } = useKeyStatus();

  useEffect(() => {
    getConfig()
      .then((cfg) => {
        setApiKeyStorage(cfg.apiKeyStorage);
        if (!cfg.hasApiKey) setOpen(true);
      })
      .catch((err) => {
        setOpen(true);
        setError(
          err instanceof Error ? err.message : "Failed to load API key settings"
        );
      })
      .finally(() => setLoading(false));
  }, []);

  async function handleSave() {
    const trimmed = apiKey.trim();
    if (!trimmed) {
      setError("Please paste your ElevenLabs API key");
      return;
    }

    setSaving(true);
    setError(null);
    setStatus("testing");

    try {
      const result = await testApiKey(trimmed);
      if (!result.ok) {
        setStatus("invalid");
        setError(result.error || "Key test failed");
        setSaving(false);
        return;
      }

      const config = await saveConfig({ apiKey: trimmed });
      setApiKeyStorage(config.apiKeyStorage);
      setStatus("valid");
      toast.success("API key saved");
      setOpen(false);
      await recheck();
    } catch (err) {
      setStatus("invalid");
      setError(err instanceof Error ? err.message : "Failed to save key");
    } finally {
      setSaving(false);
    }
  }

  async function handleSaveAnyway() {
    const trimmed = apiKey.trim();
    if (!trimmed) return;
    setSaving(true);
    try {
      const config = await saveConfig({ apiKey: trimmed });
      setApiKeyStorage(config.apiKeyStorage);
      toast.success("API key saved");
      setOpen(false);
      await recheck();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save key");
    } finally {
      setSaving(false);
    }
  }

  if (loading) return null;

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (next) setOpen(true);
      }}
      disablePointerDismissal
    >
      <DialogContent className="sm:max-w-md" showCloseButton={false}>
        <DialogHeader>
          <div className="mb-2 flex h-10 w-10 items-center justify-center rounded-full bg-foreground/10">
            <KeyRound className="h-5 w-5" />
          </div>
          <DialogTitle>Welcome to Scriber</DialogTitle>
          <DialogDescription>
            Scriber uses your own ElevenLabs account to transcribe audio — the
            key stays on this machine.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-3">
          <label className="text-sm font-medium" htmlFor="api-key-input">
            ElevenLabs API Key
          </label>
          <div className="relative">
            <input
              id="api-key-input"
              type={reveal ? "text" : "password"}
              autoComplete="off"
              spellCheck={false}
              placeholder="sk_..."
              value={apiKey}
              onChange={(e) => {
                setApiKey(e.target.value);
                setStatus("idle");
                setError(null);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !saving) handleSave();
              }}
              className="h-10 w-full rounded-lg border border-border bg-muted/30 pl-3 pr-10 font-mono text-sm outline-none placeholder:text-muted-foreground/40 focus:border-foreground/20 focus:bg-background"
            />
            {apiKey && (
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

          {status === "invalid" && error && (
            <div className="flex flex-col gap-2 rounded-lg border border-destructive/30 bg-destructive/5 px-3 py-2 text-xs text-destructive">
              <div className="flex items-start gap-2">
                <AlertCircle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                <span className="flex-1">{error}</span>
              </div>
              <button
                type="button"
                onClick={handleSaveAnyway}
                disabled={saving}
                className="self-start text-[11px] underline underline-offset-2 hover:no-underline"
              >
                Save without testing
              </button>
            </div>
          )}

          <a
            href="https://elevenlabs.io/app/settings/api-keys"
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
          >
            Get an API key from ElevenLabs
            <ExternalLink className="h-3 w-3" />
          </a>

          <Button
            onClick={handleSave}
            disabled={saving || !apiKey.trim()}
            className="mt-2"
          >
            {status === "testing" ? (
              <>
                <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
                Verifying...
              </>
            ) : status === "valid" ? (
              <>
                <Check className="mr-1.5 h-3.5 w-3.5" />
                Saved
              </>
            ) : (
              "Save & Continue"
            )}
          </Button>

          <p className="text-center text-[11px] text-muted-foreground/60">
            Your key is stored in{" "}
            <span className="font-medium text-muted-foreground/80">
              {apiKeyStorage === "config-file"
                ? "~/.scriber/config.json"
                : "macOS Keychain"}
            </span>
            . Scriber only reads it when talking to ElevenLabs.
          </p>
        </div>
      </DialogContent>
    </Dialog>
  );
}
