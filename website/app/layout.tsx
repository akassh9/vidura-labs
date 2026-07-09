import type { Metadata } from "next";
import { headers } from "next/headers";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("host") ?? "vidura-labs.local";
  const protocol = host.startsWith("localhost") ? "http" : "https";
  const metadataBase = new URL(`${protocol}://${host}`);

  return {
    metadataBase,
    title: "Vidura Labs | Reproducible physics runs",
    description: "A native macOS research companion for inspectable, reproducible high-energy physics simulations with Pythia 8.",
    openGraph: {
      title: "Vidura Labs | Reproducible physics runs",
      description: "From physics question to verified run record.",
      images: [{ url: "/og.png", width: 1200, height: 630, alt: "Vidura Labs reproducible physics runs" }],
    },
    twitter: {
      card: "summary_large_image",
      title: "Vidura Labs | Reproducible physics runs",
      description: "From physics question to verified run record.",
      images: ["/og.png"],
    },
  };
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
