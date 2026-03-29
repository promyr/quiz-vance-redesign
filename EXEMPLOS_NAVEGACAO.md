> Documento histórico. A documentação principal e atualizada do projeto está em `README.md`.

# Exemplos de NavegaÃ§Ã£o para as Novas Telas

## Quick Links para Integrar nas Telas Existentes

### 1. Na Home Screen
Para adicionar links para as novas telas no menu principal:

```dart
// BotÃ£o para EstatÃ­sticas
GestureDetector(
  onTap: () => context.go('/stats'),
  child: Container(
    // ... seu card design
    child: const Text('ðŸ“Š EstatÃ­sticas'),
  ),
)

// BotÃ£o para ConfiguraÃ§Ãµes
GestureDetector(
  onTap: () => context.go('/settings'),
  child: Container(
    // ... seu card design
    child: const Text('âš™ï¸ ConfiguraÃ§Ãµes'),
  ),
)

// BotÃ£o para Conquistas (alternativo)
GestureDetector(
  onTap: () => context.go('/conquistas'),
  child: Container(
    // ... seu card design
    child: const Text('ðŸ… Conquistas'),
  ),
)
```

### 2. Na Profile Screen
Para adicionar um link na pÃ¡gina de perfil:

```dart
// BotÃ£o "Ver Todas as Conquistas"
GestureDetector(
  onTap: () => context.go('/conquistas'),
  child: Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('ðŸ… Conquistas'),
        Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textMuted),
      ],
    ),
  ),
)
```

### 3. Na App Bottom Navigation
Se desejar adicionar as novas telas no menu inferior:

```dart
// Adicionar no AppBottomNav (se existir)
items: [
  // ... items existentes
  _NavItem(
    icon: 'ðŸ“Š',
    label: 'Stats',
    onTap: () => context.go('/stats'),
  ),
  _NavItem(
    icon: 'âš™ï¸',
    label: 'Settings',
    onTap: () => context.go('/settings'),
  ),
]
```

### 4. Acessar os Providers em Qualquer Tela

```dart
// Importar em qualquer widget Consumer:
import '../settings/providers/settings_provider.dart';

// Dentro de um ConsumerWidget:
final aiProvider = ref.watch(aiProviderSettingProvider);
final apiKeyGemini = ref.watch(apiKeyGeminiProvider);

// Acessar os dados:
aiProvider.when(
  loading: () => const Text('Carregando...'),
  error: (e, _) => const Text('Erro'),
  data: (provider) => Text('Usando: $provider'),
)
```

### 5. Logout ProgramÃ¡tico

```dart
// Em qualquer tela, fazer logout e ir para login:
Future<void> handleLogout() async {
  await ref.read(authStateNotifierProvider.notifier).logout();
  if (mounted) {
    context.go('/login');
  }
}
```

---

## Fluxo de NavegaÃ§Ã£o Recomendado

```
Home Screen
  â”œâ”€ BotÃ£o Stats â†’ /stats
  â”‚   â”œâ”€ BotÃ£o "Ver Conquistas" â†’ /conquistas
  â”‚   â”‚   â””â”€ BotÃ£o "â† " â†’ volta para /stats
  â”‚   â””â”€ BotÃ£o "â† " â†’ volta para /
  â”‚
  â”œâ”€ BotÃ£o Settings â†’ /settings
  â”‚   â”œâ”€ Salvar configuraÃ§Ãµes (SnackBar)
  â”‚   â”œâ”€ Sair da Conta â†’ /login
  â”‚   â””â”€ BotÃ£o "â† " â†’ volta para /
  â”‚
  â””â”€ BotÃ£o Conquistas â†’ /conquistas
      â””â”€ BotÃ£o "â† " â†’ volta para /
```

---

## Estrutura Completa para Widget Customizado

### Card GenÃ©rico com Link
```dart
class MenuCard extends StatelessWidget {
  const MenuCard({
    required this.emoji,
    required this.title,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn()
        .slideX(begin: 0.05);
  }
}

// Uso:
MenuCard(
  emoji: 'ðŸ“Š',
  title: 'EstatÃ­sticas',
  onTap: () => context.go('/stats'),
)
```

---

## Dados a Passar Entre Telas (Opcional)

Se precisar passar dados via `state.extra`:

```dart
// Enviando dados
context.go('/conquistas', extra: {
  'sourceScreen': 'stats',
  'userId': currentUserId,
});

// Recebendo dados na rota
GoRoute(
  path: '/conquistas',
  builder: (context, state) {
    final extra = state.extra as Map<String, dynamic>?;
    return ConquistasScreen(
      sourceScreen: extra?['sourceScreen'] as String?,
    );
  },
)
```

---

## Teste as Telas Manualmente

```bash
# Para testar diretamente no emulador:
flutter run --target lib/main.dart

# Depois, use o DevTools ou console para navegar:
# context.go('/stats')
# context.go('/conquistas')
# context.go('/settings')
```
> Documento histÃ³rico. A documentaÃ§Ã£o principal e atualizada do projeto estÃ¡ em `README.md`.

