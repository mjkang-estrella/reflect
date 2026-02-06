export type JsonObject = Record<string, unknown>;

export type Tone = "gentle" | "balanced" | "direct";
export type Proactivity = "low" | "medium" | "high";

export type RawModelResponse = {
  shouldUpdate?: unknown;
  profilePatch?: {
    displayName?: unknown;
    tone?: unknown;
    proactivity?: unknown;
    avoidTopicsAdd?: unknown;
    avoidTopicsRemove?: unknown;
    notesAppend?: unknown;
  } | null;
};

export type SanitizedModelResponse = {
  shouldUpdate: boolean;
  profilePatch: {
    displayName: string | null;
    tone: Tone | null;
    proactivity: Proactivity | null;
    avoidTopicsAdd: string[];
    avoidTopicsRemove: string[];
    notesAppend: string | null;
  };
};

const ALLOWED_TONES = new Set<Tone>(["gentle", "balanced", "direct"]);
const ALLOWED_PROACTIVITY = new Set<Proactivity>(["low", "medium", "high"]);
const TOPIC_MAX_WORDS = 4;
const TOPIC_MAX_ITEMS = 24;
const DISPLAY_NAME_MAX_CHARS = 80;
const NOTES_MAX_CHARS = 220;
const MEMORY_NOTES_MAX_ITEMS = 50;

export function sanitizeModelResponse(input: unknown): SanitizedModelResponse {
  const payload = asObject(input);
  const patch = asObject(payload.profilePatch);

  const displayName = sanitizeDisplayName(patch.displayName);
  const tone = sanitizeTone(patch.tone);
  const proactivity = sanitizeProactivity(patch.proactivity);
  const avoidTopicsAdd = sanitizeTopicList(patch.avoidTopicsAdd);
  const avoidTopicsRemove = sanitizeTopicList(patch.avoidTopicsRemove);
  const notesAppend = sanitizeNotes(patch.notesAppend);

  return {
    shouldUpdate: payload.shouldUpdate === true,
    profilePatch: {
      displayName,
      tone,
      proactivity,
      avoidTopicsAdd,
      avoidTopicsRemove,
      notesAppend,
    },
  };
}

export function isDuplicateSession(stateJson: unknown, sessionId: string): boolean {
  const state = asObject(stateJson);
  return typeof state.last_profile_memory_session_id === "string" &&
    state.last_profile_memory_session_id === sessionId;
}

export function mergeProfileJson(
  profileJson: unknown,
  patch: SanitizedModelResponse["profilePatch"],
  shouldUpdate: boolean,
): { profileJson: JsonObject; changed: boolean } {
  const current = withProfileDefaults(profileJson);
  const merged: JsonObject = { ...current };
  let changed = false;

  if (!shouldUpdate) {
    return { profileJson: merged, changed: false };
  }

  if (patch.displayName !== null && patch.displayName !== readString(current.displayName)) {
    merged.displayName = patch.displayName;
    changed = true;
  }

  if (patch.tone !== null && patch.tone !== readTone(current.tone)) {
    merged.tone = patch.tone;
    changed = true;
  }

  if (patch.proactivity !== null && patch.proactivity !== readProactivity(current.proactivity)) {
    merged.proactivity = patch.proactivity;
    changed = true;
  }

  const existingTopics = parseAvoidTopics(readString(current.avoidTopics));
  const topicSet = new Set(existingTopics);
  for (const topic of patch.avoidTopicsRemove) {
    topicSet.delete(topic);
  }
  for (const topic of patch.avoidTopicsAdd) {
    topicSet.add(topic);
  }
  const mergedTopics = Array.from(topicSet).slice(0, TOPIC_MAX_ITEMS);
  const mergedTopicValue = mergedTopics.join(",");
  if (mergedTopicValue !== readString(current.avoidTopics)) {
    merged.avoidTopics = mergedTopicValue;
    changed = true;
  }

  return { profileJson: merged, changed };
}

