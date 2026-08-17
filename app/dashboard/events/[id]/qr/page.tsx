import { notFound } from "next/navigation";
import { requireUser } from "@/lib/session";
import { getEvent } from "@/repositories/events";
import { isR2Configured } from "@/lib/r2";
import { QrManager } from "./qr-manager";

export default async function QrPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const user = await requireUser();
  const event = await getEvent(user.id, id);
  if (!event) notFound();

  return <QrManager event={event} r2Configured={isR2Configured()} />;
}
