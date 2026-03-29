# Quiz Vance Redesign

Cliente Flutter do Quiz Vance para estudo com IA, quiz objetivo, quiz dissertativo, simulados, flashcards com repeticao espacada, biblioteca de materiais, plano de estudo, gamificacao e assinatura premium.

Este README descreve o estado real do repositorio em `2026-03-29`.

## Estado atual

- plataformas ativas: Android, iOS e Windows
- autenticacao real via backend; demo mode removido
- bootstrap e execucao local preparados para usar Flutter do Puro quando disponivel
- storage local criptografado com `sqlite3` + `sqlcipher_flutter_libs`
- cache complementar em `SharedPreferences`
- tokens e segredos em `flutter_secure_storage`

## Stack

| Camada | Tecnologia |
| --- | --- |
| UI | Flutter |
| Linguagem | Dart 3 |
| Estado | `flutter_riverpod` |
| Roteamento | `go_router` |
| HTTP | `dio` |
| Banco local | `sqlite3`, `sqlcipher_flutter_libs`, `sqflite` |
| Preferencias | `shared_preferences` |
| Segredos locais | `flutter_secure_storage` |
| Arquivos | `file_picker` |
| PDF | `syncfusion_flutter_pdf` |
| Graficos | `fl_chart` |
| Animacoes | `flutter_animate`, `lottie` |
| Notificacoes | `flutter_local_notifications`, `timezone` |
| Links externos | `url_launcher` |

## Estrutura

```text
lib/
|-- app/        # bootstrap visual e roteamento
|-- core/       # config, rede, storage, tema, notificacoes
|-- features/   # modulos por dominio
`-- shared/     # providers e widgets compartilhados
```

Padrao praticado no projeto:

- `domain/`: modelos e regras simples
- `data/`: repositorios, adapters e integracao remota/local
- `presentation/`: telas e widgets da feature

Observacao:

- a organizacao por pastas existe, mas algumas features ainda concentram orquestracao na UI; isso esta em refactor gradual

## Features principais

- autenticacao com login, cadastro, refresh de token e restauracao de sessao
- quiz objetivo com geracao via backend e submissao de resultado
- quiz dissertativo com geracao e correcao remota
- flashcards com revisao local e sync remoto best-effort
- simulados com cronometro e resultado
- biblioteca de materiais com importacao de PDF, TXT e MD
- pacote de estudo a partir da biblioteca
- plano de estudo semanal
- ranking semanal, mensal e global
- perfil, stats, conquistas e premium
- configuracao de provedor de IA e chaves de API

## Persistencia local

### SQLite criptografado

Banco principal: `quiz_vance.db`

Uso atual:

- flashcards
- sessoes e caches locais estruturados
- arquivos da biblioteca
- cache do usuario e dados auxiliares

### SharedPreferences

Usado para estado leve e preferencias, como:

- progresso de gamificacao
- configuracoes de IA
- plano de estudo ativo
- contadores locais de flashcards

### Flutter Secure Storage

Usado para:

- `auth_token`
- `refresh_token`
- chave do banco local criptografado
- segredos locais de integracao, quando aplicavel

## Backend

Backend padrao:

```text
https://quiz-vance-redesign-backend.fly.dev
```

Override em runtime:

```powershell
flutter run -d windows --dart-define=BACKEND_URL=http://localhost:8000
```

Endpoints consumidos pelo app incluem:

- `/auth/login`
- `/auth/register`
- `/auth/logout`
- `/auth/refresh`
- `/auth/me`
- `/quiz/generate`
- `/quiz/submit`
- `/quiz/open/generate`
- `/quiz/open/grade`
- `/flashcards`
- `/flashcards/review`
- `/flashcards/create`
- `/flashcards/sync`
- `/simulado/generate`
- `/simulado/submit`
- `/ranking/weekly`
- `/ranking/monthly`
- `/ranking/global`
- `/study-plan/generate`
- `/library/generate-package`
- `/user/stats`
- `/user/profile`
- `/user/profile/update`
- `/user/ai-config`
- `/billing/plans`
- `/billing/status`
- `/billing/checkout/start`

## Ambiente recomendado

### Flutter

O workspace esta configurado para priorizar o ambiente:

```text
Puro stable
```

Arquivo de referencia:

```text
.puro.json
```

Se houver mais de um Flutter instalado na maquina, prefira os scripts da raiz do projeto para evitar mistura de SDKs.

### Windows

Para build desktop, o projeto depende de:

- Visual Studio Build Tools com C++
- OpenSSL disponivel para o plugin `sqlcipher_flutter_libs`

O `windows/CMakeLists.txt` contem fallback local para encontrar OpenSSL em ambientes Windows ja preparados.

## Execucao local

### Setup inicial

```powershell
.\SETUP.ps1
```

O setup:

- resolve o Flutter
- executa `flutter doctor`
- garante plataformas
- instala dependencias quando necessario
- roda `flutter analyze --no-pub`
- roda `flutter test --no-pub`

### Rodar no Windows

```powershell
.\INICIAR.ps1
```

Ou com backend customizado:

```powershell
.\INICIAR.ps1 -BackendUrl http://localhost:8000
```

O launcher usa `--no-pub` quando o cache local ja esta preparado, para evitar dependencia desnecessaria de rede.

### Android

```powershell
flutter run -d <device-id> --dart-define=BACKEND_URL=http://localhost:8000
```

## Builds

### APK assinado

```powershell
.\BUILD_APK.ps1
```

Saidas principais:

- `build/app/outputs/flutter-apk/app-release.apk`
- `output_apk/app-universal-release.apk`
- `output_apk/app-arm64-v8a-release.apk` quando o split build conclui

### Build release por script

```powershell
.\scripts\build_release.ps1 -Platform android
.\scripts\build_release.ps1 -Platform windows
.\scripts\build_release.ps1 -Platform all
```

Saidas esperadas:

- Android APK: `build/app/outputs/flutter-apk/app-release.apk`
- Android AAB: `build/app/outputs/bundle/release/app-release.aab`
- Windows EXE: `build/windows/x64/runner/Release/quiz_vance_flutter.exe`

## CI

O workflow principal fica em:

- `.github/workflows/build.yml`

Objetivo atual:

- analisar e testar
- gerar APK release em pushes e PRs
- gerar AAB em tags
- gerar artefato Windows release

## Testes e validacao

Comandos principais:

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --debug --no-pub --dart-define=BACKEND_URL=https://quiz-vance-redesign-backend.fly.dev
```

