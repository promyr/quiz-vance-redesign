class AiProviderDefinition {
  const AiProviderDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.buyUrl,
    required this.docsUrl,
    required this.storageKey,
    required this.defaultModel,
  });

  final String id;
  final String label;
  final String description;
  final String buyUrl;
  final String docsUrl;
  final String storageKey;
  final String defaultModel;
}

const aiProviderCatalog = <AiProviderDefinition>[
  AiProviderDefinition(
    id: 'groq',
    label: 'Groq (Ultrarrápido)',
    description: 'Provedor mais rápido (respostas em ~0.3s) com Llama 3.3 70B.',
    buyUrl: 'https://console.groq.com/keys',
    docsUrl: 'https://console.groq.com/docs/quickstart',
    storageKey: 'api_key_groq',
    defaultModel: 'llama-3.3-70b-versatile',
  ),
  AiProviderDefinition(
    id: 'gemini',
    label: 'Gemini (Google)',
    description: 'Excelente para explicações detalhadas e quizzes do ENEM.',
    buyUrl: 'https://aistudio.google.com/app/apikey',
    docsUrl: 'https://ai.google.dev/gemini-api/docs/api-key',
    storageKey: 'api_key_gemini',
    defaultModel: 'gemini-3.5-flash',
  ),
  AiProviderDefinition(
    id: 'openai',
    label: 'OpenAI',
    description: 'Modelos GPT para quizzes, explicações e correções.',
    buyUrl: 'https://platform.openai.com/api-keys',
    docsUrl: 'https://platform.openai.com/docs/quickstart',
    storageKey: 'api_key_openai',
    defaultModel: 'gpt-4o-mini',
  ),
];

String defaultModelForAiProvider(String provider) {
  final normalized = provider.trim().toLowerCase();
  for (final candidate in aiProviderCatalog) {
    if (candidate.id == normalized) {
      return candidate.defaultModel;
    }
  }
  return aiProviderCatalog.first.defaultModel;
}
