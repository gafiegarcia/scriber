"use client";

import { useParams } from "next/navigation";
import { NotesShell } from "@/components/notes-shell";

export default function NotesLayout() {
  const params = useParams();
  const selectedId = params?.id as string | undefined;
  // Layout renders NotesShell persistently — it never unmounts when navigating
  // between /notes and /notes/[id], so DesktopListPane and useNotes() survive
  // route changes and the sidebar never flickers.
  return <NotesShell selectedId={selectedId} />;
}
