# Proveniência de release — Quiz Vance

## Canal oficial

O único artefato Android oficial é o APK universal do flavor `production`.
O Telegram deve publicar somente o link HTTPS estável retornado por
`/app/update`; anexos, APKs split, AABs e builds experimentais não são canais
oficiais.

Arquivos antigos permanecem preservados até existir autorização de limpeza,
mas são considerados **não publicáveis**. Nomes genéricos antigos, incluindo
`app-universal-release.apk`, não determinam a versão atual.

## Identidade canônica

Cada release deve ligar, em um manifesto:

1. commit Git e confirmação de árvore limpa;
2. versão completa do `pubspec.yaml`, incluindo `versionCode`;
3. Alembic head;
4. digest da imagem Fly;
5. nome, tamanho e SHA-256 do APK;
6. SHA-256 do certificado de assinatura;
7. URL pública e SHA-256 baixado novamente;
8. ID da mensagem fixada no Telegram.

Ausência ou divergência de qualquer campo bloqueia publicação.

## Build Android

Use `BUILD_APK.ps1` ou `scripts/build_release.ps1 -Platform android`. Ambos
constroem somente:

```text
output_apk/quiz-vance-<versionName>+<versionCode>-universal.apk
```

O build recebe `BACKEND_URL` e `APP_VERSION`, usa o flavor `production` e não
apaga APKs históricos. `BUILD_APK.ps1` valida a assinatura com `apksigner`,
calcula SHA-256 e grava `output_apk/release-manifest.json`.

Release sem `android/key.properties`, propriedade obrigatória ou keystore real
falha fechado. Fallback para assinatura debug é proibido.

## Backend e migration

O container executa como usuário não-root. Migration não roda no comando de
startup: o Fly executa `alembic upgrade head` uma vez via `release_command`
antes de trocar o tráfego. O deploy continua bloqueado sem backup/restore,
head único e compatibilidade comprovada com APK N−1/N−2.

## CI

O workflow:

- bloqueia regressões de secrets;
- executa testes e análise Flutter/backend;
- constrói somente APK universal production;
- exige signing material vindo de GitHub Secrets;
- valida assinatura, alinhamento e hashes;
- gera SBOM para APK e imagem;
- bloqueia vulnerabilidades altas no container;
- fixa GitHub Actions por commit SHA.

## Telegram

Antes de qualquer mutação, o publicador:

1. valida host HTTPS canônico;
2. calcula tamanho e SHA-256 do APK da imagem;
3. baixa o link público em streaming;
4. exige tamanho e SHA-256 idênticos;
5. edita o pin atual ou cria e fixa o substituto sem remover previamente o pin
   saudável;
6. relê o pin e confirma texto e botão.

Publicadores legados ou por anexo devem permanecer neutralizados e nunca ser
usados para anunciar uma versão oficial.
