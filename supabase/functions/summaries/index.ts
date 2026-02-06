import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type SummaryPayload = {
  headline: string;
  bullets: string[];
};

type SummaryRequest = {
  sessionId: string;
  transcript: string;
  title?: string | null;
};

const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
const openaiModel = Deno.env.get("OPENAI_SUMMARY_MODEL") ?? "gpt-4o-mini";
const openaiUrl = "https://api.openai.com/v1/responses";

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization") ?? req.headers.get("authorization");

  let payload: SummaryRequest;
  try {
    payload = await req.json();
  } catch (_error) {
    return jsonResponse({ error: "Invalid JSON payload." }, 400);
  }

  const sessionId = payload.sessionId?.trim();
  const transcript = payload.transcript?.trim();
  const title = payload.title?.trim();

  if (!sessionId || !transcript) {
    return jsonResponse({ error: "sessionId and transcript are required." }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
  if (!supabaseUrl || !supabaseKey) {
    return jsonResponse({ error: "Supabase credentials are not set." }, 500);
  }

  const supabase = createClient(
    supabaseUrl,
    supabaseKey,
    authHeader
      ? {
        global: {
          headers: { Authorization: authHeader },
        },
      }
      : undefined
  );

  if (authHeader) {
    const { data: existing, error: existingError } = await supabase
      .from("daily_summaries")
      .select("summary_json")
      .eq("session_id", sessionId)
      .maybeSingle();

    if (existingError) {
      return jsonResponse({ error: existingError.message }, 500);
    }

    if (existing?.summary_json) {
      const existingSummary = normalizeSummary(existing.summary_json as SummaryPayload, { transcript, title });
      const headline = existingSummary.headline.trim();
      if (headline) {
        const { error: titleError } = await supabase
          .from("journal_sessions")
          .update({ title: headline })
          .eq("id", sessionId);
        if (titleError) {
          console.error("Failed to update session title from existing summary", titleError.message);
        }
      }
      return jsonResponse({ summary: existingSummary });
    }
  }

  if (!openaiApiKey) {
    return jsonResponse({ error: "OPENAI_API_KEY is not set." }, 500);
  }

  const prompt = buildPrompt({ transcript, title });
  const generated = await generateSummaryWithOpenAI(prompt, openaiApiKey);
  const normalized = normalizeSummary(
    generated ?? fallbackSummaryFromTranscript(transcript, title),
    { transcript, title }
  );

  if (authHeader) {
    const { error: upsertError } = await supabase
      .from("daily_summaries")
      .upsert({
        session_id: sessionId,
        summary_json: normalized,
      }, { onConflict: "session_id" })
      .select("session_id")
      .single();

    if (upsertError) {
      return jsonResponse({ error: upsertError.message }, 500);
    }

    const headline = normalized.headline.trim();
    if (headline) {
      const { error: titleError } = await supabase
        .from("journal_sessions")
        .update({ title: headline })
        .eq("id", sessionId);
      if (titleError) {
        console.error("Failed to update session title", titleError.message);
      }
    }
  }

  return jsonResponse({ summary: normalized });
});

function buildPrompt(input: { transcript: string; title?: string }) {
  const title = input.title ? `Title: ${input.title}\n` : "";
  return [
    "Summarize this journal into JSON with keys: headline, bullets.",
    "headline: <= 60 characters.",
    "bullets: 2-4 concise statements.",
    "Return ONLY valid JSON.",
    title + "Transcript:\n" + input.transcript,
  ].join("\n");
}

