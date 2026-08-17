import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // pg est un module Node natif : il ne doit pas être bundlé.
  serverExternalPackages: ["pg"],
  // Un package-lock.json dans un dossier parent (hors de ce projet)
  // sinon Next.js infère une racine de workspace incorrecte.
  outputFileTracingRoot: path.join(__dirname),
};

export default nextConfig;
