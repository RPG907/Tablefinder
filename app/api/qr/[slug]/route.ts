import { NextRequest, NextResponse } from "next/server";
import QRCode from "qrcode";
import sharp from "sharp";
import { getPublicQrSettings } from "@/repositories/public-search";
import { fetchLogoBuffer } from "@/lib/r2";

/**
 * Génère le QR Code d'un événement à la volée : sharp + qrcode
 * nécessitent Node (pas de sockets/fs sous Edge).
 */
export const runtime = "nodejs";

const SIZE = 1024;

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;

  // SECURITY DEFINER, muet si l'événement n'existe pas ou est
  // dépublié — même comportement que la page publique.
  const settings = await getPublicQrSettings(slug);
  if (!settings) {
    return NextResponse.json({ error: "Introuvable" }, { status: 404 });
  }

  const url = new URL(req.url);
  const format = url.searchParams.get("format") === "svg" ? "svg" : "png";
  const download = url.searchParams.get("download") === "1";
  const targetUrl = `${process.env.NEXT_PUBLIC_APP_URL || url.origin}/e/${slug}`;
  const color = { dark: settings.qr_foreground, light: settings.qr_background };

  if (format === "svg") {
    const svg = await QRCode.toString(targetUrl, {
      type: "svg",
      color,
      margin: 2,
      errorCorrectionLevel: "H",
      width: SIZE,
    });
    return new NextResponse(svg, {
      headers: {
        "content-type": "image/svg+xml",
        "cache-control": "public, max-age=60",
        ...(download && { "content-disposition": `attachment; filename="qr-${slug}.svg"` }),
      },
    });
  }

  let png = await QRCode.toBuffer(targetUrl, {
    type: "png",
    color,
    margin: 2,
    errorCorrectionLevel: "H",
    width: SIZE,
  });

  if (settings.qr_logo_key) {
    png = await compositeLogo(png, settings.qr_logo_key, settings.qr_background);
  }

  return new NextResponse(new Uint8Array(png), {
    headers: {
      "content-type": "image/png",
      "cache-control": "public, max-age=60",
      ...(download && { "content-disposition": `attachment; filename="qr-${slug}.png"` }),
    },
  });
}

/**
 * Superpose le logo au centre, sur un cadre de la couleur de fond
 * (sinon le logo mangerait des modules du QR et le rendrait
 * illisible sur cette zone). errorCorrectionLevel "H" tolère la
 * perte d'environ 30% des modules, d'où la taille limitée à 22%.
 */
async function compositeLogo(
  qrPng: Buffer,
  logoKey: string,
  background: string,
): Promise<Buffer> {
  try {
    const logoBuffer = await fetchLogoBuffer(logoKey);
    const logoSize = Math.round(SIZE * 0.2);
    const pad = Math.round(logoSize * 0.15);
    const frame = logoSize + pad * 2;

    const resizedLogo = await sharp(logoBuffer)
      .resize(logoSize, logoSize, { fit: "cover" })
      .toBuffer();

    const frameBuffer = await sharp({
      create: { width: frame, height: frame, channels: 4, background },
    })
      .composite([{ input: resizedLogo, top: pad, left: pad }])
      .png()
      .toBuffer();

    const offset = Math.round((SIZE - frame) / 2);

    return await sharp(qrPng)
      .composite([{ input: frameBuffer, top: offset, left: offset }])
      .png()
      .toBuffer();
  } catch {
    // Le QR reste utilisable sans logo si R2 est indisponible.
    return qrPng;
  }
}
