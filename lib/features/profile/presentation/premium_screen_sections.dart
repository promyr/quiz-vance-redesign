part of 'premium_screen.dart';

class _PremiumLoadedView extends ConsumerWidget {
  const _PremiumLoadedView({
    required this.entryMode,
    required this.status,
    required this.plans,
    required this.startingCheckout,
    required this.onRefresh,
    required this.onCheckout,
    required this.formatDate,
    required this.findCurrentPlan,
  });

  final PremiumEntryMode entryMode;
  final BillingStatus status;
  final List<BillingPlan> plans;
  final bool startingCheckout;
  final Future<void> Function() onRefresh;
  final Future<void> Function(BillingPlan plan) onCheckout;
  final String? Function(String? iso) formatDate;
  final BillingPlan? Function(List<BillingPlan> plans, BillingStatus status)
      findCurrentPlan;

  bool get _isManageMode => entryMode == PremiumEntryMode.manage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateNotifierProvider).valueOrNull;
    final isAdmin = authState?.isAdmin == true;
    final effectiveIsPremium = isAdmin || status.isPremium;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding =
        screenWidth > 936 ? (screenWidth - 900) / 2 : 18.0;
    final currentPlan = findCurrentPlan(plans, status);
    final orderedPlans = orderBillingPlans(
      plans: plans,
      status: status,
      entryMode: entryMode,
    );
    final displayedPlans = visibleBillingPlans(
      orderedPlans: orderedPlans,
      status: status,
      entryMode: entryMode,
    );
    final hero = buildPremiumHeroContent(
      entryMode: entryMode,
      status: status,
      currentPlan: currentPlan,
      formattedPremiumUntil: formatDate(status.premiumUntil),
      isAdmin: isAdmin,
    );

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          8,
          horizontalPadding,
          24,
        ),
        children: _isManageMode
            ? [
                _PremiumHero(
                  content: hero,
                  premiumUntil:
                      isAdmin ? null : formatDate(status.premiumUntil),
                ),
                const SizedBox(height: 18),
                _ManageStatusCard(
                  currentPlanName: currentPlan?.name ??
                      (effectiveIsPremium ? 'Premium' : 'Plano grátis'),
                  isPremium: effectiveIsPremium,
                  premiumUntil: formatDate(status.premiumUntil),
                  isAdmin: isAdmin,
                ),
                const SizedBox(height: 14),
                _RefreshButton(onRefresh: onRefresh),
                const SizedBox(height: 20),
                Text(
                  effectiveIsPremium ? 'Sua assinatura' : 'Seja Premium',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  effectiveIsPremium
                      ? 'Gerencie seus benefícios e veja todas as novidades disponíveis para você.'
                      : 'Estude sem limites com inteligência artificial por apenas R\$ 14,90 por mês.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                _ModeSwitchCard(
                  title: effectiveIsPremium
                      ? 'Ver benefícios do plano'
                      : 'Assinar por R\$ 14,90/mês',
                  subtitle: effectiveIsPremium
                      ? 'Conheça tudo o que está incluído na sua assinatura.'
                      : 'Desbloqueie quizzes ilimitados, simulados do ENEM e correção de respostas abertas.',
                  buttonLabel: effectiveIsPremium
                      ? 'Conhecer Benefícios'
                      : 'Quero ser Premium (R\$ 14,90)',
                  onTap: () => context
                      .push(premiumRouteForEntry(PremiumEntryMode.subscribe)),
                ),
              ]
            : [
                _PremiumHero(
                  content: hero,
                  premiumUntil:
                      isAdmin ? null : formatDate(status.premiumUntil),
                ),
                const SizedBox(height: 18),
                const _SubscribeBenefitsCard(),
                const SizedBox(height: 20),
                Text(
                  status.isPremium ? 'Detalhes do plano' : 'Escolha seu plano',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  status.isPremium
                      ? 'Confira os detalhes do seu plano ativo abaixo.'
                      : 'Escolha a opção ideal para acelerar seus estudos.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                for (final plan in displayedPlans) ...[
                  _BillingPlanCard(
                    plan: plan,
                    status: status,
                    startingCheckout: startingCheckout,
                    onCheckout: onCheckout,
                  ),
                  const SizedBox(height: 14),
                ],
                _CompactCurrentPlan(
                  currentPlanName: currentPlan?.name ??
                      (status.isPremium ? 'Premium' : 'Plano grátis'),
                  premiumUntil: formatDate(status.premiumUntil),
                  isPremium: status.isPremium,
                ),
                const SizedBox(height: 14),
                _RefreshButton(onRefresh: onRefresh),
              ],
      ),
    );
  }
}

class _PremiumHero extends StatelessWidget {
  const _PremiumHero({
    required this.content,
    required this.premiumUntil,
  });

