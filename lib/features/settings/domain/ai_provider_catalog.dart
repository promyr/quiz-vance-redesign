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
    id: 'gemini',
    label: 'Gemini',
    description: 'Mais economico para quizzes e geracao geral.',
    buyUrl: 'https://aistudio.google.com/app/apikey',
    docsUrl: 'https://ai.google.dev/gemini-api/docs/api-key',
    storageKey: 'api_key_gemini',
    defaultModel: 'gemini-2.0-flash',
  ),
  AiProviderDefinition(
    id: 'openai',
    label: 'OpenAI',
    description: 'Melhor opção para qualidade e dissertativas.',
    buyUrl: 'https://platform.openai.com/api-keys',
    docsUrl: 'https://platform.openai.com/docs/quickstart',
    storageKey: 'api_key_openai',
    defaultModel: 'gpt-4o-mini',
  ),
  AiProviderDefinition(
    id: 'groq',
    label: 'Groq',
    description: 'Muito rapido para estudo e respostas curtas.',
    buyUrl: 'https://console.groq.com/keys',
    docsUrl: 'https://console.groq.com/docs/quickstart',
    storageKey: 'api_key_groq',
    defaultModel: 'llama-3.3-70b-versatile',
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
