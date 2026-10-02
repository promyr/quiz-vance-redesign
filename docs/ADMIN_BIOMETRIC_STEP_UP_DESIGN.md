# Confirmação biométrica de ações administrativas

## Resumo do entendimento

- Administradores devem poder confirmar ações sensíveis com a digital.
- A senha administrativa permanece disponível como alternativa.
- A senha não pode ser persistida para viabilizar a biometria.
- A confirmação local precisa produzir uma prova verificável pelo servidor.
- Cada autorização deve valer para uma ação e um escopo específicos.
- Logout, redefinição ou troca de senha invalidam a credencial cadastrada.
- A primeira ativação da biometria exige a senha administrativa atual.

## Premissas

- A primeira plataforma atendida é Android 23 ou superior.
- O dispositivo possui biometria cadastrada e Android Keystore funcional.
- Toda comunicação entre aplicativo e backend ocorre por HTTPS.
- O administrador já possui uma sessão JWT válida no momento da operação.
- Desktop continua usando senha, pois o cofre biométrico adotado é habilitado
  somente no Android.

## Arquitetura

O aplicativo gera um par de chaves Ed25519 exclusivo do aparelho. A chave
privada é armazenada em um arquivo criptografado pelo Android Keystore e só
pode ser lida após a confirmação biométrica. O backend recebe apenas a chave
pública, vinculada ao administrador e à versão atual de autenticação da conta.

Para confirmar uma ação, o backend cria um desafio aleatório com validade de
90 segundos e vinculado ao escopo solicitado. A digital libera a chave privada,
o aplicativo assina o desafio e o servidor valida a assinatura. Uma assinatura
válida produz um token opaco de step-up com validade de 120 segundos. O token é
armazenado no servidor somente como SHA-256, aceita exatamente um uso e apenas
no escopo para o qual foi emitido.

## Fluxos

### Ativação

1. Administrador informa a senha atual.
2. Aplicativo gera o par Ed25519 no aparelho.
3. Chave privada é gravada no cofre biométrico.
4. Chave pública e identificador do aparelho são enviados ao backend.
5. Backend valida senha, função administrativa e registra a credencial.

### Confirmação

1. Aplicativo solicita desafio para um escopo administrativo.
2. Android apresenta a tela nativa de biometria.
3. Aplicativo assina o desafio com a chave protegida.
4. Backend valida assinatura, prazo, usuário, versão da sessão e escopo.
5. Backend emite um token de uso único.
6. A operação consome o token de forma transacional.

### Fallback

Se a biometria estiver indisponível, for cancelada ou a credencial tiver
expirado, o aplicativo solicita a senha e mantém o fluxo anterior.

## Tratamento de erros

- Credencial ausente ou invalidada: oferecer senha e permitir novo cadastro.
- Biometria cancelada: abrir confirmação por senha sem bloquear a operação.
- Desafio vencido ou já usado: recusar e exigir nova confirmação.
- Token usado, vencido ou com escopo diferente: recusar com HTTP 401.
- Assinatura inválida: consumir o desafio e registrar falha na auditoria.
- Troca de senha ou logout: a mudança de `auth_version` invalida o cadastro.

## Critérios de validação

- Nenhuma senha ou chave privada aparece em payload, log ou banco do servidor.
- Teste automatizado comprova bloqueio de replay e troca de escopo.
- Teste automatizado comprova que a senha é transmitida sem alteração.
- Reordenação de chaves é uma única operação atômica.
- Flutter Analyze, testes Flutter, Pytest e Ruff passam sem falhas.
- APK release instala e abre em Android com e sem biometria cadastrada.

## Registro de decisões

1. **Ed25519 em vez de senha no cofre:** evita persistir a credencial principal
   da conta e permite verificação assimétrica no servidor.
2. **Android Keystore via `biometric_storage`:** oferece proteção biométrica
   nativa e invalidação conforme a política biométrica do dispositivo.
3. **Token opaco de uso único:** reduz replay e evita expor estado sensível no
   cliente.
4. **Escopo obrigatório:** uma autorização para testar uma chave não pode
   cadastrar, excluir, ativar ou reordenar chaves.
5. **Senha como fallback:** preserva acesso administrativo em aparelhos sem
   sensor, com sensor bloqueado ou após alteração da conta.
6. **Reordenação atômica:** substitui múltiplos PATCH por um endpoint único,
   permitindo uma confirmação biométrica para a operação completa.