  final PremiumHeroContent content;
  final String? premiumUntil;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: content.gradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              content.badgeLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            content.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content.subtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          if (premiumUntil != null) ...[
            const SizedBox(height: 12),
            Text(
              'Valido ate $premiumUntil',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ManageStatusCard extends StatelessWidget {
  const _ManageStatusCard({
    required this.currentPlanName,
    required this.isPremium,
    required this.premiumUntil,
    this.isAdmin = false,
  });

  final String currentPlanName;
  final bool isPremium;
  final String? premiumUntil;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final titleName = isAdmin ? 'Administrador Geral' : currentPlanName;
    final statusBadgeLabel = isAdmin
        ? 'ADM Ilimitado'
        : (isPremium ? 'Premium ativo' : 'Plano grátis');
    final statusColor = isAdmin
        ? AppColors.xpGold
        : (isPremium ? AppColors.primary : AppColors.textMuted);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isAdmin ? AppColors.xpGold.withOpacity(0.5) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isAdmin
                    ? Icons.admin_panel_settings_rounded
                    : (isPremium
                        ? Icons.verified_rounded
                        : Icons.info_outline_rounded),
                color: statusColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titleName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusBadgeLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            isAdmin
                ? 'Sua conta possui acesso ilimitado de Administrador Geral. Todos os recursos estão liberados sem restrições.'
                : (isPremium
                    ? 'Use esta tela para conferir o status da sua assinatura e aproveitar seus benefícios.'
                    : 'Use esta tela para acompanhar seu plano atual. Para uma compra nova, assine o Premium por apenas R\$ 14,90/mês.'),
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          if (premiumUntil != null && !isAdmin) ...[
            const SizedBox(height: 10),
            Text(
              'Renovacao atual ate $premiumUntil',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubscribeBenefitsCard extends StatelessWidget {
  const _SubscribeBenefitsCard();

  @override
  Widget build(BuildContext context) {
    // (label, freeValue, premiumValue)
    const rows = [
      ('Quizzes por vez', 'Até 10 questões', 'Ilimitadas com IA'),
      ('Simulados por semana', '1 por semana', 'Ilimitados'),
      ('Questões dissertativas', '1 por semana', 'Ilimitadas'),
      ('Modo Infinito com IA', '🔒 Indisponível', '∞ Ilimitado'),
      ('Histórico e estatísticas', '7 dias de histórico', 'Histórico completo'),
      ('Ranking da comunidade', '🔒 Indisponível', '✓ Acesso liberado'),
      ('Plano de estudo semanal', '🔒 Indisponível', '✓ Roteiro IA liberado'),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Grátis vs Premium',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          // Header row
          const Row(
            children: [
              Expanded(flex: 4, child: SizedBox.shrink()),
              Expanded(
                flex: 3,
                child: Text(
                  'Grátis',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Premium',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          for (final row in rows) ...[
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    row.$1,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    row.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: row.$2 == '🔒'
                          ? AppColors.textSecondary
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    row.$3,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ModeSwitchCard extends StatelessWidget {
  const _ModeSwitchCard({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingPlanCard extends StatelessWidget {
  const _BillingPlanCard({
    required this.plan,
    required this.status,
    required this.startingCheckout,
    required this.onCheckout,
  });

  final BillingPlan plan;
  final BillingStatus status;
  final bool startingCheckout;
  final Future<void> Function(BillingPlan plan) onCheckout;

  @override
  Widget build(BuildContext context) {
    final action = buildPremiumPlanAction(plan: plan, status: status);
    final isCurrentPlan = status.planCode == plan.code;
    final isPaidPlan = plan.priceCents > 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrentPlan
              ? AppColors.primary
              : (isPaidPlan
                  ? AppColors.border
                  : AppColors.textDisabled.withOpacity(0.6)),
          width: isCurrentPlan ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      plan.formattedPrice,
                      style: TextStyle(
                        color: isPaidPlan
                            ? AppColors.primary
                            : AppColors.textMuted,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrentPlan)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Plano atual',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: !action.enabled || startingCheckout
                    ? null
                    : () => onCheckout(plan),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor:
                      action.enabled ? AppColors.primary : AppColors.surface2,
                  disabledBackgroundColor: AppColors.surface2,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: AppColors.textMuted,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color:
                          action.enabled ? AppColors.primary : AppColors.border,
                    ),
                  ),
                ),
                child: startingCheckout && action.enabled
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        action.label,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactCurrentPlan extends StatelessWidget {
  const _CompactCurrentPlan({
    required this.currentPlanName,
    required this.premiumUntil,
    required this.isPremium,
  });

  final String currentPlanName;
  final String? premiumUntil;
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status atual do plano',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPremium
                ? '$currentPlanName ativo'
                : 'Plano atual: $currentPlanName',
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          if (premiumUntil != null) ...[
            const SizedBox(height: 4),
            Text(
              'Validade: $premiumUntil',
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onRefresh,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Text(
          'Atualizar status do plano',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PremiumErrorState extends StatelessWidget {
  const _PremiumErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Falha ao carregar assinatura',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              _RefreshButton(onRefresh: onRetry),
            ],
          ),
        ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.arrow_back_rounded,
          color: AppColors.textPrimary,
          size: 18,
        ),
      ),
    );
  }
}