async function generateSummaryWithOpenAI(
  prompt: string,
  apiKey: string
): Promise<SummaryPayload | null> {
  const messages = [
    {
      role: "system",
      content: "You summarize journals into a short headline and 2-4 concise bullets.",
    },
    { role: "user", content: prompt },
  ];

  const structuredBody = {
    model: openaiModel,
    input: messages,
    text: {
      format: {
        type: "json_schema",
        name: "journal_summary",
        strict: true,
        schema: {
          type: "object",
          additionalProperties: false,
          required: ["headline", "bullets"],
          properties: {
            headline: { type: "string" },
            bullets: { type: "array", items: { type: "string" } },
          },
        },
      },
    },
  };

  const structuredResponse = await fetch(openaiUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(structuredBody),
  });

  if (structuredResponse.ok) {
    const data = await structuredResponse.json();
    const outputText = extractOutputText(data);
    if (!outputText) return null;
    return safeJsonParse(outputText);
  }

  const structuredError = await structuredResponse.text();
  console.error("Structured summary call failed", structuredError);

  const fallbackResponse = await fetch(openaiUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: openaiModel,
      input: messages,
    }),
  });

  if (!fallbackResponse.ok) {
    const fallbackError = await fallbackResponse.text();
    console.error("Fallback summary call failed", fallbackError);
    return null;
  }

  const fallbackData = await fallbackResponse.json();
  const fallbackText = extractOutputText(fallbackData);
  if (!fallbackText) return null;

  const direct = safeJsonParse(fallbackText);
  if (direct) return direct;

  // Handles markdown code fences or surrounding text.
  const objectMatch = fallbackText.match(/\{[\s\S]*\}/);
  if (!objectMatch) return null;
  return safeJsonParse(objectMatch[0]);
}

function fallbackSummaryFromTranscript(transcript: string, title?: string): SummaryPayload {
  const lines = transcript
    .split(/\n+/)
    .map((line) => line.trim())
    .filter(Boolean);

  const headline = (title?.trim() || lines[0] || "Journal reflection").slice(0, 60).trim();
  const bullets = lines.slice(0, 4);

  if (bullets.length >= 2) {
    return { headline, bullets };
  }

  const words = transcript
    .replace(/\s+/g, " ")
    .trim()
    .split(" ")
    .filter(Boolean);

  const midpoint = Math.max(8, Math.floor(words.length / 2));
  const first = words.slice(0, midpoint).join(" ").trim();
  const second = words.slice(midpoint).join(" ").trim();

  return {
    headline,
    bullets: [first || "Reflection captured.", second || "Key thoughts recorded."],
  };
}

function extractOutputText(data: Record<string, unknown>): string | null {
  if (typeof data.output_text === "string") {
    return data.output_text;
  }

  const output = data.output;
  if (Array.isArray(output)) {
    for (const item of output) {
      const content = item?.content;
      if (!Array.isArray(content)) continue;
      for (const part of content) {
        if (typeof part?.text === "string") {
          return part.text;
        }
      }
    }
  }

  return null;
}

function safeJsonParse(text: string): SummaryPayload | null {
  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== "object") return null;
    return parsed as SummaryPayload;
  } catch (_error) {
    return null;
  }
}

function normalizeSummary(
  raw: SummaryPayload,
  fallback: { transcript: string; title?: string }
): SummaryPayload {
  const headlineRaw = typeof raw.headline === "string" ? raw.headline.trim() : "";
  const bulletsRaw = Array.isArray(raw.bullets) ? raw.bullets : [];

  const headlineFallback = fallback.title?.trim()
    || fallback.transcript.split(/\n+/)[0]?.trim()
    || "Journal reflection";

  let headline = headlineRaw || headlineFallback;
  if (headline.length > 60) {
    headline = headline.slice(0, 60).trim();
  }

  let bullets = bulletsRaw
    .map((bullet) => String(bullet).trim())
    .filter((bullet) => bullet.length > 0);

  if (bullets.length > 4) {
    bullets = bullets.slice(0, 4);
  }

  if (bullets.length < 2) {
    const fallbackLines = fallback.transcript
      .split(/\n+/)
      .map((line) => line.trim())
      .filter(Boolean);
    for (const line of fallbackLines) {
      if (bullets.length >= 2) break;
      if (!bullets.includes(line)) {
        bullets.push(line);
      }
    }
  }

  return { headline, bullets };
}

function jsonResponse(payload: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
