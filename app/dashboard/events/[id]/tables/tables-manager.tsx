"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Plus, Pencil, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from "@/components/ui/table";
import type { TableRow as EventTable } from "@/repositories/tables";
import { deleteTableAction } from "./actions";
import { TableFormDialog } from "./table-form-dialog";

export function TablesManager({
  eventId,
  tables,
}: {
  eventId: string;
  tables: EventTable[];
}) {
  const router = useRouter();
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<EventTable | undefined>(undefined);
  const [deletePending, startDeleteTransition] = useTransition();

  function openCreate() {
    setEditing(undefined);
    setDialogOpen(true);
  }

  function openEdit(table: EventTable) {
    setEditing(table);
    setDialogOpen(true);
  }

  function onDelete(table: EventTable) {
    const warning =
      table.guest_count > 0
        ? `Supprimer la table ${table.table_number} ? ${table.guest_count} invité(s) seront désassignés (pas supprimés).`
        : `Supprimer la table ${table.table_number} ?`;
    if (!confirm(warning)) return;
    startDeleteTransition(async () => {
      const result = await deleteTableAction(eventId, table.id);
      if (!result.ok) {
        toast.error(result.error);
        return;
      }
      toast.success("Table supprimée");
      router.refresh();
    });
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-sm text-neutral-500">
          {tables.length} table{tables.length > 1 ? "s" : ""}
        </p>
        <Button onClick={openCreate}>
          <Plus /> Ajouter une table
        </Button>
      </div>

      {tables.length === 0 ? (
        <div className="rounded-xl border border-dashed border-neutral-300 bg-white p-12 text-center">
          <p className="text-neutral-500">Aucune table pour l&apos;instant.</p>
        </div>
      ) : (
        <div className="rounded-xl border border-neutral-200 bg-white">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Numéro</TableHead>
                <TableHead>Nom</TableHead>
                <TableHead>Remplissage</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {tables.map((table) => (
                <TableRow key={table.id}>
                  <TableCell className="font-medium">{table.table_number}</TableCell>
                  <TableCell className="text-neutral-500">{table.name ?? "—"}</TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <span>
                        {table.guest_count} / {table.capacity}
                      </span>
                      {table.is_overbooked && (
                        <Badge variant="warning">Complète</Badge>
                      )}
                    </div>
                  </TableCell>
                  <TableCell className="text-right">
                    <Button
                      size="icon"
                      variant="ghost"
                      onClick={() => openEdit(table)}
                      aria-label="Modifier"
                    >
                      <Pencil className="size-4" />
                    </Button>
                    <Button
                      size="icon"
                      variant="ghost"
                      disabled={deletePending}
                      onClick={() => onDelete(table)}
                      aria-label="Supprimer"
                    >
                      <Trash2 className="size-4 text-red-600" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      <TableFormDialog
        eventId={eventId}
        table={editing}
        open={dialogOpen}
        onOpenChange={setDialogOpen}
      />
    </div>
  );
}
