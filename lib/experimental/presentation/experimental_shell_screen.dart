import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/experimental_theme.dart';

class ExperimentalShellScreen extends StatefulWidget {
  const ExperimentalShellScreen({
    super.key,
    required this.variant,
  });

  final String variant;

  @override
  State<ExperimentalShellScreen> createState() =>
      _ExperimentalShellScreenState();
}

class _ExperimentalShellScreenState extends State<ExperimentalShellScreen> {
  int _currentIndex = 0;

  static const _pages = <_ExperimentalPage>[
    _ExperimentalPage(
      label: 'Hoje',
      icon: Icons.bolt_rounded,
      title: 'Hoje',
      subtitle: 'Prioridade real, nao menu',
      body: _TodayScreen(),
    ),
    _ExperimentalPage(
      label: 'Estudar',
      icon: Icons.auto_awesome_rounded,
      title: 'Estudar',
      subtitle: 'Fluxo guiado por impacto',
      body: _StudyScreen(),
    ),
    _ExperimentalPage(
      label: 'Biblioteca',
      icon: Icons.library_books_rounded,
      title: 'Biblioteca',
      subtitle: 'Material conectado ao plano',
      body: _LibraryScreen(),
    ),
    _ExperimentalPage(
      label: 'Perfil',
      icon: Icons.shield_rounded,
      title: 'Perfil',
      subtitle: 'Conta, seguranca e operacao',
      body: _ProfileScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    final page = _pages[_currentIndex];

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              colors.background,
              colors.surface,
              colors.panel,
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              Positioned(
                left: -40,
                top: -30,
                child: _GlowOrb(
                    color: colors.primary.withOpacity(0.16), size: 180),
              ),
              Positioned(
                right: -30,
                top: 120,
                child: _GlowOrb(
                    color: colors.secondary.withOpacity(0.16), size: 160),
              ),
              Positioned(
                left: 40,
                bottom: 140,
                child:
                    _GlowOrb(color: colors.accent.withOpacity(0.10), size: 120),
              ),
              Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                page.subtitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: colors.muted),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                page.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge
                                    ?.copyWith(color: colors.text),
                              ),
                              const SizedBox(height: 6),
                              _Badge(label: 'Paleta ${widget.variant}'),
                            ],
                          ),
                        ),
                        _GlassIconButton(
                          icon: Icons.notifications_none_rounded,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: page.body,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (value) {
                setState(() {
                  _currentIndex = value;
                });
              },
              destinations: _pages
                  .map(
                    (page) => NavigationDestination(
                      icon: Icon(page.icon),
                      label: page.label,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExperimentalPage {
  const _ExperimentalPage({
    required this.label,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
  });

  final String label;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget body;
}

class _TodayScreen extends StatelessWidget {
  const _TodayScreen();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const <Widget>[
        _HeroPanel(
          eyebrow: 'Proxima melhor acao',
          title: 'Retomar Direito Administrativo',
          description:
              'Seu risco subiu porque o tema caiu para 61% de acerto e voce tem revisoes vencendo hoje.',
          primaryAction: 'Continuar agora',
          secondaryAction: 'Ver plano',
        ),
        SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: _StatCard(
                label: 'Meta semanal',
                value: '82%',
                note: '11,4h de 14h',
                progress: 0.82,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Streak',
                value: '9 dias',
                note: 'melhor serie em 30 dias',
                progress: 0.74,
              ),
            ),
          ],
        ),
        SizedBox(height: 14),
        _SectionCard(
          title: 'Fila inteligente',
          badge: 'ordenada por impacto',
          children: <Widget>[
            _ActionRow(
              title: 'Revisao guiada',
              subtitle:
                  'Erros do ultimo simulado convertidos em um bloco curto de recuperacao.',
              trailing: '18 min',
            ),
            _ActionRow(
              title: 'Pacote do tema fraco',
              subtitle:
                  'Resumo, quiz e flashcards do mesmo assunto numa sequencia unica.',
              trailing: 'Biblioteca',
            ),
            _ActionRow(
              title: 'Discursiva de consolidacao',
              subtitle:
                  'Treino aberto com um angulo novo para nao repetir historico.',
              trailing: 'IA',
            ),
          ],
        ),
        SizedBox(height: 14),
        _SectionCard(
          title: 'Alertas',
          badge: '2 urgentes',
          children: <Widget>[
            _ActionRow(
              title: '12 flashcards vencem hoje',
              subtitle: 'Vale encaixar um bloco de 9 minutos antes das 18h.',
              trailing: 'urgente',
            ),
            _ActionRow(
              title: 'Plano atrasado em 1 dia',
              subtitle:
                  'O app sugere um modo de recuperacao curto para voltar ao ritmo.',
              trailing: 'recuperar',
            ),
          ],
        ),
      ],
    );
  }
}

