export interface ChatMessage {
  role: "system" | "user";
  content: string;
}

export interface ChatRequest {
  messages: ChatMessage[];
  temperature?: number;
}

/** Provider-neutral interface to allow the advisor service to be tested without network access. */
export interface LlmClient {
  chat(request: ChatRequest): Promise<string>;
}

export interface OpenAiCompatibleClientOptions {
  apiKey: string;
  baseUrl?: string;
  model?: string;
  timeoutMs?: number;
  fetchFn?: typeof fetch;
}

interface ChatCompletionResponse {
  choices?: Array<{ message?: { content?: string | null } }>;
  error?: { message?: string };
}

/** Minimal client for OpenAI-compatible `/chat/completions` APIs. */
export function createOpenAiCompatibleClient(options: OpenAiCompatibleClientOptions): LlmClient {
  const baseUrl = (options.baseUrl ?? "https://api.openai.com/v1").replace(/\/$/, "");
  const model = options.model ?? "gpt-4o-mini";
  const timeoutMs = options.timeoutMs ?? 12_000;
  const fetchFn = options.fetchFn ?? fetch;

  return {
    async chat(request): Promise<string> {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), timeoutMs);

      try {
        const response = await fetchFn(`${baseUrl}/chat/completions`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${options.apiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model,
            messages: request.messages,
            temperature: request.temperature ?? 0.2,
            response_format: { type: "json_object" },
          }),
          signal: controller.signal,
        });

        const payload = await response.json().catch(() => ({})) as ChatCompletionResponse;
        if (!response.ok) {
          throw new Error(`LLM request failed (${response.status}): ${payload.error?.message ?? "unknown error"}`);
        }

        const content = payload.choices?.[0]?.message?.content;
        if (typeof content !== "string" || content.trim() === "") {
          throw new Error("LLM response did not include message content");
        }
        return content;
      } finally {
        clearTimeout(timeout);
      }
    },
  };
}
