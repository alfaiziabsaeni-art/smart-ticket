import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { encodeBase64 } from "jsr:@std/encoding@1/base64";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Kategori Gemini -> nama divisi (sama dengan 4 divisi default)
const CATEGORY_TO_DIVISION: Record<string, string> = {
  Listrik: "Teknis",
  Medis: "Medis",
  Keamanan: "Keamanan",
  Logistik: "Logistik",
  Kebersihan: "Logistik",
};

// Model cadangan kalau daftar model gagal diambil
const FALLBACK_MODELS = ["gemini-flash-latest", "gemini-2.5-flash", "gemini-flash-lite-latest"];

function geminiKey(): string {
  const key = Deno.env.get("GEMINI_API_KEY")?.trim();
  if (!key) throw new Error("GEMINI_API_KEY belum di-set di Supabase (Edge Functions > Secrets)");
  return key;
}

let cachedModels: string[] | null = null;

// Cari model Flash & Flash-Lite yang tersedia untuk key ini
async function listFlashModels(): Promise<string[]> {
  if (cachedModels) return cachedModels;
  let names: string[] = [];
  try {
    const res = await fetch(
      "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200",
      { headers: { "x-goog-api-key": geminiKey() }, signal: AbortSignal.timeout(8000) },
    );
    const json = await res.json();
    if (!res.ok) {
      // Key salah / lokasi tidak didukung: langsung kasih tahu, jangan coba model lain
      throw new Error(`Gemini menolak API key (${res.status}): ${json?.error?.message ?? ""}`);
    }
    names = (json.models ?? [])
      .filter((m: any) => m.supportedGenerationMethods?.includes("generateContent"))
      .map((m: any) => String(m.name).replace("models/", ""))
      .filter((n: string) =>
        n.includes("flash") && !/image|tts|live|audio|embedding|robotics|computer|omni/.test(n)
      );
    // Model stabil dulu (bukan preview/exp), terbaru dulu
    const stable = names
      .filter((n) => !/preview|exp/.test(n))
      .sort((a, b) => b.localeCompare(a));
    // Selang-seling Flash dan Flash-Lite: kuota gratis tiap model terpisah,
    // jadi kalau satu penuh/sibuk (429/503) masih ada cadangan
    const flash = stable.filter((n) => !n.includes("lite"));
    const lite = stable.filter((n) => n.includes("lite"));
    names = [];
    for (let i = 0; i < Math.max(flash.length, lite.length); i++) {
      if (flash[i]) names.push(flash[i]);
      if (lite[i]) names.push(lite[i]);
    }
  } catch (e) {
    if (String(e).includes("menolak API key")) throw e;
    console.error("list models gagal:", String(e));
  }
  names.push(...FALLBACK_MODELS);
  const override = Deno.env.get("GEMINI_MODEL");
  if (override) names.unshift(override);
  cachedModels = [...new Set(names)].slice(0, 6);
  console.log("model kandidat:", cachedModels.join(", "));
  return cachedModels;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function callGemini(body: unknown): Promise<string> {
  const models = await listFlashModels();
  const errors: string[] = [];
  const deadline = Date.now() + 110_000; // Edge Function maksimal ~150 detik

  for (const model of models) {
    // 503 = model lagi sibuk: coba sekali lagi setelah jeda singkat
    for (let attempt = 1; attempt <= 2; attempt++) {
      if (Date.now() > deadline) break;
      try {
        const res = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json", "x-goog-api-key": geminiKey() },
            body: JSON.stringify(body),
            signal: AbortSignal.timeout(30000),
          },
        );
        const json = await res.json();
        console.log("gemini", model, "percobaan", attempt, "status", res.status);
        const text = json?.candidates?.[0]?.content?.parts
          ?.map((p: any) => p.text ?? "")
          .join("");
        if (res.ok && text) return text;

        const why = String(json?.error?.message ?? json?.candidates?.[0]?.finishReason ?? "jawaban kosong");
        console.error("gemini", model, res.status, why);
        // 400/401/403 = masalah key atau request, model lain pasti gagal juga
        if ([400, 401, 403].includes(res.status)) {
          throw new Error(`Gemini menolak request (${res.status}): ${why.split("\n")[0]}`);
        }
        if (res.status === 503 && attempt === 1) {
          await sleep(1500);
          continue;
        }
        // Cukup kalimat pertama biar pesan di HP nggak kepanjangan
        errors.push(`${model} ${res.status === 429 ? "kuota habis" : res.status === 503 ? "sibuk" : res.status}`);
        break;
      } catch (e) {
        if (String(e).includes("menolak request")) throw e;
        console.error("gemini", model, String(e));
        errors.push(`${model} timeout/error`);
        break;
      }
    }
  }
  throw new Error("Gemini gagal (" + errors.join(", ") + "). Coba lagi sebentar, atau ganti GEMINI_API_KEY kalau kuota harian habis.");
}

