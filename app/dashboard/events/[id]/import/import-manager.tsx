"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import Papa from "papaparse";
import { toast } from "sonner";
import { Upload, FileWarning } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/ui/card";
import { Alert, AlertTitle, AlertDescription } from "@/components/ui/alert";
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from "@/components/ui/table";
import type { ImportRow, ImportResult } from "@/repositories/import";
import { importGuestsAction } from "./actions";

const MAX_ROWS = 2000;

const HEADER_ALIASES: Record<string, "first_name" | "last_name" | "table_number"> = {
  first_name: "first_name",
  firstname: "first_name",
  prenom: "first_name",
  last_name: "last_name",
  lastname: "last_name",
  nom: "last_name",
  table_number: "table_number",
  table: "table_number",
  numero_table: "table_number",
  numerotable: "table_number",
};

function normalizeHeader(header: string): string {
  return header
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function parseCsvRows(raw: Record<string, string>[]): ImportRow[] {
  const rows: ImportRow[] = [];
  for (const record of raw) {
    const row: ImportRow = { first_name: "", last_name: "", table_number: null };
    let hasValue = false;
    for (const [rawKey, rawValue] of Object.entries(record)) {
      const key = HEADER_ALIASES[normalizeHeader(rawKey)];
      if (!key) continue;
      const value = (rawValue ?? "").trim();
      if (!value) continue;
      hasValue = true;
      if (key === "table_number") {
        const parsed = Number.parseInt(value, 10);
        row.table_number = Number.isFinite(parsed) ? parsed : null;
      } else {
        row[key] = value;
      }
    }
    if (hasValue) rows.push(row);
  }
  return rows;
}

export function ImportManager({ eventId }: { eventId: string }) {
  const router = useRouter();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [rows, setRows] = useState<ImportRow[]>([]);
  const [parseError, setParseError] = useState<string | null>(null);
  const [defaultCapacity, setDefaultCapacity] = useState("10");
  const [result, setResult] = useState<ImportResult | null>(null);
  const [pending, startTransition] = useTransition();

  function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setResult(null);
    setParseError(null);
    setFileName(file.name);

    Papa.parse<Record<string, string>>(file, {
      header: true,
      skipEmptyLines: true,
      complete: (results) => {
        const parsed = parseCsvRows(results.data);
        if (parsed.length === 0) {
          setRows([]);
          setParseError(
            "Aucune ligne exploitable. Colonnes attendues : first_name (ou prenom), last_name (ou nom), table_number (ou table).",
          );
          return;
        }
        if (parsed.length > MAX_ROWS) {
          setRows([]);
          setParseError(
            `${parsed.length} lignes trouvées, maximum ${MAX_ROWS}. Séparez le fichier en plusieurs imports.`,
          );
          return;
        }
        setRows(parsed);
      },
      error: (error) => {
        setParseError(error.message);
      },
    });
  }

  function runImport(createMissingTables: boolean) {
    startTransition(async () => {
      const cap = Math.max(1, Math.min(100, Number(defaultCapacity) || 10));
      const actionResult = await importGuestsAction(
        eventId,
        rows,
        createMissingTables,
        cap,
      );
      if (!actionResult.ok) {
        toast.error(actionResult.error);
        return;
      }
      setResult(actionResult.data);
      if (actionResult.data.status === "ok") {
        toast.success(`${actionResult.data.inserted} invité(s) importé(s)`);
        router.refresh();
      }
    });
  }

  function reset() {
    setFileName(null);
    setRows([]);
    setResult(null);
    setParseError(null);
    if (fileInputRef.current) fileInputRef.current.value = "";
  }

  return (
    <div className="max-w-2xl space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Importer un CSV</CardTitle>
          <CardDescription>
            Colonnes attendues : <code>first_name</code>, <code>last_name</code>,{" "}
            <code>table_number</code> (les alias <code>prenom</code>, <code>nom</code>,{" "}
            <code>table</code> fonctionnent aussi). 2000 lignes maximum.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center gap-3">
            <Input
              ref={fileInputRef}
              type="file"
              accept=".csv,text/csv"
              onChange={onFileChange}
              className="max-w-xs"
            />
            {fileName && (
              <Button type="button" variant="ghost" size="sm" onClick={reset}>
                Effacer
              </Button>
            )}
          </div>

          {parseError && (
            <Alert variant="destructive">
              <FileWarning />
              <AlertTitle>Fichier invalide</AlertTitle>
              <AlertDescription>{parseError}</AlertDescription>
            </Alert>
          )}

          {rows.length > 0 && !result && (
            <>
              <p className="text-sm text-neutral-500">
                {rows.length} ligne{rows.length > 1 ? "s" : ""} détectée
                {rows.length > 1 ? "s" : ""}.
              </p>
              <div className="max-h-64 overflow-y-auto rounded-lg border border-neutral-200">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Prénom</TableHead>
                      <TableHead>Nom</TableHead>
                      <TableHead>Table</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.slice(0, 20).map((row, i) => (
                      <TableRow key={i}>
                        <TableCell>{row.first_name || "—"}</TableCell>
                        <TableCell>{row.last_name || "—"}</TableCell>
                        <TableCell>{row.table_number ?? "—"}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
              {rows.length > 20 && (
                <p className="text-xs text-neutral-400">
                  Aperçu limité aux 20 premières lignes.
                </p>
              )}

              <div className="flex items-end gap-3">
                <div className="space-y-1.5">
                  <Label htmlFor="defaultCapacity">
                    Capacité par défaut des tables créées
                  </Label>
                  <Input
                    id="defaultCapacity"
                    type="number"
                    min={1}
                    max={100}
                    className="w-32"
                    value={defaultCapacity}
                    onChange={(e) => setDefaultCapacity(e.target.value)}
                  />
                </div>
                <Button onClick={() => runImport(false)} disabled={pending}>
                  <Upload /> {pending ? "Import..." : "Importer"}
                </Button>
              </div>
            </>
          )}

          {result?.status === "missing_tables" && (
            <Alert variant="warning">
              <FileWarning />
              <AlertTitle>Tables manquantes</AlertTitle>
              <AlertDescription className="space-y-3">
                <p>
                  Les tables {result.missing_tables.join(", ")} n&apos;existent pas
                  encore. Rien n&apos;a été importé.
                </p>
                <Button size="sm" onClick={() => runImport(true)} disabled={pending}>
                  {pending ? "Import..." : "Créer les tables manquantes et importer"}
                </Button>
              </AlertDescription>
            </Alert>
          )}

          {result?.status === "ok" && (
            <Alert variant="success">
              <AlertTitle>Import terminé</AlertTitle>
              <AlertDescription>
                {result.inserted} invité(s) importé(s)
                {result.created_tables > 0 &&
                  `, ${result.created_tables} table(s) créée(s)`}
                {result.skipped > 0 && `, ${result.skipped} ligne(s) vide(s) ignorée(s)`}
                .
              </AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
