import { notFound } from "next/navigation";
import { getPublicEvent } from "@/repositories/public-search";
import { formatEventDate } from "@/lib/date";
import { GuestSearch } from "./guest-search";

export default async function PublicEventPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const event = await getPublicEvent(slug);
  if (!event) notFound();

  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col items-center gap-8 px-6 py-16">
      <div className="space-y-2 text-center">
        <h1 className="text-2xl font-semibold text-balance">{event.name}</h1>
        {event.event_date && (
          <p className="text-sm text-neutral-500">{formatEventDate(event.event_date)}</p>
        )}
        {event.description && (
          <p className="text-sm text-neutral-600">{event.description}</p>
        )}
      </div>

      <GuestSearch slug={slug} />
    </main>
  );
}
