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
4. identificação do deploy/imagem do backend ativo;
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

O backend atual usa Render. O container executa como usuário não-root e
`alembic upgrade head` deve concluir antes de iniciar o Gunicorn e seus workers.
O arquivo Fly é legado e não comprova a configuração do serviço ativo.
Mudanças de schema exigem backup/restore, head único e avaliação de
compatibilidade com os APKs suportados. Retirar a migration do startup exige
antes configurar uma etapa de deploy equivalente no serviço ativo.

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

Flutter tem um job independente das credenciais de assinatura, executado em
push e pull request. O APK assinado é gerado somente em tag `v*` ou execução
manual, depois de todos os jobs de qualidade e segurança. Os entrypoints locais
recusam fontes modificadas ou novas sem commit e verificam novamente o mesmo
commit após o build. Não altere retroativamente `clean_tree` de releases antigas.

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
