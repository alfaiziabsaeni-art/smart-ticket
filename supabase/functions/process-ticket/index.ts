import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Kategori Gemini -> nama divisi (sesuaikan dengan divisi yang dibuat Farrel)
const CATEGORY_TO_DIVISION: Record<string, string> = {
  Listrik: "Teknis",
  Medis: "Medis",
  Keamanan: "Keamanan",
  Logistik: "Logistik",
  Kebersihan: "Logistik",
};

function toBase64(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(bin);
}

let cachedModels: string[] | null = null;

// Cari model Flash yang tersedia untuk key ini: stabil dulu, lite belakangan
async function listFlashModels(): Promise<string[]> {
  if (cachedModels) return cachedModels;
  let names: string[] = [];
  try {
    const res = await fetch(
      "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200",
      {
        headers: { "x-goog-api-key": Deno.env.get("GEMINI_API_KEY")! },
        signal: AbortSignal.timeout(8000),
      },
    );
    const json = await res.json();
    names = (json.models ?? [])
      .filter((m: any) => m.supportedGenerationMethods?.includes("generateContent"))
      .map((m: any) => String(m.name).replace("models/", ""))
      .filter((n: string) =>
        n.includes("flash") && !/image|tts|live|audio|embedding|robotics|computer|omni/.test(n)
      );
    const rank = (n: string) =>
      (/preview|exp/.test(n) ? 2 : 0) + (n.includes("lite") ? 1 : 0);
    names.sort((a, b) => rank(a) - rank(b) || b.localeCompare(a));
  } catch (e) {
    console.error("list models gagal:", String(e));
  }
  if (names.length === 0) names = ["gemini-flash-latest", "gemini-flash-lite-latest"];
  const override = Deno.env.get("GEMINI_MODEL");
  if (override) names.unshift(override);
  cachedModels = names.slice(0, 4);
  console.log("model kandidat:", cachedModels.join(", "));
  return cachedModels;
}

async function callGemini(body: unknown): Promise<any> {
  const models = await listFlashModels();
  let last: unknown;
  for (const model of models) {
    try {
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": Deno.env.get("GEMINI_API_KEY")!,
          },
          body: JSON.stringify(body),
              signal: AbortSignal.timeout(45000),
        },
      );
      const json = await res.json();
      console.log("gemini", model, "status", res.status);
      if (json?.candidates?.[0]?.content?.parts?.[0]?.text) return json;
      last = json;
    } catch (e) {
      console.error("gemini", model, String(e));
      last = String(e);
    }
  }
  throw new Error("Semua model Gemini gagal: " + JSON.stringify(last));
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
    if (!audioRes.ok) throw new Error("Gagal unduh audio, status " + audioRes.status);
    const mime = (audioRes.headers.get("content-type") ?? "audio/wav").split(";")[0];
    const audioB64 = toBase64(await audioRes.arrayBuffer());

    const prompt = `Kamu asisten triase laporan lapangan acara. Dengarkan audio (Bahasa Indonesia/informal) dan balas HANYA JSON:
{"transcript": string, "category": "Listrik"|"Medis"|"Keamanan"|"Logistik"|"Kebersihan"|"Lainnya",
 "zone": salah satu dari [${zones.join(", ")}] atau null bila tidak jelas,
 "urgency": "low"|"medium"|"high",
 "confidence_score": angka 0 sampai 1 (turunkan bila audio bising atau tidak jelas)}`;

    const gJson = await callGemini({
      contents: [{ parts: [{ text: prompt }, { inline_data: { mime_type: mime, data: audioB64 } }] }],
      generationConfig: { responseMimeType: "application/json" },
    });
    const ai = JSON.parse(gJson.candidates[0].content.parts[0].text);

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