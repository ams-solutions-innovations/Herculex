export class GeminiFailure extends Error {
  code;
  status;
  retryable;
  retryAfterSeconds;
  constructor(code, message, status = 503, retryable = false, retryAfterSeconds){
    super(message);
    this.code = code;
    this.status = status;
    this.retryable = retryable;
    this.retryAfterSeconds = retryAfterSeconds;
    this.name = "GeminiFailure";
  }
}
/** One shared budget also bounds grounded -> structured fallback calls. */ export class GenerationBudget {
  kind;
  requestId;
  now;
  attempts;
  startedAt;
  deadline;
  constructor(kind = "unknown", requestId = crypto.randomUUID(), now = Date.now, timeoutMs = 70_000){
    this.kind = kind;
    this.requestId = requestId;
    this.now = now;
    this.attempts = 0;
    this.startedAt = now();
    this.deadline = this.startedAt + timeoutMs;
  }
  remaining() {
    return this.deadline - this.now();
  }
}
function transportFailure(error) {
  if (error instanceof GeminiFailure) return error;
  if (error instanceof DOMException && [
    "TimeoutError",
    "AbortError"
  ].includes(error.name)) {
    return new GeminiFailure("timeout", "Herculex AI took too long. Your input is kept; please try again.", 504, true);
  }
  return new GeminiFailure("unavailable", "Herculex AI could not connect. Please try again shortly.", 503, true);
}
export async function requestGemini({ primaryModel, fallbackModel, bodyForModel, apiKey, budget = new GenerationBudget(), fetcher = fetch, wait = (ms)=>new Promise((resolve)=>setTimeout(resolve, ms)) }) {
  let failure = new GeminiFailure("timeout", "Herculex AI took too long. Please try again.", 504, true);
  while(budget.attempts < 2 && budget.remaining() > 0){
    const model = budget.attempts === 0 ? primaryModel : fallbackModel || primaryModel;
    const attempt = ++budget.attempts;
    const started = budget.now();
    let status;
    try {
      const response = await fetcher(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiKey
        },
        body: bodyForModel(model),
        signal: AbortSignal.timeout(Math.max(1, Math.min(attempt === 1 ? 45_000 : 20_000, budget.remaining())))
      });
      status = response.status;
      if (!response.ok) {
        const retryable = [
          408,
          429,
          500,
          502,
          503,
          504
        ].includes(response.status);
        const retryHeader = response.headers.get("retry-after");
        const seconds = retryHeader == null ? NaN : Number(retryHeader);
        const dateSeconds = retryHeader == null ? NaN : (Date.parse(retryHeader) - budget.now()) / 1000;
        const retryAfter = Number.isFinite(seconds) ? Math.max(0, seconds) : Number.isFinite(dateSeconds) ? Math.max(0, dateSeconds) : undefined;
        await response.body?.cancel();
        if ([
          401,
          403,
          404
        ].includes(response.status)) {
          throw new GeminiFailure("configuration", "Herculex AI is temporarily unavailable. Please try again later.");
        }
        if (response.status === 429) {
          throw new GeminiFailure("provider_quota", "Herculex AI is currently at capacity. Your input is kept; please try again later.", 503, true, retryAfter);
        }
        throw new GeminiFailure(retryable ? "unavailable" : "invalid_input", retryable ? "Herculex AI is busy. Your input is kept; please try again shortly." : "Herculex AI could not process this input. Please check it and try again.", retryable ? 503 : 400, retryable, retryAfter);
      }
      let root;
      try {
        root = await response.json();
      } catch (error) {
        if (error instanceof DOMException) throw error;
        throw new GeminiFailure("invalid_response", "Herculex AI returned an incomplete response. Please try again.", 502, true);
      }
      if (!root || typeof root !== "object" || Array.isArray(root)) {
        throw new GeminiFailure("invalid_response", "Herculex AI returned an incomplete response. Please try again.", 502, true);
      }
      console.log("gemini attempt", {
        requestId: budget.requestId,
        kind: budget.kind,
        model,
        attempt,
        status,
        durationMs: budget.now() - started,
        outcome: "success"
      });
      return {
        root: root,
        modelVersion: model
      };
    } catch (error) {
      failure = transportFailure(error);
      console.warn("gemini attempt", {
        requestId: budget.requestId,
        kind: budget.kind,
        model,
        attempt,
        status,
        durationMs: budget.now() - started,
        outcome: failure.code
      });
      if (!failure.retryable || failure.code === "invalid_response" || budget.attempts >= 2) throw failure;
      const delay = failure.retryAfterSeconds == null ? 500 + Math.floor(Math.random() * 500) : Math.ceil(failure.retryAfterSeconds * 1000);
      if (delay >= budget.remaining()) throw failure;
      await wait(delay);
    }
  }
  throw failure;
}
