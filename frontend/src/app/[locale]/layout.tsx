import { hasLocale } from "next-intl";
import { notFound } from "next/navigation";
import { getMessages, getTranslations, setRequestLocale } from "next-intl/server";
import { NextIntlClientProvider } from "next-intl";
import Script from "next/script";
import { routing } from "@/i18n/routing";
import { Providers } from "./providers";
import { StartupGate } from "@/components/layout/StartupGate";
import Navbar from "@/components/layout/Navbar";
import { WorkspacePages } from "@/components/layout/WorkspacePages";

const CRYPTO_RANDOM_UUID_POLYFILL = `(function(){var c=globalThis.crypto;if(!c||typeof c.randomUUID==="function")return;function u(){if(typeof c.getRandomValues==="function"){var b=new Uint8Array(16);c.getRandomValues(b);b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;var h=Array.from(b,function(x){return x.toString(16).padStart(2,"0")}).join("");return h.slice(0,8)+"-"+h.slice(8,12)+"-"+h.slice(12,16)+"-"+h.slice(16,20)+"-"+h.slice(20)}return"xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g,function(ch){var r=Math.random()*16|0;return(ch==="x"?r:(r&3)|8).toString(16)})}try{Object.defineProperty(c,"randomUUID",{value:u,configurable:true,writable:true})}catch(e){c.randomUUID=u}})();`;

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "nav" });
  return { title: t("title") };
}

export default async function LocaleLayout({
  children,
  modal,
  params,
}: {
  children: React.ReactNode;
  modal: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;

  if (!hasLocale(routing.locales, locale)) {
    notFound();
  }

  setRequestLocale(locale);

  const messages = await getMessages();

  return (
    <html lang={locale} className="h-full antialiased" suppressHydrationWarning>
      <head>
        <Script id="crypto-randomuuid-polyfill" strategy="beforeInteractive">
          {CRYPTO_RANDOM_UUID_POLYFILL}
        </Script>
      </head>
      <body className="min-h-full flex flex-col bg-background text-foreground">
        <NextIntlClientProvider messages={messages}>
          <Providers locale={locale}>
            <StartupGate>
              <Navbar />
              <main className="flex min-h-0 flex-1 flex-col"><WorkspacePages>{children}</WorkspacePages></main>
              {modal}
            </StartupGate>
          </Providers>
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
