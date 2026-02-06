import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type QuestionKind = "default" | "follow_up" | "new_topic";

type QuestionHistoryItem = {
  text: string;
  coverageTag?: string | null;
  kind?: QuestionKind | null;
  status?: string | null;
};

type ProfilePayload = {
  tone?: string;
  proactivity?: string;
  avoidTopics?: string[];
};

type ResolvedProfileContext = {
  tone: "gentle" | "balanced" | "direct";
  proactivity: "low" | "medium" | "high";
  avoidTopics: string[];
  memoryNotes: string[];
};

type RecentSession = {
  title?: string;
  snippet?: string;
};

type QuestionsRequest = {
  mode: "validate" | "next";
  draftText: string;
  recentText: string;
  lastQuestion?: string;
  questionHistory?: QuestionHistoryItem[];
  profile?: ProfilePayload;
  recentSessions?: RecentSession[];
  preferredKind?: QuestionKind;
};

type QuestionsResponse = {
  answered?: boolean;
  answerConfidence?: number;
  nextQuestion?: {
    text: string;
    coverageTag?: string;
    kind?: QuestionKind;
  } | null;
  reason?: string;
  fallbackUsed?: boolean;
};

const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
const openaiModel = Deno.env.get("OPENAI_QUESTION_MODEL") ?? "gpt-4o-mini";
const openaiUrl = "https://api.openai.com/v1/responses";
const MAX_MEMORY_NOTES = 8;
const MAX_MEMORY_NOTE_CHARS = 220;
const MAX_AVOID_TOPICS = 24;

const fallbackQuestions = [
  { text: "What felt most important today?", coverageTag: "values", kind: "default" },
  { text: "What moment stayed with you the most?", coverageTag: "event", kind: "default" },
  { text: "What felt heavier than you expected?", coverageTag: "emotion", kind: "default" },
  { text: "What gave you a small sense of progress?", coverageTag: "action", kind: "default" },
  { text: "What are you grateful for right now?", coverageTag: "gratitude", kind: "default" },
  { text: "Who influenced your day the most?", coverageTag: "relationships", kind: "default" },
  { text: "What did your body need today?", coverageTag: "health", kind: "default" },
  { text: "What took most of your energy?", coverageTag: "work", kind: "default" },
  { text: "What would you want to remember from today?", coverageTag: "values", kind: "default" },
];

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization") ?? req.headers.get("authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header." }, 401);
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

  if (!openaiApiKey) {
    return jsonResponse({ error: "OPENAI_API_KEY is not set." }, 500);
  }

  let payload: QuestionsRequest;
  try {
    payload = await req.json();
  } catch (error) {
    return jsonResponse({ error: "Invalid JSON payload." }, 400);
  }

  if (!payload.mode || !payload.draftText || !payload.recentText) {
    return jsonResponse({ error: "mode, draftText, and recentText are required." }, 400);
  }

  if (payload.mode === "validate") {
    return handleValidate(payload);
  }

  if (payload.mode === "next") {
    let context: ResolvedProfileContext;
    try {
      context = await resolveProfileContext(supabase, userId, payload.profile ?? {});
    } catch (error) {
      console.error("Failed to resolve me_db context for questions", error);
      context = fallbackProfileContext(payload.profile ?? {});
    }
    return handleNext(payload, context);
  }

  return jsonResponse({ error: "Unsupported mode." }, 400);
});

async function handleValidate(payload: QuestionsRequest): Promise<Response> {
  if (!payload.lastQuestion) {
    return jsonResponse({ error: "lastQuestion is required for validation." }, 400);
  }

  const prompt = buildValidationPrompt(payload.lastQuestion, payload.recentText);
  let responseText: string;
  try {
    responseText = await callOpenAI(prompt);
  } catch {
    const response: QuestionsResponse = {
      answered: false,
      answerConfidence: 0,
      nextQuestion: null,
      reason: "openai_error",
      fallbackUsed: true,
    };
    return jsonResponse(response);
  }
  const parsed = parseValidationResponse(responseText);

  if (!parsed) {
    const response: QuestionsResponse = {
      answered: false,
      answerConfidence: 0,
      nextQuestion: null,
      reason: "parse_failed",
      fallbackUsed: true,
    };
    return jsonResponse(response);
  }

  const response: QuestionsResponse = {
    answered: parsed.answered,
    answerConfidence: parsed.confidence,
    nextQuestion: null,
    reason: parsed.reason,
    fallbackUsed: false,
  };
  return jsonResponse(response);
}

