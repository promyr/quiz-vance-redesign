# Plano mestre de refatoração — Quiz Vance

Data do baseline: 2026-08-07

## Entendimento confirmado

- Refatorar progressivamente o aplicativo Flutter, o backend FastAPI, testes e scripts operacionais.
- Preservar comportamento, contratos HTTP, dados, rotas, visual, autenticação, privilégios administrativos e artefatos de release.
- Considerar o estado atual da árvore de trabalho como baseline oficial, inclusive as alterações ainda não consolidadas no Git.
- Priorizar correção, segurança, confiabilidade e testabilidade antes de mudanças puramente estéticas.
- Não introduzir funcionalidades novas nem migrações destrutivas durante a refatoração.
- Manter Android como plataforma principal sem criar divergências intencionais entre plataformas.

## Baseline verificável

- Flutter: 142 arquivos Dart e aproximadamente 37.553 linhas.
- Apresentação: 28 telas e aproximadamente 21.244 linhas.
- Git: 350 entradas alteradas no início do trabalho.
- `flutter analyze`: aprovado.
- `flutter test`: 360 testes aprovados.
- Backend: 121 testes aprovados; seis avisos de depreciação do adaptador SQLite do Python.

## Premissas não funcionais

- Contratos públicos permanecem compatíveis com o APK já distribuído.
- Dados locais e remotos existentes não podem ser descartados.
- Segredos, tokens, conteúdo integral de PDFs e credenciais não entram em logs.
- Operações de rede, armazenamento, biometria, PDF e IA devem ter timeout e falhas classificadas.
- Cada lote deve permanecer reversível e pequeno o suficiente para localizar regressões.
- O desempenho não pode piorar em inicialização, login, navegação ou processamento de documentos.

## Arquitetura alvo

### Flutter

Cada feature mantém quatro responsabilidades explícitas:

1. `domain`: entidades e regras puras;
2. `application`: casos de uso, coordenação e estado;
3. `data`: API, banco e armazenamento;
4. `presentation`: composição visual sem regras de negócio ou acesso direto a infraestrutura.

Componentes compartilhados ficam em `core` somente quando são infraestrutura global e em `shared` quando são comportamentos reutilizáveis de produto. Providers fazem injeção e exposição de estado; não concentram regras que pertencem a casos de uso.

### Backend

O backend permanece um monólito modular FastAPI:

1. routers validam e traduzem HTTP;
2. services executam regras e orquestração;
3. repositories encapsulam persistência;
4. integrações externas ficam em gateways específicos;
5. `main.py` apenas monta aplicação, middleware, lifecycle e routers.

## Fases

### Fase 1 — fundações e fronteiras

- Consolidar tratamento de erros e respostas externas.
- Reduzir acoplamento de autenticação, roteamento, armazenamento e providers.
- Criar testes de caracterização para fluxos transversais.
- Identificar e remover dependências circulares.

### Fase 2 — PDF e geração por IA

- Unificar Biblioteca e Plano de Estudos sobre um pipeline documental comum.
- Separar upload, extração, análise, polling, retry e apresentação.
- Centralizar fallback, timeout e classificação de provedores.

### Fase 3 — apresentação Flutter

- Dividir telas com mais de 500 linhas em seções e controllers coesos.
- Remover widgets duplicados e estados locais redundantes.
- Preservar chaves, semântica, navegação e comportamento visual.

### Fase 4 — backend modular

- Extrair rotas e regras restantes de `backend/app/main.py`.
- Dividir o serviço de IA por seleção, transporte, parsing e política de retry.
- Manter compatibilidade de schemas e banco.

### Fase 5 — limpeza e release

- Remover código morto, experimentos não usados e dependências comprovadamente ociosas.
- Atualizar documentação, mapa arquitetural e gates de CI.
- Executar testes, análise, segurança, build e verificação do APK.

## Gates de qualidade

Para cada lote:

1. escrever teste de caracterização ou regressão;
2. confirmar o teste vermelho quando representar comportamento ausente;
3. aplicar a menor alteração estrutural possível;
4. executar testes direcionados;
5. executar `flutter analyze` ou Ruff conforme o ecossistema;
6. executar a suíte completa ao concluir a fase;
7. registrar riscos residuais.

