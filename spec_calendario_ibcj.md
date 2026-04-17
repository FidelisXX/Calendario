# 📋 Especificação do Sistema
## Calendário de Eventos — Igreja Batista Central do Jordão (IBCJ)

---

## 1. Visão Geral

Aplicativo web simples destinado à secretaria da IBCJ para gerenciamento do calendário anual de eventos da igreja. O sistema deve permitir cadastrar, visualizar, editar e excluir eventos, com detecção automática de conflitos de datas e sugestão de datas alternativas.

---

## 2. Perfis de Usuário

| Perfil | Permissões |
|---|---|
| **Secretária** | Criar, editar, excluir e visualizar todos os eventos |
| **Membro (opcional)** | Somente visualizar o calendário |

> Na versão inicial, o sistema pode ter apenas um usuário (a secretária), com login por e-mail e senha.

---

## 3. Funcionalidades

### 3.1 Cadastro de Evento
A secretária poderá cadastrar um evento informando:

- **Nome do evento** *(obrigatório)*
- **Data** *(obrigatório)*
- **Horário de início e fim** *(opcional)*
- **Categoria** *(ex: Culto, Celebração da Ceia, Reunião, Acampamento, Aniversário, EB, Jovens, Outro)*
- **Descrição / observações** *(opcional)*
- **Recorrência** *(opcional: único, mensal, anual)*

### 3.2 Detecção de Conflito de Data
Ao selecionar uma data para novo evento:

1. O sistema verifica se já existe algum evento cadastrado nessa data.
2. Se houver conflito, exibe um **alerta visual** com a lista dos eventos já existentes naquele dia.
3. O sistema sugere automaticamente as **3 datas mais próximas livres** (anteriores e posteriores), que a secretária pode selecionar com um clique.
4. A secretária pode optar por manter a data original mesmo com conflito (eventos simultâneos permitidos).

**Exemplo de alerta:**
> ⚠️ *"Esta data já possui o evento: Celebração da Ceia. Datas próximas disponíveis: 03/01, 05/01, 06/01."*

### 3.3 Visualização do Calendário
- **Visão mensal** (padrão): grade com todos os meses, semelhante ao calendário da imagem de referência.
- **Visão de lista**: lista cronológica dos eventos do mês ou do ano.
- Eventos exibidos com cores por categoria (ex: Culto = roxo, Ceia = dourado, Jovens = azul).
- Ao clicar em um dia com evento, abre um painel lateral com os detalhes.

### 3.4 Edição e Exclusão de Eventos
- Editar qualquer campo do evento.
- Ao editar a data, o sistema repete a verificação de conflito.
- Excluir evento com confirmação ("Tem certeza que deseja excluir?").

### 3.5 Exportação
- Exportar o calendário do ano em **PDF** no layout similar ao da imagem de referência (com logo da IBCJ).
- Exportar lista de eventos em **Excel/CSV**.

---

## 4. Regras de Negócio

| # | Regra |
|---|---|
| RN01 | Uma data pode ter mais de um evento (sem bloqueio), mas o sistema sempre alertará sobre conflitos. |
| RN02 | Datas sugeridas como "livres" são aquelas sem nenhum evento cadastrado. |
| RN03 | O calendário exibe por padrão o ano corrente, com navegação para anos anteriores e futuros. |
| RN04 | Eventos com recorrência anual (ex: Celebração da Ceia toda primeira semana do mês) devem ser gerados automaticamente. |
| RN05 | O sistema deve manter histórico de eventos de anos anteriores. |

---

## 5. Telas do Sistema

### Tela 1 — Login
- Campo e-mail e senha
- Botão "Entrar"

### Tela 2 — Calendário (Tela Principal)
- Cabeçalho com logo da IBCJ e ano selecionado
- Grade com os 12 meses
- Botão "+ Novo Evento"
- Filtro por categoria
- Botão "Exportar PDF" e "Exportar Excel"

### Tela 3 — Cadastro/Edição de Evento
- Formulário com os campos do item 3.1
- Alerta de conflito (se houver) com sugestão de datas
- Botões "Salvar" e "Cancelar"

### Tela 4 — Detalhe do Dia
- Lista de eventos daquele dia
- Botão de editar e excluir por evento
- Botão "+ Adicionar evento neste dia"

---

## 6. Requisitos Não Funcionais

- **Plataforma:** Web (responsivo para desktop e celular)
- **Tecnologia sugerida:** Mendix (low-code) ou React + backend simples
- **Autenticação:** Login com e-mail e senha, sessão com expiração
- **Armazenamento:** Banco de dados relacional (dados persistidos)
- **Idioma:** Português (Brasil)
- **Acessibilidade:** Fontes legíveis, bom contraste de cores

---

## 7. Identidade Visual

- Cores principais: **Azul escuro (navy), Dourado e Branco** (baseado no calendário de referência)
- Logo da IBCJ presente no cabeçalho e no PDF exportado
- Tipografia elegante, semelhante ao material impresso da igreja

---

## 8. Fora do Escopo (Versão Inicial)

- Envio de notificações/e-mails para membros
- App mobile nativo (iOS/Android)
- Integração com Google Calendar
- Controle de presença em eventos

> Esses itens podem ser adicionados em versões futuras.

---

## 9. Critérios de Aceite

- [ ] A secretária consegue cadastrar um evento em menos de 1 minuto
- [ ] Ao selecionar uma data com conflito, o alerta aparece imediatamente
- [ ] As sugestões de datas livres são exibidas automaticamente
- [ ] O calendário anual pode ser exportado em PDF com identidade visual da IBCJ
- [ ] O sistema funciona corretamente em navegadores Chrome, Edge e Firefox

---

*Documento elaborado para a Igreja Batista Central do Jordão — versão 1.0*