class _StudyScreen extends StatelessWidget {
  const _StudyScreen();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const <Widget>[
        _SectionHeader(
          title: 'Recomendado agora',
          subtitle: 'Os modos continuam existindo, mas entram por intencao.',
        ),
        SizedBox(height: 12),
        _ModuleCard(
          title: 'Quiz adaptativo',
          badge: 'mais indicado',
          description:
              '12 questoes puxadas dos seus erros recentes e da prova alvo.',
          metrics: <String>['14 min', 'Adm.', '+6 pts'],
        ),
        SizedBox(height: 12),
        _ModuleCard(
          title: 'Flashcards de recuperacao',
          badge: '12 vencidos',
          description:
              'Repeticao espacada com anti-repeticao de sugestoes ja vistas.',
          metrics: <String>['9 min', 'SRS', 'leve'],
        ),
        SizedBox(height: 12),
        _ModuleCard(
          title: 'Discursiva com IA',
          badge: 'profundo',
          description:
              'Treino aberto com historico para explorar perguntas novas.',
          metrics: <String>['22 min', 'aberta', 'analise'],
        ),
        SizedBox(height: 12),
        _ModuleCard(
          title: 'Simulado inteligente',
          badge: 'prova real',
          description:
              'Peso maior nos assuntos em que sua confianca esta acima da precisao.',
          metrics: <String>['40 min', 'prova', 'pressao'],
        ),
      ],
    );
  }
}

