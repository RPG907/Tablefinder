import { notFound } from "next/navigation";
import { requireUser } from "@/lib/session";
import { getEvent } from "@/repositories/events";
import { formatEventDate } from "@/lib/date";
import { EventNav } from "./event-nav";

export default async function EventLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const user = await requireUser();
  const event = await getEvent(user.id, id);
  if (!event) notFound();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">{event.name}</h1>
        {event.event_date && (
          <p className="text-sm text-neutral-500">{formatEventDate(event.event_date)}</p>
        )}
      </div>
      <EventNav eventId={event.id} />
      {children}
    </div>
  );
}
