import { notFound } from "next/navigation";
import { requireUser } from "@/lib/session";
import { getEvent } from "@/repositories/events";
import { SettingsForm } from "./settings-form";

export default async function EventSettingsPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const user = await requireUser();
  const event = await getEvent(user.id, id);
  if (!event) notFound();

  return <SettingsForm event={event} />;
}
