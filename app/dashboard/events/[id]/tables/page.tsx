import { requireUser } from "@/lib/session";
import { listTables } from "@/repositories/tables";
import { TablesManager } from "./tables-manager";

export default async function TablesPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const user = await requireUser();
  const tables = await listTables(user.id, id);

  return <TablesManager eventId={id} tables={tables} />;
}
