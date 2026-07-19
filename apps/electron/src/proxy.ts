import { NextResponse, type NextRequest } from "next/server";

const MUTATING_METHODS = new Set(["POST", "PUT", "PATCH", "DELETE"]);

export function proxy(request: NextRequest) {
  const desktopToken = process.env.SCRIBER_DESKTOP_TOKEN;
  if (
    desktopToken &&
    request.headers.get("x-scriber-desktop-token") !== desktopToken
  ) {
    return NextResponse.json(
      { error: "Desktop API authentication required" },
      { status: 401 }
    );
  }

  if (!MUTATING_METHODS.has(request.method)) return NextResponse.next();

  const origin = request.headers.get("origin");
  const host = request.headers.get("host");

  // Same-origin requests from the page always carry an Origin header matching host.
  // Local tools like curl may omit Origin — allow those (no browser = no CSRF risk).
  if (!origin) return NextResponse.next();

  try {
    const originHost = new URL(origin).host;
    if (originHost === host) return NextResponse.next();
  } catch {
    // Malformed Origin — reject below
  }

  return NextResponse.json(
    { error: "Cross-origin request rejected" },
    { status: 403 }
  );
}

export const config = {
  matcher: "/api/:path*",
};
