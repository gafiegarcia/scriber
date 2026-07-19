import Link from "next/link";
import { Button } from "@/components/ui/button";

export default function NoteNotFound() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-4 px-6 text-center">
      <h2 className="text-lg font-semibold">Note not found</h2>
      <p className="text-sm text-muted-foreground">
        This note may have been deleted.
      </p>
      <Link href="/notes">
        <Button variant="outline">Back to notes</Button>
      </Link>
    </div>
  );
}
