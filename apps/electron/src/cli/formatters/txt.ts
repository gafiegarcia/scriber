export function renderTxt(text: string): string {
  return text.endsWith("\n") ? text : text + "\n";
}
