class AiProviderDefinition {
  const AiProviderDefinition({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

const defaultAiProviderId = 'gemini';

const aiProviderCatalog = <AiProviderDefinition>[
  AiProviderDefinition(
    id: 'gemini',
    label: 'Gemini (Google)',
    description: 'Explicacoes detalhadas e quizzes com Gemini 3.8 Flash.',
  ),
  AiProviderDefinition(
    id: 'groq',
    label: 'Groq (Ultrarrápido)',
    description: 'Respostas rapidas com Llama 3.3 70B e Llama 3.1 8B.',
  ),
];

String normalizeAiProviderId(String provider) {
  final normalized = provider.trim().toLowerCase();
  return aiProviderCatalog.any((candidate) => candidate.id == normalized)
      ? normalized
      : defaultAiProviderId;
}
