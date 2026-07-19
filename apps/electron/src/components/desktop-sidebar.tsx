"use client";

import Link from "next/link";
import { useRouter, usePathname } from "next/navigation";
import { FileText, Settings, Plus, Search, Mic, Upload } from "lucide-react";
import { ExitButton } from "@/components/exit-button";
import {
  useGlobalShortcuts,
  triggerNotesSearch,
} from "@/lib/hooks/use-keyboard-shortcuts";
import { useNotes } from "@/lib/hooks/use-notes";

const sourceIcons = {
  recording: Mic,
  upload: Upload,
  text: FileText,
} as const;

export function DesktopSidebar() {
  const pathname = usePathname();
  const router = useRouter();
  useGlobalShortcuts();

  const { notes } = useNotes();
  const recents = notes.slice(0, 5);

  const notesActive =
    pathname === "/notes" || pathname.startsWith("/notes/");
  const settingsActive = pathname.startsWith("/settings");

  return (
    <aside className="hidden shrink-0 border-r border-border/40 bg-sidebar/30 backdrop-blur-xl lg:flex lg:w-60 lg:flex-col">
      <div className="flex h-14 items-center px-4">
        <svg
          width="110"
          height="26"
          viewBox="0 0 110 26"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
          aria-label="Scriber"
          role="img"
          className="h-5 w-auto"
        >
          <path
            d="M0.0175781 18.2812L0 16.8398H5.18555V17.9121C5.20898 19.084 5.58398 19.9512 6.31055 20.5137C7.04883 21.0645 8.10352 21.3398 9.47461 21.3398C10.8223 21.3398 11.8359 21.0938 12.5156 20.6016C13.1953 20.0977 13.5352 19.4238 13.5352 18.5801C13.5352 17.7715 13.2012 17.1562 12.5332 16.7344C11.877 16.3008 10.4707 15.7969 8.31445 15.2227C5.71289 14.5078 3.73242 13.5527 2.37305 12.3574C1.02539 11.1504 0.351562 9.53906 0.351562 7.52344C0.351562 5.42578 1.1543 3.75 2.75977 2.49609C4.37695 1.24219 6.54492 0.615234 9.26367 0.615234C11.9473 0.615234 14.0977 1.21289 15.7148 2.4082C17.3438 3.5918 18.1699 5.2207 18.1934 7.29492V8.40234H13.166V7.62891C13.1543 6.67969 12.832 5.94141 12.1992 5.41406C11.5781 4.875 10.623 4.60547 9.33398 4.60547C8.02148 4.60547 7.07812 4.82813 6.50391 5.27344C5.92969 5.71875 5.64258 6.31641 5.64258 7.06641C5.64258 7.79297 6 8.36133 6.71484 8.77148C7.44141 9.18164 8.88867 9.67383 11.0566 10.248C13.6348 10.9395 15.5742 11.8887 16.875 13.0957C18.1758 14.291 18.8262 15.9258 18.8262 18C18.8262 20.2852 17.9707 22.0605 16.2598 23.3262C14.5605 24.5918 12.3164 25.2246 9.52734 25.2246C6.73828 25.2246 4.45898 24.6445 2.68945 23.4844C0.919922 22.3125 0.0292969 20.5781 0.0175781 18.2812ZM20.2767 16.0488V15.5215C20.2767 12.6035 21.097 10.3418 22.7377 8.73633C24.39 7.11914 26.5287 6.31055 29.1537 6.31055C31.7552 6.31055 33.765 6.89648 35.183 8.06836C36.6127 9.24023 37.3978 10.916 37.5384 13.0957L37.5736 13.6582H32.4584V13.2891C32.4232 12.3164 32.1185 11.5723 31.5443 11.0566C30.9818 10.541 30.2377 10.2832 29.3119 10.2832C28.222 10.2832 27.3197 10.7051 26.6048 11.5488C25.9017 12.3926 25.5502 13.6758 25.5502 15.3984V16.1719C25.5502 17.8125 25.8959 19.0898 26.5873 20.0039C27.2787 20.918 28.1752 21.375 29.2767 21.375C30.2494 21.375 31.0287 21.1113 31.6146 20.584C32.2005 20.0449 32.4994 19.2832 32.5111 18.2988V17.9473H37.5736L37.556 18.4043C37.5209 20.5488 36.765 22.2363 35.2884 23.4668C33.8119 24.6855 31.7728 25.2949 29.1712 25.2949C26.5462 25.2949 24.4076 24.4863 22.7552 22.8691C21.1029 21.252 20.2767 18.9785 20.2767 16.0488ZM39.2527 24.8906V6.78516H44.5085V9.03516H44.5261C44.9597 8.28516 45.5749 7.66406 46.3718 7.17188C47.1687 6.67969 48.0534 6.43359 49.0261 6.43359C49.4597 6.43359 49.8288 6.45703 50.1335 6.50391C50.4499 6.53906 50.696 6.58594 50.8718 6.64453V10.9863C50.5437 10.8809 50.2214 10.8047 49.905 10.7578C49.6003 10.6992 49.2429 10.6699 48.8327 10.6699C48.0593 10.6699 47.2683 10.9277 46.4597 11.4434C45.6511 11.9473 45.0241 12.627 44.5788 13.4824V24.8906H39.2527ZM51.9884 24.8906V6.78516H57.2794V24.8906H51.9884ZM51.6192 2.79492C51.6192 2.00977 51.8829 1.34766 52.4102 0.808594C52.9376 0.269531 53.6817 0 54.6427 0C55.6153 0 56.3536 0.263672 56.8575 0.791016C57.3731 1.31836 57.6309 1.98633 57.6309 2.79492C57.6309 3.58008 57.3673 4.25391 56.8399 4.81641C56.3126 5.36719 55.5684 5.64258 54.6075 5.64258C53.6466 5.64258 52.9083 5.36719 52.3927 4.81641C51.877 4.25391 51.6192 3.58008 51.6192 2.79492ZM60.0131 24.8906V0.544922H65.1987V8.71875C65.7143 7.99219 66.4584 7.41797 67.4311 6.99609C68.4038 6.57422 69.4877 6.36328 70.683 6.36328C72.7573 6.36328 74.4389 7.20117 75.728 8.87695C77.017 10.5527 77.6616 12.7207 77.6616 15.3809V15.9082C77.6616 18.5918 77.0053 20.8242 75.6928 22.6055C74.3803 24.375 72.6928 25.2598 70.6303 25.2598C69.435 25.2598 68.3334 25.0664 67.3256 24.6797C66.3295 24.293 65.6088 23.7656 65.1635 23.0977H65.1459V24.8906H60.0131ZM65.2163 19.2305C65.4858 19.7812 65.9545 20.2734 66.6225 20.707C67.3022 21.1406 68.0932 21.3574 68.9955 21.3574C70.0737 21.3574 70.9057 20.8418 71.4916 19.8105C72.0776 18.7793 72.3705 17.4727 72.3705 15.8906V15.4863C72.3705 13.9395 72.0776 12.6973 71.4916 11.7598C70.9057 10.8105 70.0209 10.3359 68.8373 10.3359C68.0405 10.3359 67.2963 10.5469 66.6049 10.9688C65.9252 11.3789 65.4623 11.8652 65.2163 12.4277V19.2305ZM78.7078 16.0488V15.5215C78.7078 12.7441 79.534 10.5176 81.1863 8.8418C82.8504 7.1543 84.9949 6.31055 87.6199 6.31055C90.2098 6.31055 92.2488 7.11328 93.7371 8.71875C95.2254 10.3242 95.9637 12.5215 95.952 15.3105V16.9102H81.5379V14.0098H90.8895V14.3965C90.8895 13.1074 90.6727 12.0703 90.2391 11.2852C89.8055 10.4883 88.8445 10.0898 87.3562 10.0898C86.3133 10.0898 85.452 10.5703 84.7723 11.5312C84.0926 12.4922 83.7527 13.6758 83.7527 15.082V16.084C83.7527 17.7363 84.1395 19.0488 84.9129 20.0215C85.6863 20.9824 86.6414 21.4629 87.7781 21.4629C88.6805 21.4629 89.448 21.2871 90.0809 20.9355C90.7254 20.5723 91.2117 20.1211 91.5398 19.582L95.7762 21.1465C95.2371 22.5059 94.2996 23.543 92.9637 24.2578C91.6395 24.9609 89.9051 25.3125 87.7605 25.3125C84.9949 25.3125 82.7918 24.4805 81.1512 22.8164C79.5223 21.1523 78.7078 18.8965 78.7078 16.0488ZM97.6486 24.8906V6.78516H102.904V9.03516H102.922C103.356 8.28516 103.971 7.66406 104.768 7.17188C105.565 6.67969 106.449 6.43359 107.422 6.43359C107.856 6.43359 108.225 6.45703 108.529 6.50391C108.846 6.53906 109.092 6.58594 109.268 6.64453V10.9863C108.94 10.8809 108.617 10.8047 108.301 10.7578C107.996 10.6992 107.639 10.6699 107.229 10.6699C106.455 10.6699 105.664 10.9277 104.856 11.4434C104.047 11.9473 103.42 12.627 102.975 13.4824V24.8906H97.6486Z"
            fill="currentColor"
          />
        </svg>
      </div>

      <div className="px-3 pb-1 pt-2">
        <Link
          href="/"
          className="flex h-9 w-full items-center justify-center gap-1.5 rounded-md bg-foreground text-sm font-medium text-background transition-colors hover:brightness-110"
        >
          <Plus className="h-4 w-4" />
          <span>New transcription</span>
          <kbd className="rounded bg-background/15 px-1.5 py-0.5 font-mono text-[10px] text-background/70">
            T
          </kbd>
        </Link>
      </div>

      <nav aria-label="Main navigation" className="flex flex-col gap-0.5 px-3 pt-2">
        <button
          type="button"
          onClick={() => triggerNotesSearch(router, pathname)}
          className="group flex h-9 cursor-pointer items-center gap-2 rounded-md px-2 text-sm text-muted-foreground transition-colors hover:bg-foreground/5 hover:text-foreground"
        >
          <Search className="h-4 w-4" />
          <span>Search notes</span>
          <kbd className="ml-auto rounded bg-muted px-1.5 py-0.5 font-mono text-[10px] text-muted-foreground/60">
            ⌘K
          </kbd>
        </button>

        <Link
          href="/notes"
          aria-current={notesActive ? "page" : undefined}
          className={`group flex h-9 items-center gap-2 rounded-md px-2 text-sm transition-colors ${
            notesActive
              ? "bg-foreground/10 text-foreground"
              : "text-muted-foreground hover:bg-foreground/5 hover:text-foreground"
          }`}
        >
          <FileText className="h-4 w-4" />
          All notes
        </Link>
      </nav>

      {recents.length > 0 && (
        <div className="mt-8 px-3">
          <div className="px-2 pb-1 text-[11px] font-medium text-muted-foreground/70">
            Recents
          </div>
          <div className="flex flex-col gap-0.5">
            {recents.map((note) => {
              const active = pathname === `/notes/${note.id}`;
              const Icon = sourceIcons[note.source] ?? FileText;
              return (
                <Link
                  key={note.id}
                  href={`/notes/${note.id}`}
                  className={`flex h-7 items-center gap-2 rounded-md px-2 text-xs transition-colors ${
                    active
                      ? "bg-foreground/10 text-foreground"
                      : "text-muted-foreground hover:bg-foreground/5 hover:text-foreground"
                  }`}
                >
                  <Icon className="h-3.5 w-3.5 shrink-0" />
                  <span className="truncate">{note.title || "Untitled"}</span>
                </Link>
              );
            })}
          </div>
        </div>
      )}

      <div className="mt-auto flex items-center justify-between gap-2 border-t border-border/40 px-2 py-2">
        <Link
          href="/settings"
          aria-label="Settings"
          aria-current={settingsActive ? "page" : undefined}
          className={`inline-flex h-9 w-9 items-center justify-center rounded-full transition-colors active:scale-95 ${
            settingsActive
              ? "bg-foreground/10 text-foreground"
              : "text-muted-foreground hover:bg-foreground/5 hover:text-foreground"
          }`}
        >
          <Settings className="h-4 w-4" />
        </Link>
        <ExitButton />
      </div>
    </aside>
  );
}