class _LibraryScreen extends StatelessWidget {
  const _LibraryScreen();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const <Widget>[
        _SectionHeader(
          title: 'Biblioteca conectada',
          subtitle:
              'Nao e so acervo. E material ligado ao que o plano pede agora.',
        ),
        SizedBox(height: 12),
        _SectionCard(
          title: 'Pacote em foco',
          badge: 'tema fraco',
          children: <Widget>[
            _ActionRow(
              title: 'Direito Administrativo: atos',
              subtitle:
                  'Resumo enxuto, 18 flashcards e quiz prontos para abrir em sequencia.',
              trailing: 'abrir',
            ),
            _ActionRow(
              title: 'Constitucional: controle',
              subtitle:
                  'Material sugerido a partir do seu ultimo bloco abaixo da meta.',
              trailing: 'sugerido',
            ),
          ],
        ),
        SizedBox(height: 14),
        _SectionCard(
          title: 'Colecoes',
          badge: 'curadoria',
          children: <Widget>[
            _ActionRow(
              title: 'Recuperacao rapida',
              subtitle: 'Pacotes curtos para sair de atraso sem travar o dia.',
              trailing: '15 min',
            ),
            _ActionRow(
              title: 'Base teorica',
              subtitle: 'Leituras e resumos para temas ainda rasos.',
              trailing: 'fundacao',
            ),
            _ActionRow(
              title: 'Reta final',
              subtitle: 'Conteudo comprimido para proximidade de prova.',
              trailing: 'sprint',
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const <Widget>[
        _ProfileHero(),
        SizedBox(height: 14),
        _SectionCard(
          title: 'Conta',
          badge: 'protegida',
          children: <Widget>[
            _ActionRow(
              title: 'Alterar ID da conta',
              subtitle:
                  'Checagem instantanea de disponibilidade antes de salvar.',
              trailing: '@belchiorvance',
            ),
            _ActionRow(
              title: 'Sessoes ativas',
              subtitle:
                  'Ver ultimo acesso e encerrar outros dispositivos com um toque.',
              trailing: '3',
            ),
            _ActionRow(
              title: 'Senha e acesso',
              subtitle:
                  'Troca de senha, historico basico e alertas de tentativa suspeita.',
              trailing: 'seguro',
            ),
          ],
        ),
        SizedBox(height: 14),
        _SectionCard(
          title: 'API keys e IA',
          badge: 'operacional',
          children: <Widget>[
            _ActionRow(
              title: 'OpenAI conectada',
              subtitle:
                  'Teste de conexao, ultimo uso e fallback sem tela quebrando.',
              trailing: 'ok',
            ),
            _ActionRow(
              title: 'Gemini reserva',
              subtitle:
                  'Provedor secundario para redundancia em caso de falha.',
              trailing: 'opcional',
            ),
          ],
        ),
        SizedBox(height: 14),
        _DangerCard(),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero();

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return _GlassCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: <Widget>[
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: <Color>[colors.primary, colors.secondary],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: colors.primary.withOpacity(0.24),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Center(
              child: Text(
                'BV',
                style: TextStyle(
                  color: colors.background,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Belchior Vance',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '@belchiorvance',
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.muted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Liga Ouro • 9 dias de streak • Plano ativo',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.primaryAction,
    required this.secondaryAction,
  });

  final String eyebrow;
  final String title;
  final String description;
  final String primaryAction;
  final String secondaryAction;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.surface,
            colors.panel,
            colors.primary.withOpacity(0.42),
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.primary.withOpacity(0.18),
            blurRadius: 26,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            eyebrow,
            style: TextStyle(
              color: colors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontSize: 31),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _PrimaryPill(label: primaryAction),
              _SecondaryPill(label: secondaryAction),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.note,
    required this.progress,
  });

  final String label;
  final String value;
  final String note;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontSize: 28),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: colors.text.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(note, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.badge,
    required this.children,
  });

  final String title;
  final String badge;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child:
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
              _Badge(label: badge),
            ],
          ),
          const SizedBox(height: 12),
          ..._separated(children),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.title,
    required this.badge,
    required this.description,
    required this.metrics,
  });

  final String title;
  final String badge;
  final String description;
  final List<String> metrics;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child:
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
              _Badge(label: badge),
            ],
          ),
          const SizedBox(height: 10),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: metrics
                .map(
                  (metric) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: colors.text.withOpacity(0.05),
                      ),
                    ),
                    child: Text(
                      metric,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _DangerCard extends StatelessWidget {
  const _DangerCard();

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: colors.danger.withOpacity(0.08),
        border: Border.all(color: colors.danger.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Zona critica',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.danger,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Excluir conta continua possivel, mas com senha atual e confirmacao textual clara. Nada escondido, nada ambiguo.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: colors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            trailing,
            style: TextStyle(
              color: colors.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: colors.card.withOpacity(0.74),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.text.withOpacity(0.06)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 22,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.primary.withOpacity(0.14)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PrimaryPill extends StatelessWidget {
  const _PrimaryPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.background,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SecondaryPill extends StatelessWidget {
  const _SecondaryPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.text.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.text.withOpacity(0.08)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.text,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: colors.card.withOpacity(0.60),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: colors.text),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color,
              blurRadius: size * 0.6,
              spreadRadius: size * 0.08,
            ),
          ],
        ),
      ),
    );
  }
}

List<Widget> _separated(List<Widget> children) {
  final result = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    result.add(children[i]);
    if (i != children.length - 1) {
      result.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Divider(height: 1),
      ));
    }
  }
  return result;
}

ExperimentalColors _colors(BuildContext context) {
  return Theme.of(context).extension<ExperimentalColors>()!;
}