Observacoes:

- a maior parte da cobertura atual ainda esta em testes unitarios
- o projeto ainda tem poucos widget tests e nao possui `integration_test`

## Limites conhecidos

- o backend nao faz parte deste repositorio
- notificacoes locais completas sao foco de Android/iOS; Windows nao tem o mesmo suporte operacional
- parte da orquestracao ainda esta em telas grandes e sera movida para camadas intermediarias em refactors futuros
- ainda faltam analytics e observabilidade de produto

## Arquivos centrais

- `lib/main.dart`
- `lib/app/router.dart`
- `lib/core/config/app_config.dart`
- `lib/core/network/api_client.dart`
- `lib/core/network/api_endpoints.dart`
- `lib/core/storage/local_storage.dart`
- `lib/shared/providers/auth_provider.dart`
- `lib/shared/providers/user_provider.dart`
- `lib/shared/providers/gamification_provider.dart`
- `lib/features/quiz/data/quiz_repository.dart`
- `lib/features/flashcard/data/flashcard_repository.dart`
- `lib/features/library/data/library_repository.dart`
- `lib/features/open_quiz/data/open_quiz_repository.dart`
- `lib/features/simulado/data/simulado_repository.dart`
- `lib/features/study_plan/data/study_plan_repository.dart`
- `lib/features/profile/data/billing_repository.dart`

## Documentos auxiliares

Arquivos historicos ainda presentes:

- `QUICK_START.md`
- `FEATURES_IMPLEMENTATION.md`
- `TELAS_IMPLEMENTADAS.md`
- `EXEMPLOS_NAVEGACAO.md`
- `CHECKLIST_IMPLEMENTACAO.md`

Esses documentos podem ajudar com contexto historico, mas o README da raiz deve ser tratado como fonte principal para setup, execucao e build.