async function handleNext(payload: QuestionsRequest, context: ResolvedProfileContext): Promise<Response> {
  const preferredKind = payload.preferredKind ?? inferPreferredKind(payload.questionHistory ?? []);
  const avoidTopics = context.avoidTopics;

  const prompt = buildQuestionPrompt({
    preferredKind,
    draftText: payload.draftText,
    recentText: payload.recentText,
    lastQuestion: payload.lastQuestion ?? "",
    profile: {
      tone: context.tone,
      proactivity: context.proactivity,
      avoidTopics: context.avoidTopics,
    },
    memoryNotes: context.memoryNotes,
    recentSessions: payload.recentSessions ?? [],
  });

  let responseText: string;
  try {
    responseText = await callOpenAI(prompt);
  } catch {
    const fallback = pickFallbackQuestion(avoidTopics);
    const response: QuestionsResponse = {
      answered: false,
      answerConfidence: 0,
      nextQuestion: fallback,
      reason: "openai_error",
      fallbackUsed: true,
    };
    return jsonResponse(response);
  }
  const sanitized = sanitizeQuestion(responseText, avoidTopics);

  if (!sanitized) {
    const fallback = pickFallbackQuestion(avoidTopics);
    const response: QuestionsResponse = {
      answered: false,
      answerConfidence: 0,
      nextQuestion: fallback,
      reason: "fallback_default",
      fallbackUsed: true,
    };
    return jsonResponse(response);
  }

  const response: QuestionsResponse = {
    answered: false,
    answerConfidence: 0,
    nextQuestion: {
      text: sanitized,
      coverageTag: "auto",
      kind: preferredKind,
    },
    reason: "generated",
    fallbackUsed: false,
  };

  return jsonResponse(response);
}

function buildValidationPrompt(question: string, recentText: string): string {
  return [
    "You are validating whether a user answered a question in a journal transcript.",
    "Return strict JSON with keys: answered (boolean), confidence (0-1), reason (short string).",
    "Answer true only if the recent text clearly answers the question.",
    "Question:",
    question,
    "Recent text:",
    recentText,
  ].join("\n");
}

function buildQuestionPrompt(input: {
  preferredKind: QuestionKind;
  draftText: string;
  recentText: string;
  lastQuestion: string;
  profile: ProfilePayload;
  memoryNotes: string[];
  recentSessions: RecentSession[];
}): string {
  const tone = input.profile.tone ?? "balanced";
  const proactivity = input.profile.proactivity ?? "medium";
  const avoidTopics = (input.profile.avoidTopics ?? []).join(", ");

  const sessionContext = input.recentSessions
    .map((session, index) => {
      const title = session.title?.trim() ?? "";
      const snippet = session.snippet?.trim() ?? "";
      return `- Session ${index + 1}: ${title} ${snippet}`.trim();
    })
    .filter(Boolean)
    .join("\n");

  const kindGuidance = input.preferredKind === "follow_up"
    ? "Ask a follow-up that builds on the user's recent text."
    : input.preferredKind === "new_topic"
      ? "Shift to a different topic than the last question. Do not follow up on it."
      : "Ask a broadly reflective question grounded in the text.";

  const proactivityGuidance = proactivity === "low"
    ? "Be gentle and avoid pushing into sensitive detail."
    : proactivity === "high"
      ? "Be more direct and specific while staying respectful."
      : "Be balanced and supportive.";

  const memoryContext = input.memoryNotes
    .slice(-MAX_MEMORY_NOTES)
    .map((note) => `- ${truncate(note, MAX_MEMORY_NOTE_CHARS)}`)
    .join("\n");

  return [
    "You help users reflect deeper with short, thoughtful questions.",
    "Output ONLY the question in English, under 15 words, ending with '?'",
    "Use profile memory as soft context only. Prioritize the current transcript.",
    `Tone: ${tone}. ${proactivityGuidance}`,
    avoidTopics ? `Topics to avoid: ${avoidTopics}.` : "",
    memoryContext ? `User memory notes:\n${memoryContext}` : "",
    kindGuidance,
    input.lastQuestion ? `Last question: ${input.lastQuestion}` : "",
    "Recent text:",
    truncate(input.recentText, 800),
    "Draft so far:",
    truncate(input.draftText, 1200),
    sessionContext ? `Recent sessions:\n${sessionContext}` : "",
  ].filter(Boolean).join("\n");
}

