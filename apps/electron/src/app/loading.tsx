import { Skeleton } from "@/components/ui/skeleton";

export default function AppLoading() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-6 px-8">
      <div className="flex flex-col items-center gap-3">
        <Skeleton className="h-9 w-28 rounded-lg" />
        <Skeleton className="h-5 w-52 rounded-lg" />
      </div>
      <div className="flex items-end gap-8 pt-6">
        <Skeleton className="h-14 w-14 rounded-full" />
        <Skeleton className="h-[72px] w-[72px] rounded-full" />
      </div>
    </div>
  );
}
