# Quiz Vance Redesign

Flutter app para estudo com IA, quizzes objetivos e dissertativos, flashcards com repeticao espacada, simulados, biblioteca de materiais, plano de estudo, gamificacao e assinatura premium.

[![Build and Release](https://github.com/promyr/quiz-vance-redesign/actions/workflows/build.yml/badge.svg)](https://github.com/promyr/quiz-vance-redesign/actions/workflows/build.yml)

<p align="center">
  <img src="assets/quiz_vance_logo_1024.png" alt="Quiz Vance official logo" width="260" />
</p>

## Visao geral

O Quiz Vance Redesign e o cliente Flutter da nova experiencia do Quiz Vance. O projeto foi estruturado por features e roda hoje em:

- Android
- iOS
- Windows

Capacidades principais:

- autenticacao real com refresh e restauracao de sessao
- quiz objetivo gerado por backend
- quiz dissertativo com correcao por IA
- simulados com cronometro e resultado
- flashcards com revisao e repeticao espacada
- biblioteca de materiais com PDF, TXT e MD
- plano de estudo
- ranking, conquistas e gamificacao
- premium e checkout
- configuracao de provedor de IA

## Stack

| Camada | Tecnologia |
| --- | --- |
| App | Flutter + Dart 3 |
| Estado | `flutter_riverpod` |
| Roteamento | `go_router` |
| HTTP | `dio` |
| Storage local | `sqlite3`, `sqlcipher_flutter_libs`, `sqflite` |
| Segredos locais | `flutter_secure_storage` |
| Preferencias | `shared_preferences` |
| Notificacoes | `flutter_local_notifications`, `timezone` |
| UI/animacoes | `fl_chart`, `flutter_animate`, `lottie` |

## Arquitetura

Estrutura principal:

```text
lib/
|-- app/
|-- core/
|-- features/
`-- shared/
```

Padrao usado no projeto:

- `domain`: modelos e regras simples
- `data`: repositorios e integracao local/remota
- `application`: coordenadores e fluxos de orquestracao
- `presentation`: telas e widgets
- `shared`: providers e componentes compartilhados

## Backend

Backend padrao usado pelo app:

```text
https://quiz-vance-redesign-backend.fly.dev
```

Override local:

```powershell
flutter run -d windows --dart-define=BACKEND_URL=http://localhost:8000
```

## Setup rapido

### Ambiente recomendado

- Flutter via Puro
- Windows com Visual Studio Build Tools para desktop
- Android SDK configurado para builds Android

### Setup

```powershell
.\SETUP.ps1
```

### Rodar no Windows

```powershell
.\INICIAR.ps1
```

### Rodar no Android

```powershell
flutter run -d <device-id> --dart-define=BACKEND_URL=http://localhost:8000
```

## Build

### APK

```powershell
.\BUILD_APK.ps1
```

Saidas principais:

- `output_apk/app-universal-release.apk`
- `output_apk/app-arm64-v8a-release.apk`

### Build multiplataforma

```powershell
.\scripts\build_release.ps1 -Platform android
.\scripts\build_release.ps1 -Platform windows
```

## CI e releases

O repositório publica um workflow em:

- `.github/workflows/build.yml`

Fluxo atual:

- `push` e `pull_request` em `main`: analyze, testes, APK e build Windows
- `tags v*`: gera release com artefatos
- `workflow_dispatch`: execucao manual

## Codemagic

O projeto tambem inclui configuracao pronta para Codemagic:

- `codemagic.yaml`
- `docs/CODEMAGIC_SETUP.md`

## Testes

Comandos principais:

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

## Documentacao auxiliar

Documentos historicos ainda mantidos no repositório:

- `QUICK_START.md`
- `FEATURES_IMPLEMENTATION.md`
- `TELAS_IMPLEMENTADAS.md`
- `EXEMPLOS_NAVEGACAO.md`
- `CHECKLIST_IMPLEMENTACAO.md`
- `REFACTOR_LOG.md`
- `PHASE2_STATUS_2026-03-29.md`
- `PHASE3_STATUS_2026-03-29.md`

## Status

Estado atual do repositório em `2026-03-29`:

- demo mode removido
- storage local criptografado
- observabilidade interna adicionada
- acessibilidade base reforcada nos widgets compartilhados
- pipeline de build e release ativo
