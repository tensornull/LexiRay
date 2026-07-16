export const initialProviders = [
  {
    id: "system-dictionary",
    kind: "System Dictionary",
    name: "System Dictionary",
    enabled: true,
    builtIn: true,
  },
];

export const providerCatalog = [
  {
    kind: "OpenAI Responses",
    name: "OpenAI Responses",
    icon: "/assets/provider-openai.svg",
    model: "gpt-5.5",
    baseURL: "https://api.cometapi.com/v1",
  },
  {
    kind: "OpenAI Chat Completions",
    name: "OpenAI Chat",
    icon: "/assets/provider-openai.svg",
    model: "gpt-4.1",
    baseURL: "https://api.openai.com/v1",
  },
  {
    kind: "Anthropic Messages",
    name: "Anthropic",
    icon: "/assets/provider-anthropic.svg",
    model: "claude-sonnet-4-5",
    baseURL: "https://api.anthropic.com",
  },
  {
    kind: "Gemini GenerateContent",
    name: "Gemini",
    icon: "/assets/provider-gemini.svg",
    model: "gemini-2.5-flash",
    baseURL: "https://generativelanguage.googleapis.com",
  },
];

export const historyItems = [
  {
    source: "LexiRay seeded history text.",
    result: "Seeded history result.",
    sourceLanguage: "Auto: English",
    targetLanguage: "Auto: Simplified Chinese",
  },
  {
    source: "A calm interface should make complex work feel immediate.",
    result: "沉静的界面，应让复杂的工作也显得即时而轻松。",
    sourceLanguage: "Auto: English",
    targetLanguage: "Auto: Simplified Chinese",
  },
];

export function mockTranslation(source) {
  const normalized = source.trim().toLowerCase();
  if (normalized.includes("calm interface")) {
    return "沉静的界面，应让复杂的工作也显得即时而轻松。";
  }
  if (normalized.includes("selected text")) {
    return "这是从另一个应用中捕获的所选文本。";
  }
  if (normalized.includes("ocr")) {
    return "OCR 区域中的文字已被识别并翻译。";
  }
  if (normalized.includes("lexiray")) {
    return "LexiRay 会将选择、输入或屏幕区域中的文字快速翻译。";
  }
  return "这是当前原型生成的模拟翻译结果，用于还原 LexiRay 的真实产品交互。";
}
