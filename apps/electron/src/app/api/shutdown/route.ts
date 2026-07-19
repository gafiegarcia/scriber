import { NextResponse } from "next/server";

export const runtime = "nodejs";

export async function POST() {
  setTimeout(() => {
    process.stdout.write(
      "\n  Scriber stopped via web UI.\n  Run `scriber` again to restart.\n\n"
    );
    process.exit(0);
  }, 100);
  return NextResponse.json({ ok: true });
}
