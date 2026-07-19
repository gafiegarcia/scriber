"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Mic, FileText, Settings } from "lucide-react";

const tabs = [
  { href: "/", label: "Transcribe", icon: Mic },
  { href: "/notes", label: "Notes", icon: FileText },
  { href: "/settings", label: "Settings", icon: Settings },
] as const;

export function BottomTabBar() {
  const pathname = usePathname();

  function isActive(href: string) {
    if (href === "/") return pathname === "/";
    return pathname.startsWith(href);
  }

  return (
    <nav aria-label="Main navigation" className="flex shrink-0 border-t border-border/40 bg-background/80 backdrop-blur-lg pb-[env(safe-area-inset-bottom)] lg:hidden">
      {tabs.map(({ href, label, icon: Icon }) => {
        const active = isActive(href);
        return (
          <Link
            key={href}
            href={href}
            aria-current={active ? "page" : undefined}
            className={`flex flex-1 flex-col items-center gap-0.5 pb-2 pt-2.5 text-xs font-medium transition-colors ${
              active
                ? "border-t-2 border-foreground text-foreground"
                : "border-t-2 border-transparent text-muted-foreground active:text-foreground"
            }`}
          >
            <Icon
              className={`h-[22px] w-[22px] transition-transform ${active ? "scale-105" : ""}`}
              strokeWidth={active ? 2.2 : 1.8}
            />
            <span>{label}</span>
          </Link>
        );
      })}
    </nav>
  );
}
