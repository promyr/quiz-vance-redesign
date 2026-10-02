import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/experimental_theme.dart';

part 'experimental_shell_sections.dart';

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
