import { requireUser } from "@/lib/session";
import { listEvents } from "@/repositories/events";
import { CreateEventDialog } from "./create-event-dialog";
import { EventCard } from "./event-card";

export default async function DashboardPage() {
  const user = await requireUser();
  const events = await listEvents(user.id);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Vos événements</h1>
          <p className="text-sm text-neutral-500">
            Créez un événement, ajoutez vos tables et vos invités.
          </p>
        </div>
        <CreateEventDialog />
      </div>

      {events.length === 0 ? (
        <div className="rounded-xl border border-dashed border-neutral-300 bg-white p-12 text-center">
          <p className="text-neutral-500">Aucun événement pour l&apos;instant.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {events.map((event) => (
            <EventCard key={event.id} event={event} />
          ))}
        </div>
      )}
    </div>
  );
}
