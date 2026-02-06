import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  applyStateUpdate,
  mergeProfileJson,
  sanitizeModelResponse,
  updatedProfileForResponse,
  withProfileDefaults,
} from "./core.ts";

Deno.test("sanitize and merge applies valid patch into empty profile", () => {
  const sanitized = sanitizeModelResponse({
    shouldUpdate: true,
    profilePatch: {
      displayName: "Mina",
      tone: "gentle",
      proactivity: "high",
      avoidTopicsAdd: ["work", "family"],
      avoidTopicsRemove: [],
      notesAppend: "Wants a calmer tone around work topics.",
    },
  });

  const merged = mergeProfileJson({}, sanitized.profilePatch, sanitized.shouldUpdate);
  assertEquals(merged.profileJson.displayName, "Mina");
  assertEquals(merged.profileJson.tone, "gentle");
  assertEquals(merged.profileJson.proactivity, "high");
  assertEquals(merged.profileJson.avoidTopics, "work,family");
});

Deno.test("invalid enums are ignored", () => {
  const sanitized = sanitizeModelResponse({
    shouldUpdate: true,
    profilePatch: {
      displayName: "  ",
      tone: "aggressive",
      proactivity: "super-high",
      avoidTopicsAdd: [],
      avoidTopicsRemove: [],
      notesAppend: null,
    },
  });

  const merged = mergeProfileJson(
    { displayName: "Ari", tone: "balanced", proactivity: "medium", avoidTopics: "health" },
    sanitized.profilePatch,
    sanitized.shouldUpdate,
  );

  assertEquals(merged.profileJson.displayName, "Ari");
  assertEquals(merged.profileJson.tone, "balanced");
  assertEquals(merged.profileJson.proactivity, "medium");
  assertEquals(merged.profileJson.avoidTopics, "health");
});

Deno.test("topic add/remove merge stays normalized and deduplicated", () => {
  const sanitized = sanitizeModelResponse({
    shouldUpdate: true,
    profilePatch: {
      displayName: null,
      tone: null,
      proactivity: null,
      avoidTopicsAdd: ["work", "friends", "friends", "too many words here now"],
      avoidTopicsRemove: ["health"],
      notesAppend: null,
    },
  });

  const merged = mergeProfileJson(
    { avoidTopics: "work,health" },
    sanitized.profilePatch,
    sanitized.shouldUpdate,
  );

  assertEquals(merged.profileJson.avoidTopics, "work,friends");
});

Deno.test("notes append is truncated to max length", () => {
  const longNote = "x".repeat(400);
  const sanitized = sanitizeModelResponse({
    shouldUpdate: true,
    profilePatch: {
      displayName: null,
      tone: null,
      proactivity: null,
      avoidTopicsAdd: [],
      avoidTopicsRemove: [],
      notesAppend: longNote,
    },
  });

  assert(sanitized.profilePatch.notesAppend !== null);
  assertEquals(sanitized.profilePatch.notesAppend?.length, 220);
});

Deno.test("duplicate session returns duplicate without appending notes", () => {
  const state = {
    last_profile_memory_session_id: "session-1",
    memory_notes: ["first"],
  };

  const result = applyStateUpdate(state, "session-1", "new note", true);
  assertEquals(result.duplicate, true);
  assertEquals(result.changed, false);
  assertEquals(result.notesChanged, false);
  assertEquals((result.stateJson.memory_notes as string[]).length, 1);
});

Deno.test("updatedProfileForResponse provides defaults", () => {
  const response = updatedProfileForResponse({ displayName: "", avoidTopics: "" });
  assertEquals(response.tone, "balanced");
  assertEquals(response.proactivity, "medium");
  assertEquals(response.avoidTopics, "");
});

Deno.test("withProfileDefaults fills missing canonical fields", () => {
  const profile = withProfileDefaults({});
  assertEquals(profile.schemaVersion, 1);
  assertEquals(profile.displayName, "");
  assertEquals(profile.tone, "balanced");
  assertEquals(profile.proactivity, "medium");
  assertEquals(profile.lastUpdatedBy, "user");
});
