# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Visão geral

Sistema web de gestão de igrejas — originalmente só da IBCJ, agora multi-igreja (calendário de eventos, liturgias, agenda semanal, escala diaconal, ministérios, relatórios financeiros/de culto, membros e gabinete pastoral). Interface e textos em **português (Brasil)**. A especificação original (só o módulo de calendário) está em [spec_calendario_ibcj.md](spec_calendario_ibcj.md); o sistema cresceu bem além dela.

## Estrutura e execução

- **Todo o app é um único arquivo**: [gestao-ibcj.html](gestao-ibcj.html) (~6.3k linhas) — CSS no `<style>` do topo, markup no meio, JS puro (sem framework, sem build) num `<script>` a partir de ~linha 1255.
- **Não há build, lint, testes nem package.json.** Para rodar localmente, sirva a pasta estaticamente (VS Code Live Server, porta 5501 em [.vscode/settings.json](.vscode/settings.json)) e abra `gestao-ibcj.html`.
- **Deploy**: Vercel, estático. [vercel.json](vercel.json) reescreve `/` → `/gestao-ibcj.html`. [ads.txt](ads.txt) é do Google AdSense (o script do AdSense é carregado no HTML).
- Dependências via CDN: `@supabase/supabase-js@2` e `@emailjs/browser@4`.

## Backend: Supabase

- Cliente criado direto no HTML (`const DB = supabase.createClient(...)`) com a anon key. Todas as leituras/escritas são `DB.from('ibcj_*')...` chamadas do navegador.
- [ibcj_database.sql](ibcj_database.sql) está **desatualizado** em relação ao banco real (faltam, p.ex., `ibcj_membros.tipo`, `ibcj_liturgias.event_id`, a tabela legada `ibcj_notas` e tudo das migrações). Esquema original: tabelas `ibcj_users`, `ibcj_events`, `ibcj_liturgias`, `ibcj_agenda`, `ibcj_diaconal`, `ibcj_ministerios`, `ibcj_ministerio_members`, `ibcj_financial_reports`, `ibcj_registros`, `ibcj_gabinete_notes`, `ibcj_membros`, `ibcj_reuniao_admin_reports`, `ibcj_culto_reports` + bucket de Storage público `comprovantes`). Ao adicionar/alterar colunas, atualize também esse script.
- IDs são `TEXT` gerados no cliente por `uid()`; datas são guardadas como texto ISO `YYYY-MM-DD` (a UI exibe/aceita `dd/mm/aaaa` via `isoToBR`/`brToISO`/`maskDateInput`). Campos estruturados (itens de liturgia, dias da agenda, votações, itens financeiros) ficam em colunas `JSONB`.
- Eventos têm mapeamento de nomes entre JS e banco em `evtToDb`/`evtFromDb` (`start`↔`start_time`, `cat`↔`category`, `desc`↔`description`, `rec`↔`recurrence`). Os valores de recorrência usados pelo código são `unique | weekly | monthly | annual` (o comentário no SQL está desatualizado). Recorrências são materializadas como linhas separadas no momento de salvar (`saveEvt`).

## Multi-igreja

Cada igreja é uma linha em `igrejas` (`tag`, `nome`, `logo_url`). Secretaria/líder pertencem a uma igreja (`profiles.igreja_id`); pastor/admin enxergam todas e trocam a igreja exibida pelo seletor do cabeçalho (`trocarIgreja`, salva em `localStorage['ibcj_igreja']` e recarrega a página). `S.igrejaId` é a igreja exibida: **toda consulta filtra `.eq('igreja_id', S.igrejaId)` e todo insert/upsert leva `igreja_id`** (helper `comIgreja(rec)`). Tabelas filhas de ministério/evento recebem `igreja_id` por trigger no banco.

Scripts em [migracoes/](migracoes/), na ordem: `01_estrutura_multi_igreja.sql` → `importar_usuarios.mjs` (service_role via env, `--dry-run`, `--pular=`) → `02a_politicas_perfis_igrejas.sql` (seguro com o front antigo) → `02_seguranca_rls.sql` (**quebra o front antigo: só junto com o deploy do novo**). Toda tabela nova precisa de `igreja_id` + políticas no padrão da 02 (funções `eh_global`, `eh_gestor`, `pode_acessar`, `acessa_ministerio`).

## Autenticação e permissões (importante)

- **Supabase Auth** (`signInWithPassword`, `signUp`, `resetPasswordForEmail` + `verifyOtp` para o código de recuperação). Após login, `entrar()` carrega o perfil de `profiles` e as igrejas; usuário sem igreja (e não pastor/admin) vê o painel "aguardando liberação". `ibcj_users` é legado (renomeada para `ibcj_users_legacy` pela migração 02).
- O cadastro sempre cria perfil `lider` sem igreja (trigger no banco); papel e igreja só são alterados por pastor/admin em "Usuários e Igrejas" (`openAdminUsers`), e o trigger `proteger_perfil` impede o resto. Só admin concede/remove o papel admin.
- Após a migração 02, o acesso é garantido por RLS no banco; os helpers de role no JS (`isAdmin`, `isGlobal`, `hasRole`, `canDelete`, `canApprove`, `canSeeGabinete`, `canSeeNotes`, `canEditRegistros`) controlam só a UI — mantenha os dois alinhados.
- Roles: `admin | pastor | secretaria | lider`.
- Comprovantes financeiros: bucket privado `comprovantes`, caminho `<igreja_id>/<arquivo>`; o banco guarda o caminho e a tela usa links assinados (`assinarComprovantes`, `caminhoComprovante`).
- **Fluxo de aprovação**: conteúdo criado por `lider` (eventos, liturgias, diaconal, agenda) é salvo com `status: 'pendente'` e só aparece para outros após aprovação por secretaria/pastor/admin (painel de notificações: `renderNotifPanel`, `approve*`/`reject*`). `lider` só vê/edita os próprios pendentes. Mantenha esse padrão em novos tipos de registro.

## Organização do JS

- Estado global em `currentUser` e no objeto `S` (ano, eventos, view, filtro, liturgias, agenda, ministérios etc.); a UI é re-renderizada por funções `render*` que montam HTML via strings/DOM. Sempre escape conteúdo do usuário com `escH()` ao interpolar em HTML.
- Abas principais via `switchTab('calendar'|'registros'|'pastoral'|'membros')`; subabas via `switchPastoralSub`/`switchSecretariaSub`. Há navegação mobile separada (`openMobDrawer`, `updateMobNav`, `updateMobTabStrip`) que precisa ser atualizada junto ao adicionar abas.
- Modais seguem o padrão `open*Modal` / `close*Modal` alternando a classe `on` em um `#*-overlay`; documentos (liturgia, agenda, diaconal, relatórios) têm `build*HTML` usado tanto para preview quanto para impressão (`print*`, que abre janela e chama `window.print()`). Exportação do calendário em PDF é `window.print()` com regras `@media print`; CSV via `doCSV`/`export*CSV`.
- Categorias de evento e suas cores ficam no objeto `CATS`.
- Conflito de datas: ao escolher data, `checkCflt` alerta eventos existentes e `freeDates` sugere datas livres próximas (múltiplos eventos no mesmo dia são permitidos).

## Dados pessoais

O sistema armazena dados pessoais (tabela `ibcj_membros`: nome, telefone, e-mail, endereço, data de nascimento; usuários com senha) e notas pastorais privadas. Caso o projeto envolva dados pessoais ou dados pessoais sensíveis, comunique ao time de Segurança da Informação através do e-mail seginfo@gcb.com.br.
