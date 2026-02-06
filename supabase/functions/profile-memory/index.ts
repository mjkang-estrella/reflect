import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  applyStateUpdate,
  mergeProfileJson,
  sanitizeModelResponse,
  updatedProfileForResponse,
  withProfileDefaults,
} from "./core.ts";

type SummaryPayload = {
  headline: string;
  bullets: string[];
};

type ProfileMemoryRequest = {
  sessionId: string;
  transcript: string;
  summary: SummaryPayload;
};

type MeDbRecord = {
  user_id: string;
  profile_json: Record<string, unknown>;
  state_json: Record<string, unknown>;
  patterns_json: Record<string, unknown>;
  trust_json: Record<string, unknown>;
};

const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
const openaiModel = Deno.env.get("OPENAI_PROFILE_MEMORY_MODEL") ?? "gpt-4o-mini";
const openaiUrl = "https://api.openai.com/v1/responses";

const systemPrompt = [
  "You maintain a user's journaling profile from one completed journal session.",
  "Be conservative and evidence-based.",
  "",
  "Rules:",
  "- Output ONLY valid JSON matching the provided schema.",
  "- Never invent facts.",
  "- Update only when explicit first-person evidence exists in transcript or summary.",
  "- If evidence is weak or ambiguous, use null / empty arrays.",
  "- Do not infer medical diagnoses, legal claims, or protected attributes.",
  "- Keep avoidTopics entries short (max 4 words), lowercase, deduplicated.",
  "- notesAppend must be <= 220 characters.",
].join("\n");

serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? req.headers.get("authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header." }, 401);
  }

  let payload: ProfileMemoryRequest;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON payload." }, 400);
  }

  const sessionId = payload.sessionId?.trim();
  const transcript = payload.transcript?.trim();
  const summary = payload.summary;

  if (!sessionId || !transcript || !summary || typeof summary.headline !== "string" || !Array.isArray(summary.bullets)) {
    return jsonResponse({ error: "sessionId, transcript, and summary are required." }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
  if (!supabaseUrl || !supabaseKey) {
    return jsonResponse({ error: "Supabase credentials are not set." }, 500);
  }

  const supabase = createClient(supabaseUrl, supabaseKey, {
    global: {
      headers: { Authorization: authHeader },
    },
  });

  const { data: authUser, error: authError } = await supabase.auth.getUser();
  if (authError || !authUser.user?.id) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }
  const userId = authUser.user.id;

  const { data: existingRow, error: existingError } = await supabase
    .from("me_db")
    .select("user_id, profile_json, state_json, patterns_json, trust_json")
    .eq("user_id", userId)
    .maybeSingle();

  if (existingError) {
    return jsonResponse({ error: existingError.message }, 500);
  }

  const existing: MeDbRecord = {
    user_id: userId,
    profile_json: withProfileDefaults(existingRow?.profile_json ?? {}),
    state_json: existingRow?.state_json ?? {},
    patterns_json: existingRow?.patterns_json ?? {},
    trust_json: existingRow?.trust_json ?? {},
  };

  const preState = applyStateUpdate(existing.state_json, sessionId, null, false);
  if (preState.duplicate) {
    return jsonResponse({
      applied: true,
      reason: "duplicate_session",
      updatedProfile: updatedProfileForResponse(existing.profile_json),
      sessionId,
    });
  }

  if (!openaiApiKey) {
    return jsonResponse({ error: "OPENAI_API_KEY is not set." }, 500);
  }

  const userPrompt = buildUserPrompt({
    profileJson: existing.profile_json,
    stateJson: existing.state_json,
    sessionId,
    summary,
    transcript,
  });

  const modelOutput = await generatePatchWithOpenAI(systemPrompt, userPrompt);
  if (!modelOutput) {
    return jsonResponse({ error: "Failed to generate profile patch." }, 500);
  }

  const sanitized = sanitizeModelResponse(modelOutput);

  const profileMerge = mergeProfileJson(
    existing.profile_json,
    sanitized.profilePatch,
    sanitized.shouldUpdate,
  );

  const stateMerge = applyStateUpdate(
    existing.state_json,
    sessionId,
    sanitized.profilePatch.notesAppend,
    sanitized.shouldUpdate,
  );

  if (stateMerge.duplicate) {
    return jsonResponse({
      applied: true,
      reason: "duplicate_session",
      updatedProfile: updatedProfileForResponse(profileMerge.profileJson),
      sessionId,
    });
  }

  const reason = profileMerge.changed || stateMerge.notesChanged ? "updated" : "noop";
  if (reason === "updated") {
    profileMerge.profileJson.schemaVersion = 1;
    profileMerge.profileJson.lastUpdatedBy = "ai";
    profileMerge.profileJson.lastUpdatedAt = new Date().toISOString();
  }

  const upsertPayload = {
    user_id: userId,
    profile_json: profileMerge.profileJson,
    state_json: stateMerge.stateJson,
    patterns_json: existing.patterns_json,
    trust_json: existing.trust_json,
    updated_at: new Date().toISOString(),
  };

  const { error: upsertError } = await supabase
    .from("me_db")
    .upsert(upsertPayload, { onConflict: "user_id" });

  if (upsertError) {
    return jsonResponse({ error: upsertError.message }, 500);
  }

  return jsonResponse({
    applied: true,
    reason,
    updatedProfile: updatedProfileForResponse(profileMerge.profileJson),
    sessionId,
  });
});

