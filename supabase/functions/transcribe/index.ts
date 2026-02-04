import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const openaiApiKey = Deno.env.get("OPENAI_API_KEY");

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  if (!openaiApiKey) {
    return new Response(
      JSON.stringify({ error: "OPENAI_API_KEY is not set." }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    const { audioBase64, mimeType, fileName, prompt } = await req.json();
    if (!audioBase64) {
      return new Response(
        JSON.stringify({ error: "audioBase64 is required." }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const bytes = Uint8Array.from(atob(audioBase64), (char) =>
      char.charCodeAt(0)
    );
    const file = new File([bytes], fileName ?? "recording.m4a", {
      type: mimeType ?? "audio/mp4",
    });

    const form = new FormData();
    form.append("model", "gpt-4o-mini-transcribe");
    form.append("file", file);
    if (prompt) {
      form.append("prompt", prompt);
    }

    const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openaiApiKey}`,
      },
      body: form,
    });

    if (!response.ok) {
      const errorText = await response.text();
      return new Response(
        JSON.stringify({ error: errorText }),
        { status: response.status, headers: { "Content-Type": "application/json" } },
      );
    }

    const data = await response.json();
    const text = data.text ?? "";

    return new Response(
      JSON.stringify({ text }),
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