// Ambil JSON dari jawaban AI (buang ```json ... ``` kalau ada)
function parseAiJson(text: string): any {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end < 0) throw new Error("Jawaban AI bukan JSON: " + text.slice(0, 200));
  return JSON.parse(text.slice(start, end + 1));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const { event_id, reporter_name, audio_url, photo_url } = await req.json();
    if (!event_id || !audio_url) {
      return new Response(JSON.stringify({ error: "event_id dan audio_url wajib" }),
        { status: 400, headers: { ...cors, "Content-Type": "application/json" } });
    }

    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Ambil zona & divisi acara
    const { data: ev } = await db.from("events").select("zones").eq("id", event_id).single();
    const { data: divs } = await db.from("divisions").select("id,name").eq("event_id", event_id);
    const zones: string[] = ev?.zones ?? [];

    // Unduh audio
    const audioRes = await fetch(audio_url, { signal: AbortSignal.timeout(15000) });
    if (!audioRes.ok) {
      throw new Error(`Gagal unduh audio (status ${audioRes.status}). Pastikan bucket "audio" Public.`);
    }
    const audioBytes = new Uint8Array(await audioRes.arrayBuffer());
    if (audioBytes.length < 2000) throw new Error("Audio terlalu pendek, tahan tombol lebih lama");
    let mime = (audioRes.headers.get("content-type") ?? "").split(";")[0].trim();
    if (!mime.startsWith("audio/")) mime = "audio/wav";
    console.log("audio", mime, audioBytes.length, "bytes");

    const prompt = `Kamu asisten triase laporan lapangan acara. Dengarkan audio (Bahasa Indonesia/informal) dan balas HANYA JSON:
{"transcript": string, "category": "Listrik"|"Medis"|"Keamanan"|"Logistik"|"Kebersihan"|"Lainnya",
 "zone": salah satu dari [${zones.join(", ")}] atau null bila tidak jelas,
 "urgency": "low"|"medium"|"high",
 "confidence_score": angka 0 sampai 1 (turunkan bila audio bising atau tidak jelas)}`;

    const text = await callGemini({
      contents: [{
        parts: [
          { text: prompt },
          { inline_data: { mime_type: mime, data: encodeBase64(audioBytes) } },
        ],
      }],
      generationConfig: { responseMimeType: "application/json" },
    });
    const ai = parseAiJson(text);

    // Triase: >= 0.85 langsung masuk divisi, di bawah itu ke Review Queue
    const score = Number(ai.confidence_score ?? 0);
    const u = String(ai.urgency ?? "").toLowerCase();
    const urgency = ["low", "medium", "high"].includes(u) ? u : "medium";
    const divName = CATEGORY_TO_DIVISION[ai.category];
    const division = divs?.find((d) => d.name.toLowerCase() === divName?.toLowerCase());
    const status = score >= 0.85 ? "incoming" : "review";

    const { data: ticket, error } = await db.from("tickets").insert({
      event_id,
      division_id: division?.id ?? null,
      reporter_name,
      category: ai.category,
      zone: ai.zone,
      urgency,
      confidence_score: score,
      transcript: ai.transcript,
      audio_url,
      photo_url: photo_url ?? null,
      status,
    }).select().single();
    if (error) throw error;

    await db.from("logs").insert({ ticket_id: ticket.id, action: "created", actor: reporter_name });

    return new Response(JSON.stringify(ticket),
      { headers: { ...cors, "Content-Type": "application/json" } });
  } catch (e) {
    const msg = e instanceof Error ? e.message : JSON.stringify(e);
    console.error("process-ticket error:", msg);
    return new Response(JSON.stringify({ error: msg }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } });
  }
});