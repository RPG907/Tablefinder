import { requireUser } from "@/lib/session";
import { listGuests } from "@/repositories/guests";
import { listTables } from "@/repositories/tables";
import { GuestsManager } from "./guests-manager";

export default async function GuestsPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ q?: string }>;
}) {
  const { id } = await params;
  const { q } = await searchParams;
  const user = await requireUser();
  const [guests, tables] = await Promise.all([
    listGuests(user.id, id, q),
    listTables(user.id, id),
  ]);

  return (
    <GuestsManager eventId={id} guests={guests} tables={tables} initialSearch={q ?? ""} />
  );
}
