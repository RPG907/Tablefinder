"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import type { TableRow as EventTable } from "@/repositories/tables";
import { createTableAction, updateTableAction } from "./actions";

export function TableFormDialog({
  eventId,
  table,
  open,
  onOpenChange,
}: {
  eventId: string;
  table?: EventTable;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const router = useRouter();
  const [tableNumber, setTableNumber] = useState(table ? String(table.table_number) : "");
  const [name, setName] = useState(table?.name ?? "");
  const [capacity, setCapacity] = useState(table ? String(table.capacity) : "10");
  const [pending, startTransition] = useTransition();

  function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    startTransition(async () => {
      const input = {
        tableNumber: Number(tableNumber),
        name: name || null,
        capacity: Number(capacity),
      };
      const result = table
        ? await updateTableAction(eventId, table.id, input)
        : await createTableAction(eventId, input);
      if (!result.ok) {
        toast.error(result.error);
        return;
      }
      toast.success(table ? "Table modifiée" : "Table créée");
      onOpenChange(false);
      if (!table) {
        setTableNumber("");
        setName("");
        setCapacity("10");
      }
      router.refresh();
    });
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{table ? "Modifier la table" : "Nouvelle table"}</DialogTitle>
        </DialogHeader>
        <form onSubmit={onSubmit} className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <Label htmlFor="tableNumber">Numéro</Label>
              <Input
                id="tableNumber"
                type="number"
                min={1}
                max={9999}
                required
                value={tableNumber}
                onChange={(e) => setTableNumber(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="capacity">Capacité</Label>
              <Input
                id="capacity"
                type="number"
                min={1}
                max={100}
                required
                value={capacity}
                onChange={(e) => setCapacity(e.target.value)}
              />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="name">Nom (optionnel)</Label>
            <Input
              id="name"
              maxLength={60}
              placeholder="Table d'honneur"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          <DialogFooter>
            <Button type="submit" disabled={pending || !tableNumber}>
              {pending ? "Enregistrement..." : table ? "Enregistrer" : "Créer"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
