"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Download, Trash2 } from "lucide-react";
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
import { Alert, AlertDescription } from "@/components/ui/alert";
import type { EventDetail } from "@/repositories/events";
import { updateQrSettingsAction, uploadQrLogoAction, removeQrLogoAction } from "./actions";

const HEX_RE = /^#[0-9a-fA-F]{6}$/;

export function QrManager({
  event,
  r2Configured,
}: {
  event: EventDetail;
  r2Configured: boolean;
}) {
  const router = useRouter();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [foreground, setForeground] = useState(event.qr_foreground);
  const [background, setBackground] = useState(event.qr_background);
  const [caption, setCaption] = useState(event.qr_caption ?? "");
  const [savePending, startSaveTransition] = useTransition();
  const [uploadPending, startUploadTransition] = useTransition();
  const [removePending, startRemoveTransition] = useTransition();
  const [previewTick, setPreviewTick] = useState(0);

  const previewSrc = `/api/qr/${event.slug}?format=png&t=${previewTick}`;
  const downloadPngHref = `/api/qr/${event.slug}?format=png&download=1`;
  const downloadSvgHref = `/api/qr/${event.slug}?format=svg&download=1`;

  function onSave(e: React.FormEvent) {
    e.preventDefault();
    if (!HEX_RE.test(foreground) || !HEX_RE.test(background)) {
      toast.error("Couleurs invalides");
      return;
    }
    startSaveTransition(async () => {
      const result = await updateQrSettingsAction(event.id, {
        qrForeground: foreground,
        qrBackground: background,
        qrCaption: caption || null,
      });
      if (!result.ok) {
        toast.error(result.error);
        return;
      }
      toast.success("Enregistré");
      setPreviewTick((t) => t + 1);
      router.refresh();
    });
  }

  function onUploadLogo(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    const formData = new FormData();
    formData.set("file", file);
    startUploadTransition(async () => {
      const result = await uploadQrLogoAction(event.id, formData);
      if (!result.ok) {
        toast.error(result.error);
        return;
      }
      toast.success("Logo mis à jour");
      setPreviewTick((t) => t + 1);
      if (fileInputRef.current) fileInputRef.current.value = "";
      router.refresh();
    });
  }

  function onRemoveLogo() {
    startRemoveTransition(async () => {
      const result = await removeQrLogoAction(event.id);
      if (!result.ok) {
        toast.error(result.error);
        return;
      }
      toast.success("Logo retiré");
      setPreviewTick((t) => t + 1);
      router.refresh();
    });
  }

  return (
    <div className="grid max-w-3xl grid-cols-1 gap-6 sm:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>Personnalisation</CardTitle>
          <CardDescription>
            Le QR Code pointe vers la page publique de cet événement.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <form onSubmit={onSave} className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-1.5">
                <Label htmlFor="foreground">Couleur du motif</Label>
                <div className="flex items-center gap-2">
                  <input
                    type="color"
                    aria-label="Couleur du motif"
                    value={foreground}
                    onChange={(e) => setForeground(e.target.value)}
                    className="size-9 rounded border border-neutral-200"
                  />
                  <Input
                    id="foreground"
                    value={foreground}
                    onChange={(e) => setForeground(e.target.value)}
                    className="font-mono text-xs"
                  />
                </div>
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="background">Couleur de fond</Label>
                <div className="flex items-center gap-2">
                  <input
                    type="color"
                    aria-label="Couleur de fond"
                    value={background}
                    onChange={(e) => setBackground(e.target.value)}
                    className="size-9 rounded border border-neutral-200"
                  />
                  <Input
                    id="background"
                    value={background}
                    onChange={(e) => setBackground(e.target.value)}
                    className="font-mono text-xs"
                  />
                </div>
              </div>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="caption">Légende (optionnelle)</Label>
              <Input
                id="caption"
                maxLength={60}
                placeholder="Scannez pour trouver votre table"
                value={caption}
                onChange={(e) => setCaption(e.target.value)}
              />
            </div>
            <Button type="submit" disabled={savePending}>
              {savePending ? "Enregistrement..." : "Enregistrer"}
            </Button>
          </form>

          <div className="space-y-2 border-t border-neutral-100 pt-4">
            <Label>Logo central</Label>
            {!r2Configured ? (
              <Alert>
                <AlertDescription>
                  Cloudflare R2 n&apos;est pas configuré : le logo personnalisé est
                  indisponible (voir <code>.env.local</code>). Les couleurs et la
                  légende fonctionnent normalement.
                </AlertDescription>
              </Alert>
            ) : (
              <div className="flex items-center gap-2">
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="image/png,image/jpeg,image/webp"
                  onChange={onUploadLogo}
                  disabled={uploadPending}
                  className="text-sm"
                />
                {event.qr_logo_key && (
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    onClick={onRemoveLogo}
                    disabled={removePending}
                    aria-label="Retirer le logo"
                  >
                    <Trash2 className="size-4 text-red-600" />
                  </Button>
                )}
              </div>
            )}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Aperçu</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-center rounded-lg border border-neutral-200 bg-white p-6">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              key={previewTick}
              src={previewSrc}
              alt="Aperçu du QR Code"
              width={256}
              height={256}
              className="size-64"
            />
          </div>
          <div className="flex gap-2">
            <Button asChild variant="outline" size="sm">
              <a href={downloadPngHref} download={`qr-${event.slug}.png`}>
                <Download /> PNG
              </a>
            </Button>
            <Button asChild variant="outline" size="sm">
              <a href={downloadSvgHref} download={`qr-${event.slug}.svg`}>
                <Download /> SVG
              </a>
            </Button>
          </div>
          {!event.is_published && (
            <Alert variant="warning">
              <AlertDescription>
                La page publique est masquée : le QR Code renverra
                &laquo;&nbsp;introuvable&nbsp;&raquo; tant qu&apos;elle n&apos;est pas
                publiée dans l&apos;onglet Réglages.
              </AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
