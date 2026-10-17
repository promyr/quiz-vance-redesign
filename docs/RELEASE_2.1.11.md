# Release 2.1.11+83 — Repaginação Visual Gamificada (Dark Tátil 3D)

- **Versão:** `2.1.11+83`
- **Commit Fonte:** `40d49b9edc8cac993fe52d1e461f1394328dd68d`
- **Artefato APK:** `backend/releases/android/quiz-vance-2.1.11.apk` (`output_apk/quiz-vance-2.1.11+83-universal.apk`)
- **Tamanho:** `40.599.698` bytes (`38,72 MB`)
- **SHA-256 (APK):** `643701ED6F94DB58837F3D6A94810F6D2F1BA4985EE2F49F619C13A92DEFF501`
- **SHA-256 (Certificado):** `B039A11E96AAFA7107BE445BD6404516ADA37962C0B735C059939EA15CA67215`
- **Publicação no Telegram (`@Gerent3Bot`):**
  - **Comunidade:** `-1003742591996` (Tópico `Atualizações`, `message_thread_id = 6`)
  - **Mensagem do APK (`message_id`):** `1023` (`https://t.me/c/3742591996/6/1023`)
  - **Mensagem do Changelog (`changelog_message_id`):** `1024` (`https://t.me/c/3742591996/6/1024`)

## Principais Entregas

1. **Design System Dark Gamificado Vibrante (`AppColors` / `AppTheme`):**
   - Paleta de alto contraste com fundo `Deep Obsidian` (`#0A0E17`), superfícies elevadas (`#131B2E`), `Electric Cobalt` (`#3B82F6`), `Cyber Mint` (`#00E5A3`) e `Vibrant Gold` (`#FFC800`).
   - Botões primários, Bento Tiles e cards interativos com relevo tátil 3D inferior (`boxShadow` físico sólido) e resposta imediata ao toque.
2. **Tela Inicial ("Hoje") Enxuta e Orientada à Ação (`HomeScreen`):**
   - Remoção de seções redundantes para eliminar poluição visual e rolagem desnecessária.
   - Barra de Progresso e XP unificada com Nível, Rank, XP acumulado e total de questões resolvidas.
   - Atalho direto para o Ranking Oficial (troféu dourado) no cabeçalho.
   - Arena de Prática balanceada em grade 2x2 (`Quiz IA Turbo`, `Dissertativo`, `Simulado Oficial` e `Plano do Dia`).
3. **Execução de Quiz de Alto Foco e Resultado Celebrativo (`QuizSessionScreen` / `QuizResultScreen`):**
   - Cabeçalho limpo focado na barra de progresso, contador de questão e cronômetro.
   - Alternativas com badges táteis `A / B / C / D` e feedback semântico instantâneo.
   - Tela de Resultado com painel celebrativo de desempenho e recompensas.
4. **Qualidade e Validação:**
   - `542/542` testes automatizados Flutter aprovados (`0` falhas), incluindo estresse de layout de `280px` a `800px` e `textScaler` até `3.0x`.
   - `10/10` testes de manifesto e publicador Telegram no backend aprovados.
   - Verificações `check_mojibake.ps1` e `check_secret_hygiene.mjs` aprovadas sem ocorrências.
