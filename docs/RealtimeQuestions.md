# Real-Time Reflective Questions (OpenAI API Implementation Guide)

This document is self-contained and explains how to implement real-time reflective questions in an audio‑journaling style application using the OpenAI API (not Apple Foundation Models).

## Goal
While a user is recording a voice journal, the app should periodically show a short, thoughtful follow-up question that encourages deeper reflection. The question should:
- Be short (<= 15 words).
- Be a single question ending with `?`.
- Arrive quickly enough to feel “real-time”.
- Fall back to a curated prompt set if AI is unavailable or fails.

## Architecture Overview
Use a small, focused set of components. Names are illustrative; adapt to your stack.

1. **Recorder**
   - Captures audio and exposes real-time audio levels (RMS/peak).
2. **Transcriber**
   - Produces incremental text segments with timestamps.
3. **Nudge Engine**
   - Decides when to trigger a question.
4. **Context Providers (optional)**
   - Calendar events, tasks, recent messages, etc.
5. **Question Generator**
   - Calls OpenAI to generate a short reflective question.
6. **UI Overlay**
   - Shows the question briefly, supports manual dismiss, and auto-dismisses.

## Data Flow (High-Level)
1. User starts recording.
2. Recorder emits audio buffers and audio level samples.
3. Transcriber produces text segments in near real-time.
4. Nudge Engine watches transcription + audio levels and decides when to ask.
5. Question Generator calls OpenAI and returns a single question.
6. UI overlay displays the question and auto-dismisses after a few seconds.

## Trigger Logic (When to Ask)
Use conservative, predictable gating so the user is not interrupted too often.

**Suggested defaults**
- `minStartDelay`: 10s after recording starts (avoid early interruptions).
- `minimumInterval`: based on frequency setting  
  - Minimal: 60s  
  - Moderate: 30s  
  - Frequent: 20s
- `silenceThreshold`: 4.5s of silence before triggering.

**Triggers**
1. **Silence trigger**  
   If audio level stays below a voice threshold for `silenceThreshold`, trigger.
2. **Sentence boundary trigger**  
   If the most recent transcription segment ends with `.`, `?`, or `!` and has at least 4 words, trigger (but only once per unique sentence).

**Guards**
- Do not trigger if already generating a question.
- Do not trigger if a question is already displayed.
- Do not trigger before `minStartDelay`.
- Do not trigger more frequently than `minimumInterval`.

## Context Collection (Optional)
Before generating a question, optionally fetch lightweight context:
- Calendar summaries (today’s event titles or next 1–3 events).
- Task list headlines.
- Recent email subject lines (if permitted).

Keep it short (1–5 items per source). If no context is available, use only the user’s transcription.

## OpenAI Integration
There are two practical patterns. Choose one based on your latency, platform, and privacy needs.

### Pattern A: Realtime API for transcription + events
Use the **Realtime API** for low-latency audio streaming and text output.
- Realtime supports WebRTC for client connections and WebSocket for server connections. citeturn2search1turn2search0
- Models like `gpt-realtime` are listed for real-time text/audio inputs and outputs. citeturn7view0

**When to use**: You need the lowest possible latency, live transcription, or speech‑to‑speech experiences.

### Pattern B: Separate transcription + Responses API
1. Use the **Realtime API in transcription-only mode** or a streaming transcription approach. citeturn2search2
2. Feed the latest transcription snapshot into the **Responses API** for question generation.

**Why this works well**: You can decouple transcription from question generation and throttle question requests independently.

The Responses API is the primary text generation endpoint (`POST /v1/responses`). citeturn4view0

## API Key Safety (Required)
- Do **not** embed your OpenAI API key in client apps. Route requests through your backend. citeturn5search0
- Use `OPENAI_API_KEY` as an environment variable on your server. citeturn5search0

For browser or mobile Realtime connections, use ephemeral client secrets rather than your main key. citeturn2search0

## Prompting Strategy
Use short, strict instructions plus a single “question-only” prompt.

**Instruction**
```
You help users reflect deeper with short, thoughtful follow-up questions.
```

**Prompt template**
```
Based on this journal entry so far: [TRANSCRIPTION]. 
Suggest one short, thoughtful follow-up question (under 15 words) to help the user reflect deeper. 
Only output the question, nothing else.
```

If you have additional context (calendar, tasks, etc.), prepend it in a short sentence:
```
The user had these events today: [EVENTS]. 
Important items today: [ITEMS]. 
```

### Output validation
Always validate on your server before showing the question:
- Trim whitespace.
- Remove surrounding quotes.
- Truncate at the first newline.
- Ensure it ends with `?`.
- Enforce `<= 15` words.
If validation fails, fall back to a static prompt list.

### Structured output (optional)
If you want extra reliability, use Structured Outputs from the Responses API and validate JSON rather than raw text. citeturn5search4

## Streaming Responses (Optional)
If you want the question to appear faster, stream the response and show it once a full sentence is ready. The Responses API supports streaming with `stream=true`. citeturn3search0turn4view0

## Fallback Prompt Sets
Maintain small, curated prompt lists as a safety net. Rotate categories to avoid repetition.

**Suggested categories**
- Emotional: “How did that make you feel?”
- Exploratory: “What led up to this moment?”
- Gratitude: “What is something positive from today?”
- Generic: “What feels most important about today?”

If there is not enough transcription context, force the **generic** category.

## UI Behavior
- Display the question in a lightweight overlay.
- Auto‑dismiss after ~9 seconds.
- Allow tap-to-dismiss.
- Avoid showing more than one question at a time.

## Pseudocode (Implementation Sketch)
```pseudo
onRecordingStart():
  sessionActive = true
  resetNudgeState()
  prefetchContextIfEnabled()

onTranscriptionUpdate(text, segments, now):
  if !shouldProcessUpdates(): return
  updateLastContextSnapshot(text)
  updateLastSpeechTime(segments)
  if silenceTrigger(now) or sentenceTrigger(segments):
    triggerNudge(now)

triggerNudge(now):
  if !canTrigger(now): return
  isThinking = true
  context = collectContextSnapshot()
  question = generateQuestionOpenAI(context)
  if question invalid: question = fallbackPrompt()
  showQuestion(question)

generateQuestionOpenAI(context):
  buildPrompt(context)
  call OpenAI Responses API
  sanitize + validate
  return question
```

## Recommended OpenAI Endpoints
- **Realtime**: low-latency audio/text streaming for live transcription or speech pipelines. citeturn2search1turn2search0turn2search2
- **Responses API**: general text generation for questions (`POST /v1/responses`). citeturn4view0

## Model Selection (Examples)
Pick the best model for your latency/cost needs from the OpenAI models list. citeturn7view0  
For real-time audio use, models like `gpt-realtime` are listed for streaming inputs and outputs. citeturn7view0  
For high-accuracy transcription (batch or streaming), models like `gpt-4o-transcribe` are available. citeturn3search1

## Metrics to Track
- Average time to first question.
- Questions per minute (avoid over‑nudge).
- Fallback rate (AI failures or invalid outputs).
- User dismiss rate.
- Retention impact.

## Summary
This design balances responsiveness with user comfort:
- Use transcription + silence/sentence triggers to time nudges.
- Generate questions via OpenAI with strict output rules.
- Fall back to curated prompts when needed.
- Keep API keys server‑side and use ephemeral tokens for client Realtime sessions. citeturn5search0turn2search0
