# Quiz Vance 2.1.12 — build 84

Geração mista entre médio e difícil por padrão. O modo exclusivamente difícil
exige ativação manual em quiz, simulado e dissertativas e começa desligado.
O plano de estudos não ativa esse modo por sugestão automática da IA.
Treino infinito conserva a escolha da sessão. Histórico e estatísticas são preservados.

O APK universal production foi compilado na nuvem a partir do commit
`985959c741668e21dbb73ec8982623aa997f38d5`. A verificação local confirmou
versionName 2.1.12, versionCode 84, pacote com.quizvance.quiz_vance_flutter,
arm64-v8a, armeabi-v7a e x86_64, assinatura válida e alinhamento de 16 KB.

- Arquivo: `output_apk/quiz-vance-2.1.12+84-universal.apk`
- Tamanho: 40587246 bytes
- SHA-256: `D76BD849A6BA4580E050A1FA4B6EE985C4C3764D8570BCFD7CF184EFF8EAF872`
- Certificado: `B039A11E96AAFA7107BE445BD6404516ADA37962C0B735C059939EA15CA67215`
- Execução: https://github.com/promyr/quiz-vance-redesign/actions/runs/39071394376

A execução passou nos testes Flutter e backend, análise estática e scanner da
imagem, mas foi marcada como falha ao extrair o certificado: o Build Tools 37
usa o rótulo `V2 Signer:` em vez de `Signer #1`. A assinatura e o alinhamento
já haviam passado no servidor; os relatórios e o APK foram preservados.
O arquivo foi baixado e verificado independentemente com Build Tools 36.
A leitura foi corrigida para os dois formatos nos scripts de compilação.

Os quatro secrets temporários de assinatura foram removidos ao encerrar a
execução. O APK está gerado e verificado, sem publicação em Render ou Telegram
e sem teste em dispositivo nesta etapa. A distribuição anterior não foi alterada.
