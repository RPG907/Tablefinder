import { ImportManager } from "./import-manager";

export default async function ImportPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return <ImportManager eventId={id} />;
}
