# Backend Baseline

Esta e a baseline oficial de backend para o projeto `Quiz Vance Redesign`.

## Backend oficial

- URL base: `https://quiz-vance-redesign-backend.fly.dev`
- Provedor: `Fly.io`
- Regiao esperada: `GRU`

## Topologia esperada

- Exatamente `1` app de backend ativo para este projeto
- Exatamente `1` machine ativa para o backend
- Exatamente `1` banco em uso por este backend

## Configuracao de custo esperada

Para reduzir custo e manter disponibilidade sob demanda, a configuracao esperada no Fly e:

- `auto_stop_machines = "stop"`
- `auto_start_machines = true`
- `min_machines_running = 0`

## Regras operacionais

- Qualquer URL diferente da URL base acima deve ser tratada como suspeita ate confirmacao explicita.
- Qualquer segundo app de backend no Fly deve ser tratado como excedente ate prova em contrario.
- Qualquer custo acima do esperado deve ser investigado primeiro em:
  - `2+ machines` ativas
  - volume/database excedente
  - snapshots de volume
  - health checks excessivos

## Fonte de verdade no app

O app local usa esta baseline pelos seguintes pontos:

- `backend_url.txt`
- `lib/core/config/app_config.dart`
- scripts de execucao e build que consomem `BACKEND_URL`

## Procedimento ao trocar backend

Se a URL do backend mudar:

1. Atualizar `backend_url.txt`
2. Validar `/health`
3. Validar `/health/ready`
4. Gerar novo build do app
5. Registrar a nova URL neste arquivo