## Riscos principais

- A árvore de trabalho extensa dificulta atribuir autoria e reconstruir releases.
- Telas gigantes misturam estado, acesso a dados e renderização.
- `backend/app/main.py` e o serviço de IA têm blast radius elevado.
- Capturas genéricas de exceção ocultam falhas de produção.
- Modelos baseados em `Map<String, dynamic>` permitem erros tardios de contrato.
- Refatorações transversais podem afetar dados locais multiusuário e sessões existentes.

## Registro de decisões

1. **Baseline:** preservar o estado atual completo. Alternativa rejeitada: restaurar o último commit, pois descartaria trabalho válido.
2. **Estratégia:** refatoração incremental orientada por risco. Alternativa rejeitada: reescrita total, devido ao risco de regressão.
3. **Compatibilidade:** não alterar contratos ou visual intencionalmente. Mudanças de produto ficam fora deste plano.
4. **Sequência:** fundações, documentos/IA, apresentação, backend e limpeza. Essa ordem elimina duplicações transversais antes de dividir módulos consumidores.
5. **Validação:** nenhum lote avança com testes ou análise falhando.

## Critério de conclusão

A refatoração termina quando as responsabilidades principais estiverem separadas, duplicações críticas removidas, arquivos gigantes reduzidos por componentes coesos, contratos preservados, documentação atualizada e todos os gates de Flutter/backend/release aprovados.

## Progresso consolidado em 07/08/2026

- Autenticação e roteamento: a navegação usa uma instância estável de `GoRouter`; o login por senha não abre biometria durante a troca para a Home; operações do cofre biométrico têm timeout e execução serializada.
- Estado por conta: providers dependem de um epoch de sessão, eliminando dependências circulares entre autenticação, usuário e gamificação.
- Documentos: seleção e validação de PDF foram centralizadas; Biblioteca e Plano de Estudos usam o mesmo formato e o backend mantém análise segmentada, checkpoint e retry.
- IA: chaves pessoais e OpenAI foram removidos do cliente; o pool central Gemini/Groq e o painel administrativo RBAC permanecem. Parsing JSON, saneamento de material e normalização de edital agora são módulos separados.
- Apresentação: Perfil, Premium, Home, Quiz, Plano Diário e shell experimental delegam seções visuais a arquivos menores, protegidos por testes de modularidade.
- Backend: health checks, distribuição de releases, agendamento do Telegram, análise documental, normalização de edital e preferências do usuário foram extraídos do monólito.
- Dependências: `lottie` e seus assets foram removidos após verificação de ausência total de uso. `cupertino_icons` foi mantido porque o tema usa `CupertinoPageTransitionsBuilder`, que referencia essa fonte durante a compilação release.
- Qualidade: 370 testes Flutter e 131 testes backend aprovados; `flutter analyze` e Ruff sem erros; avisos de adaptadores SQLite do Python 3.12 eliminados na infraestrutura de testes.

## Riscos residuais antes da publicação

- O repositório permanece com uma árvore de trabalho extensa herdada de alterações anteriores; o escopo exato do release deve ser registrado no manifesto.
- Testes nativos de biometria em aparelho físico continuam necessários porque o plugin depende do ciclo de vida da Activity e do keystore do dispositivo.

## Evidências finais do lote

- Flutter: `flutter analyze` sem problemas e 370 testes aprovados.
- Backend: Ruff e Bandit (severidade média/alta) sem violações, 131 testes aprovados, bytecode compilado e Alembic com uma única head.
- Segurança: verificação de higiene de segredos sem achados.
- Release: políticas de versão e APK universal aprovadas.
- Artefato: `quiz-vance-2.0.61+60-universal.apk`, 40.275.098 bytes.
- SHA-256: `D9BCD47E29FEEB5270E8D2170807A2F6EA50D96DC643D202B996262C1CD03FC3`.
- Assinatura: APK Signature Scheme v2, certificado `B039A11E96AAFA7107BE445BD6404516ADA37962C0B735C059939EA15CA67215`.
- Alinhamento: verificado com sucesso por `zipalign`.