async function callOpenAI(prompt: string): Promise<string> {
  const response = await fetch(openaiUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openaiApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: openaiModel,
      input: prompt,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI error: ${errorText}`);
  }

  const data = await response.json();
  return extractOutputText(data) ?? "";
}

function extractOutputText(data: any): string | null {
  const outputs = data?.output;
  if (!Array.isArray(outputs)) return null;
  for (const output of outputs) {
    const content = output?.content;
    if (!Array.isArray(content)) continue;
    const textBlock = content.find((item: any) => item?.type === "output_text");
    if (textBlock?.text) {
      return textBlock.text as string;
    }
  }
  return null;
}

function parseValidationResponse(text: string): { answered: boolean; confidence: number; reason: string } | null {
  const json = extractJson(text);
  if (!json) return null;
  if (typeof json.answered !== "boolean") return null;
  const confidence = typeof json.confidence === "number" ? clamp(json.confidence, 0, 1) : 0;
  const reason = typeof json.reason === "string" ? json.reason : "";
  return { answered: json.answered, confidence, reason };
}

function extractJson(text: string): any | null {
  try {
    return JSON.parse(text);
  } catch {
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]);
    } catch {
      return null;
    }
  }
}

function sanitizeQuestion(text: string, avoidTopics: string[]): string | null {
  let cleaned = text.trim();
  if (cleaned.startsWith("\"") && cleaned.endsWith("\"")) {
    cleaned = cleaned.slice(1, -1).trim();
  }
  cleaned = cleaned.split(/\r?\n/)[0] ?? "";
  cleaned = cleaned.replace(/^[\-\*\d\.\s]+/, "").trim();
  if (!cleaned) return null;

  if (!cleaned.endsWith("?")) {
    cleaned = cleaned.replace(/[.!]+$/, "").trim();
    cleaned = `${cleaned}?`;
  }

  const words = cleaned.split(/\s+/).filter(Boolean);
  if (words.length > 15) return null;

  const lowered = cleaned.toLowerCase();
  if (avoidTopics.some((topic) => topic && lowered.includes(topic.toLowerCase()))) {
    return null;
  }

  return cleaned;
}

function pickFallbackQuestion(avoidTopics: string[]): { text: string; coverageTag: string; kind: QuestionKind } {
  const loweredAvoid = avoidTopics.map((topic) => topic.toLowerCase());
  const filtered = fallbackQuestions.filter((question) =>
    !loweredAvoid.some((topic) => question.text.toLowerCase().includes(topic))
  );
  const pool = filtered.length > 0 ? filtered : fallbackQuestions;
  const selected = pool[Math.floor(Math.random() * pool.length)];
  return selected;
}

function inferPreferredKind(history: QuestionHistoryItem[]): QuestionKind {
  if (history.length === 0) return "default";
  const last = history[history.length - 1];
  if (last?.status === "answered") return "follow_up";
  if (last?.status === "ignored") return "new_topic";

  let consecutiveFollowUps = 0;
  for (let i = history.length - 1; i >= 0; i -= 1) {
    if (history[i]?.kind === "follow_up") {
      consecutiveFollowUps += 1;
    } else {
      break;
    }
  }
  if (consecutiveFollowUps >= 2) return "new_topic";

  const lastTwo = history.slice(-2);
  if (lastTwo.length === 2) {
    const [first, second] = lastTwo;
    if (first?.kind && first.kind === second?.kind) {
      return "new_topic";
    }
  }

  return "default";
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function truncate(text: string, maxLength: number): string {
  if (text.length <= maxLength) return text;
  return text.slice(0, maxLength);
}

async function resolveProfileContext(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  requestProfile: ProfilePayload,
): Promise<ResolvedProfileContext> {
  const { data, error } = await supabase
    .from("me_db")
    .select("profile_json, state_json")
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  const profileJson = asObject(data?.profile_json);
  const stateJson = asObject(data?.state_json);

  const tone = readTone(profileJson.tone) ?? readTone(requestProfile.tone) ?? "balanced";
  const proactivity = readProactivity(profileJson.proactivity) ?? readProactivity(requestProfile.proactivity) ?? "medium";
  const mergedTopics = dedupe([
    ...readAvoidTopics(profileJson.avoidTopics),
    ...sanitizeTopicList(requestProfile.avoidTopics),
  ]).slice(0, MAX_AVOID_TOPICS);
  const memoryNotes = readMemoryNotes(stateJson.memory_notes);

  return {
    tone,
    proactivity,
    avoidTopics: mergedTopics,
    memoryNotes,
  };
}

function fallbackProfileContext(requestProfile: ProfilePayload): ResolvedProfileContext {
  return {
    tone: readTone(requestProfile.tone) ?? "balanced",
    proactivity: readProactivity(requestProfile.proactivity) ?? "medium",
    avoidTopics: sanitizeTopicList(requestProfile.avoidTopics).slice(0, MAX_AVOID_TOPICS),
    memoryNotes: [],
  };
}

function readTone(value: unknown): "gentle" | "balanced" | "direct" | null {
  if (value === "gentle" || value === "balanced" || value === "direct") return value;
  return null;
}

function readProactivity(value: unknown): "low" | "medium" | "high" | null {
  if (value === "low" || value === "medium" || value === "high") return value;
  return null;
}

function readAvoidTopics(value: unknown): string[] {
  if (typeof value === "string") {
    return sanitizeTopicList(value.split(","));
  }
  return sanitizeTopicList(value);
}

function readMemoryNotes(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => typeof item === "string" ? item.trim().replace(/\s+/g, " ") : "")
    .filter((item) => item.length > 0)
    .slice(-MAX_MEMORY_NOTES)
    .map((item) => truncate(item, MAX_MEMORY_NOTE_CHARS));
}

function sanitizeTopicList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const topics = value
    .map((item) => typeof item === "string" ? item : "")
    .map((item) => item.trim().toLowerCase().replace(/\s+/g, " "))
    .filter((item) => item.length > 0 && item.split(" ").length <= 4);
  return dedupe(topics);
}

function dedupe(items: string[]): string[] {
  return [...new Set(items)];
}

function asObject(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
