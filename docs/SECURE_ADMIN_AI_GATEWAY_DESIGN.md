# Administração remota segura e AI Gateway

## Entendimento confirmado

- O proprietário precisa continuar entrando pelo aplicativo com o login `admin`.
- O painel administrativo deve permitir cadastrar, testar, ativar, desativar e priorizar chaves de IA longe do servidor.
- O aplicativo não pode criar uma sessão administrativa local nem aceitar uma senha administrativa por convenção.
- Somente o backend decide se uma conta é administradora, premium e qual é sua cota.
- Chaves mestras pertencem ao servidor e nunca devem ser devolvidas integralmente ao APK.
- A geração precisa usar um pool central com fallback e estado de saúde compartilhado entre dispositivos.
- O restante da aplicação deve continuar funcionando para usuários comuns, inclusive com chaves próprias quando essa opção estiver habilitada.

## Premissas

- O backend FastAPI publicado no Fly.io continua sendo a autoridade de autenticação.
- O banco PostgreSQL atual pode receber migrações Alembic sem recriação de tabelas.
- O login `admin` já existe ou será promovido por uma migração controlada; nenhuma senha será embutida no código.
- HTTPS permanece obrigatório.
- A carga atual cabe em uma instância, mas o estado de roteamento será persistido para não depender da memória de um processo.
- MFA será preparado como reforço posterior; a primeira entrega exige senha forte, RBAC, limitação de tentativas, sessões revogáveis e auditoria.

## Alternativas consideradas

### 1. Manter o pool completo no celular

Rejeitada. Facilita a operação remota, mas expõe todos os segredos a extração do APK, backup, dispositivo comprometido e logs.

### 2. Login administrativo separado por segredo estático

Rejeitada. Um token ou senha especial embutido no aplicativo recria o bypass atual e não oferece revogação individual.

### 3. RBAC no backend com cofre e gateway de IA

Escolhida. O proprietário continua administrando remotamente, enquanto o backend autentica a conta, aplica autorização por função, cifra as chaves e executa os testes e as chamadas aos provedores.

## Design final

### Identidade e autorização

`users.role` terá valores permitidos `user` e `admin`, com `user` como padrão. O JWT continuará curto e revogável por `auth_version`; a autorização consultará o usuário no banco em cada operação administrativa. O login `admin` não terá tratamento especial no Flutter. A promoção inicial será feita pela variável de implantação `ADMIN_LOGIN_ID`, sem senha padrão e sem criação automática de conta.

O endpoint `/auth/me` e a resposta de login incluirão `role`. O Flutter liberará o painel apenas quando `role == admin`, mas essa verificação será somente de experiência de uso: todos os endpoints `/admin/*` também exigirão `require_admin` no backend.

### Cofre de chaves

Cada chave mestra será uma linha com provedor, rótulo, prioridade, estado ativo, segredo cifrado, sufixo mascarado, métricas de saúde e timestamps. O segredo será cifrado com a chave de aplicação e nunca aparecerá em respostas, logs ou auditoria.

O painel receberá somente `id`, `provider`, `label`, `priority`, `is_active`, `masked_key`, `health_status`, `failure_count`, `blocked_until`, `last_tested_at` e `last_error_code`. A chave em texto claro existirá apenas no corpo da criação ou rotação e será descartada pelo cliente após a resposta.

### AI Gateway

As rotas de quiz, simulado, perguntas abertas, plano e biblioteca solicitarão uma credencial ao gateway. A ordem será:

1. chave própria válida do usuário, quando configurada para o provedor solicitado;
2. pool mestre do servidor para o provedor solicitado;
3. fallback para os demais provedores ativos.

Falhas de autenticação, cota e rate limit atualizarão o estado da chave no banco. Chaves bloqueadas serão ignoradas até `blocked_until`. Sucesso reduzirá falhas e atualizará a saúde. O aplicativo não manterá circuit breaker de infraestrutura.

### Operações administrativas

- `GET /admin/ai-keys`: lista metadados mascarados.
- `POST /admin/ai-keys`: cria uma chave.
- `PATCH /admin/ai-keys/{id}`: altera rótulo, prioridade e estado ou rotaciona o segredo.
- `DELETE /admin/ai-keys/{id}`: remove a chave.
- `POST /admin/ai-keys/{id}/test`: testa no servidor e persiste a saúde.
- `GET /admin/ai-audit`: consulta eventos recentes sem conteúdo secreto.

As mutações terão rate limit estrito, validação por allowlist de provedor e auditoria com usuário, ação, alvo, resultado, IP e instante.

## Estratégia de testes

- Backend: usuário comum recebe `403`; admin recebe lista mascarada; segredo nunca aparece; criação cifra; teste atualiza saúde; gateway ignora chave bloqueada e faz fallback.
- Flutter: qualquer senha não cria admin local; falha de rede falha fechada; função `admin` vem da API; rota administrativa é bloqueada para usuário comum; serviço não persiste pool nem chave mestra.
- Regressão: geração usa o gateway e não acusa ausência de chave local quando existe pool do servidor.
- Release: análise estática, testes direcionados, suíte completa, migração em banco de teste, smoke de autenticação/geração, build universal, assinatura e hash.

## Registro de decisões

| Decisão | Alternativas | Motivo |
|---|---|---|
| Manter o login `admin` | Remover administração móvel | Preserva a operação remota exigida pelo proprietário. |
| Autorizar por `users.role` no servidor | Inferir pelo nome do login | Evita promoção acidental e permite revogação. |
| Não incluir `role` como única fonte no cliente | Confiar somente no JWT/UI | O backend precisa impedir acesso mesmo com cliente adulterado. |
| Guardar chaves apenas cifradas no backend | Secure Storage do Android | O dispositivo não deve possuir o pool completo. |
| Executar teste de chave no servidor | Chamar provedor pelo celular | Evita exposição e testa o mesmo caminho da produção. |
| Persistir saúde e bloqueio no banco | Circuit breaker em memória | O estado precisa sobreviver a reinícios e valer para todos os dispositivos. |
| Usar a fonte extraída da implantação como baseline inicial | Partir do clone antigo | Impede reintroduzir regressões ausentes da produção. |
