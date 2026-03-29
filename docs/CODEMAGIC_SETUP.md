# Codemagic Setup

O repositório já está preparado para o modo YAML do Codemagic com o arquivo `codemagic.yaml` na raiz.

## Workflows

- `android-release`
- `ios-release`

## Valores já fixados no projeto

- Flutter: `3.41.4`
- Android applicationId: `com.quizvance.quiz_vance_flutter`
- iOS bundle id: `com.quizvance.quizVanceFlutter`
- Android keystore reference esperado no Codemagic: `quiz_vance_android_release`
- App Store Connect integration esperada no Codemagic: `quiz-vance-app-store-connect`

## Passos manuais no Codemagic

### 1. Alternar o app para YAML

Na tela do workflow do app, clique em `Alternar para a configuração YAML` e salve.

### 2. Configurar assinatura Android

Em `Team settings > codemagic.yaml settings > Code signing identities > Android keystores`:

- faça upload da mesma keystore usada no projeto
- use a referência `quiz_vance_android_release`

O workflow gera automaticamente `android/key.properties` durante o build usando as variáveis padrão do Codemagic:

- `CM_KEYSTORE_PATH`
- `CM_KEYSTORE_PASSWORD`
- `CM_KEY_ALIAS`
- `CM_KEY_PASSWORD`

### 3. Configurar assinatura iOS

Em `Team integrations > Developer Portal`, crie a integração App Store Connect com o nome:

- `quiz-vance-app-store-connect`

Depois, em `Code signing identities`, garanta que o bundle id abaixo tenha certificado e profile compatíveis:

- `com.quizvance.quizVanceFlutter`

### 4. Rodar os builds

Você pode executar separadamente:

- `android-release`
- `ios-release`

## Observações

- O projeto iOS foi scaffoldado no repositório porque o Codemagic precisa do Xcode project para gerar IPA.
- O ícone iOS segue a mesma decisão de branding do Android: launcher com `QV`, logo oficial mantida para branding do projeto.
