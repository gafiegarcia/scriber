export interface MarkdownFrontmatter {
  language: string;
  languageProbability: number;
  durationSeconds?: number;
  createdAt: string;
  title?: string;
}

export function renderMarkdown(text: string, meta: MarkdownFrontmatter): string {
  const lines: string[] = ["---"];
  if (meta.title) lines.push(`title: ${yamlString(meta.title)}`);
  lines.push(`language: ${meta.language}`);
  lines.push(`languageProbability: ${meta.languageProbability}`);
  if (meta.durationSeconds != null) {
    lines.push(`durationSeconds: ${meta.durationSeconds}`);
  }
  lines.push(`createdAt: ${meta.createdAt}`);
  lines.push("---", "", text.trim(), "");
  return lines.join("\n");
}

function yamlString(s: string): string {
  // Quote only when YAML would otherwise misinterpret the value. Mid-string
  // dashes are fine (e.g. "my-note"); a leading "-" or "?" is not.
  const needsQuoting =
    /[:#&*!|>'"%@`\n]/.test(s) || // structural chars anywhere
    /^[-?]/.test(s) || // leading dash or question mark → list/flow key
    /^\s|\s$/.test(s); // leading/trailing whitespace
  if (needsQuoting) {
    return `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
  }
  return s;
}