function buildUserPrompt(input: {
  profileJson: Record<string, unknown>;
  stateJson: Record<string, unknown>;
  sessionId: string;
  summary: SummaryPayload;
  transcript: string;
}): string {
  return [
    "Current profile JSON:",
    JSON.stringify(input.profileJson),
    "",
    "Current state JSON:",
    JSON.stringify(input.stateJson),
    "",
    "Session:",
    `- session_id: ${input.sessionId}`,
    `- summary_headline: ${input.summary.headline ?? ""}`,
    `- summary_bullets: ${JSON.stringify(input.summary.bullets ?? [])}`,
    "",
    "Transcript:",
    input.transcript,
    "",
    "Return JSON with this shape:",
    JSON.stringify(
      {
        shouldUpdate: true,
        profilePatch: {
          displayName: "string|null",
          tone: "gentle|balanced|direct|null",
          proactivity: "low|medium|high|null",
          avoidTopicsAdd: ["string"],
          avoidTopicsRemove: ["string"],
          notesAppend: "string|null",
        },
      },
      null,
      2,
    ),
  ].join("\n");
}

async function generatePatchWithOpenAI(system: string, user: string): Promise<unknown | null> {
  const response = await fetch(openaiUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openaiApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: openaiModel,
      input: [
        {
          role: "system",
          content: [{ type: "input_text", text: system }],
        },
        {
          role: "user",
          content: [{ type: "input_text", text: user }],
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "profile_patch",
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            required: ["shouldUpdate", "profilePatch"],
            properties: {
              shouldUpdate: { type: "boolean" },
              profilePatch: {
                type: "object",
                additionalProperties: false,
                required: [
                  "displayName",
                  "tone",
                  "proactivity",
                  "avoidTopicsAdd",
                  "avoidTopicsRemove",
                  "notesAppend",
                ],
                properties: {
                  displayName: { type: ["string", "null"] },
                  tone: {
                    type: ["string", "null"],
                    enum: ["gentle", "balanced", "direct", null],
                  },
                  proactivity: {
                    type: ["string", "null"],
                    enum: ["low", "medium", "high", null],
                  },
                  avoidTopicsAdd: {
                    type: "array",
                    items: { type: "string" },
                  },
                  avoidTopicsRemove: {
                    type: "array",
                    items: { type: "string" },
                  },
                  notesAppend: { type: ["string", "null"] },
                },
              },
            },
          },
        },
      },
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error("Profile memory OpenAI call failed", errorText);
    return null;
  }

  const data = await response.json();
  const text = extractOutputText(data);
  if (!text) return null;

  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function extractOutputText(data: Record<string, unknown>): string | null {
  if (typeof data.output_text === "string") {
    return data.output_text;
  }

  const output = data.output;
  if (!Array.isArray(output)) return null;

  for (const item of output) {
    const content = item?.content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (typeof part?.text === "string") {
        return part.text;
      }
    }
  }

  return null;
}

function jsonResponse(payload: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