export function applyStateUpdate(
  stateJson: unknown,
  sessionId: string,
  notesAppend: string | null,
  shouldUpdate: boolean,
): { stateJson: JsonObject; changed: boolean; duplicate: boolean; notesChanged: boolean } {
  const current = asObject(stateJson);
  if (isDuplicateSession(current, sessionId)) {
    return { stateJson: current, changed: false, duplicate: true, notesChanged: false };
  }

  const merged: JsonObject = { ...current };
  let notesChanged = false;

  if (shouldUpdate && notesAppend !== null) {
    const existing = Array.isArray(current.memory_notes) ? current.memory_notes : [];
    const normalized = existing
      .map((item) => typeof item === "string" ? item.trim() : "")
      .filter((item) => item.length > 0);
    normalized.push(notesAppend);
    merged.memory_notes = normalized.slice(-MEMORY_NOTES_MAX_ITEMS);
    notesChanged = true;
  }

  merged.last_profile_memory_session_id = sessionId;
  return { stateJson: merged, changed: true, duplicate: false, notesChanged };
}

export function updatedProfileForResponse(profileJson: unknown): {
  displayName: string;
  tone: Tone;
  proactivity: Proactivity;
  avoidTopics: string;
} {
  const profile = asObject(profileJson);
  return {
    displayName: readString(profile.displayName),
    tone: readTone(profile.tone),
    proactivity: readProactivity(profile.proactivity),
    avoidTopics: readString(profile.avoidTopics),
  };
}

export function withProfileDefaults(profileJson: unknown): JsonObject {
  const current = asObject(profileJson);
  return {
    schemaVersion: 1,
    name: "",
    displayName: "",
    pronouns: "",
    timezone: "UTC",
    tone: "balanced",
    proactivity: "medium",
    avoidTopics: "",
    notes: "",
    lastUpdatedBy: "user",
    lastUpdatedAt: "",
    ...current,
  };
}

export function parseAvoidTopics(raw: string): string[] {
  return raw
    .split(",")
    .map((item) => normalizeTopic(item))
    .filter((item): item is string => item !== null);
}

function sanitizeDisplayName(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().replace(/\s+/g, " ");
  if (!trimmed) return null;
  return trimmed.slice(0, DISPLAY_NAME_MAX_CHARS);
}

function sanitizeTone(value: unknown): Tone | null {
  if (typeof value !== "string") return null;
  return ALLOWED_TONES.has(value as Tone) ? value as Tone : null;
}

function sanitizeProactivity(value: unknown): Proactivity | null {
  if (typeof value !== "string") return null;
  return ALLOWED_PROACTIVITY.has(value as Proactivity) ? value as Proactivity : null;
}

function sanitizeNotes(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().replace(/\s+/g, " ");
  if (!trimmed) return null;
  return trimmed.slice(0, NOTES_MAX_CHARS);
}

function sanitizeTopicList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const normalized: string[] = [];
  const seen = new Set<string>();
  for (const item of value) {
    const topic = normalizeTopic(item);
    if (!topic || seen.has(topic)) continue;
    seen.add(topic);
    normalized.push(topic);
    if (normalized.length >= TOPIC_MAX_ITEMS) break;
  }
  return normalized;
}

function normalizeTopic(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.trim().toLowerCase().replace(/\s+/g, " ");
  if (!cleaned) return null;
  if (cleaned.split(" ").length > TOPIC_MAX_WORDS) return null;
  return cleaned;
}

function readString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function readTone(value: unknown): Tone {
  return typeof value === "string" && ALLOWED_TONES.has(value as Tone)
    ? value as Tone
    : "balanced";
}

function readProactivity(value: unknown): Proactivity {
  return typeof value === "string" && ALLOWED_PROACTIVITY.has(value as Proactivity)
    ? value as Proactivity
    : "medium";
}

function asObject(value: unknown): JsonObject {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as JsonObject;
  }
  return {};
}
