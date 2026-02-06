import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
const defaultTranscriptionModel = Deno.env.get("OPENAI_STREAM_TRANSCRIPTION_MODEL") ?? "gpt-4o-transcribe";

type SessionRequest = {
  model?: string;
};

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return new Response(
      JSON.stringify({ error: "Missing bearer authorization." }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  if (!openaiApiKey) {
    return new Response(
      JSON.stringify({ error: "OPENAI_API_KEY is not set." }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    const body = await req.json().catch(() => ({} as SessionRequest)) as SessionRequest;
    const model = typeof body.model === "string" && body.model.trim().length > 0
      ? body.model.trim()
      : defaultTranscriptionModel;

    const sessionPayload = {
      expires_after: {
        anchor: "created_at",
        seconds: 60,
      },
      session: {
        type: "transcription",
        audio: {
          input: {
            format: {
              type: "audio/pcm",
              rate: 24000,
            },
            transcription: {
              model,
            },
            turn_detection: {
              type: "server_vad",
              threshold: 0.5,
              prefix_padding_ms: 300,
              silence_duration_ms: 500,
            },
          },
        },
      },
    };

    const response = await fetch("https://api.openai.com/v1/realtime/client_secrets", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openaiApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(sessionPayload),
    });

    const responseText = await response.text();
    if (!response.ok) {
      return new Response(
        JSON.stringify({ error: responseText }),
        { status: response.status, headers: { "Content-Type": "application/json" } },
      );
    }

    const parsed = JSON.parse(responseText) as Record<string, unknown>;
    const value = typeof parsed.value === "string"
      ? parsed.value
      : typeof (parsed.client_secret as Record<string, unknown> | undefined)?.value === "string"
      ? (parsed.client_secret as Record<string, unknown>).value as string
      : "";

    if (!value) {
      return new Response(
        JSON.stringify({ error: "OpenAI returned no client secret value." }),
        { status: 502, headers: { "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({
        value,
        expires_at: parsed.expires_at ?? (parsed.client_secret as Record<string, unknown> | undefined)?.expires_at ?? null,
        session: parsed.session ?? null,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
