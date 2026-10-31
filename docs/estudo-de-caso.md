# Estudo de caso: registrar despesas pelo Telegram, para vários usuários, sem service-role key

## Contexto

O CIFRO é um app de finanças pessoais (Next.js 16 e Supabase). Registrar um gasto exige abrir o app, escolher conta, categoria e valor. A ideia foi aceitar uma mensagem como `almoço 32,50` em um bot do Telegram e fazer o resto sozinho.

O projeto já tinha três regras que moldaram a solução:

1. **Custo zero** na fase de validação: Telegram, n8n e Supabase no plano gratuito.
2. **Sem service-role key** fora do banco. O app só usa a chave pública, e o isolamento entre usuários depende de RLS. Uma chave de serviço em uma automação seria um acesso total guardado em um lugar fácil de vazar.
3. **Nenhum número do app pode divergir.** Valores são centavos inteiros, e o app recusa carregar um estado que não passe na sua validação. Um registro inválido gravado pela automação poderia trancar o usuário para fora dos próprios dados.

Nada aqui mede uso real. O projeto foi validado com contas de teste e com o uso do próprio autor.

## Arquitetura

O desenho está no [README](../README.md#arquitetura). Em uma frase: o n8n recebe o webhook do Telegram e chama funções do Postgres por HTTP, e **o banco** decide de quem é cada mensagem e se ela pode ser gravada. O n8n não guarda estado nem regra de negócio.

## Decisões

### 1. Uma escrita granular, em vez de reaproveitar o salvamento do app

O app salva enviando o estado financeiro inteiro para `save_finance_state`, que reescreve os dados do usuário sob um controle de revisão. Reaproveitar isso na automação obrigaria o n8n a baixar tudo, acrescentar uma despesa e devolver, correndo o risco de conflito com o app aberto.

A automação ganhou uma função própria, `capture_telegram_expense`, que insere um único evento e um único lançamento na conta, e incrementa a revisão do usuário. Se o app estiver aberto, ele recebe um conflito (`40001`) no próximo salvamento e recarrega, em vez de apagar a despesa do bot em silêncio. Há testes para os dois lados: a aba desatualizada é recusada e um salvamento com a revisão atual preserva as despesas do bot.

### 2. Autenticar a automação sem chave de serviço

A função do bot é chamada pela API pública, com a chave pública do projeto. O que a distingue de qualquer outro chamador é um **segredo único**, enviado no cabeçalho `x-cifro-bot-secret` e lido no banco por `current_setting('request.headers')`. O banco guarda só o hash SHA-256.

- Sem segredo configurado, tudo é recusado.
- Trocar o segredo (`rotate_telegram_bot_secret`) invalida o anterior na hora.
- As funções são `security definer` com `search_path` vazio, com `revoke` de `public`, `anon` e `authenticated` e um `grant` explícito só para quem precisa.

O raio de dano de um vazamento é limitado pelo que a função faz: ela só **insere** uma despesa em um chat já conectado. Não lê, não altera e não apaga nada.

### 3. Provar de quem é o chat

A primeira versão (migration `0001`) pedia que o usuário digitasse o id do chat e guardava um segredo por usuário, colado no nó de código do n8n. Isso tinha três problemas:

- **Não provava posse:** qualquer pessoa podia cadastrar o chat id de outra.
- **O segredo ficava dentro do workflow**, onde aparece em exportações e em logs.
- **Não escalava:** um segredo por pessoa dentro de um fluxo.

A migration `0004` troca tudo por um **link de uso único**. O app gera um token (15 minutos, guardado como hash, um pendente por usuário), a pessoa o abre no Telegram, e o bot manda ao banco o token e o chat id que o **próprio Telegram** informou. O vínculo só nasce quando os dois chegam juntos. Um chat já ligado a outra conta não pode ser tomado.

### 4. Idempotência sem tabela extra

O Telegram e o n8n podem reenviar a mesma mensagem. O id do evento é derivado de `md5(chat_id:message_id)`, e a inserção usa `on conflict do nothing`. O reenvio responde `duplicate: true` e nada é gravado de novo. O mesmo `message_id` em chats diferentes não colide.

Isso evita uma tabela de deduplicação. O custo é que, se o usuário apagar a despesa no app e a mesma mensagem for reprocessada depois, ela é gravada de novo. Na prática, reenvios acontecem em segundos, mas o limite existe.

### 5. Integridade verificada dentro da função

O schema valida cada despesa com gatilhos de restrição adiados: o evento é inserido, depois o lançamento, e a regra "um evento de despesa tem exatamente um lançamento negativo" só é conferida no `commit`. Com a função chamada pelo papel `anon`, essa verificação adiada rodaria **com as permissões de quem chamou**, que não pode executar o validador.

A solução é `set constraints all immediate` logo depois das duas inserções, para as verificações rodarem sob o papel da própria função. O [teste de controle](../db/tests/60_control.sql) reconstrói a função sem essa linha e mostra que a captura parece funcionar e só falha no commit com `permission denied`. Ele existe para a suíte avisar se alguém remover a linha.

### 6. Categoria sem LLM

A categoria sai de uma ordem fixa: o nome de uma categoria do próprio usuário na descrição, depois palavras comuns ligadas ao ícone da categoria, e por fim a categoria "Outros". É determinístico, de graça, testável e corrigível no app. Um modelo de linguagem seria uma melhoria opcional, mas traria custo, latência e saídas que uma suíte de testes não consegue fixar.

### 7. Recusas de negócio não são exceções

Valor inválido, chat desconectado e conta sem saldo inicial voltam como `{ "ok": false, "message": "..." }` com HTTP 200. O n8n só precisa repassar a mensagem ao usuário. Falhas de rede e do servidor seguem pela saída de erro do nó HTTP e chegam à mesma mensagem de falha. A pessoa nunca fica sem resposta, e a ausência de resposta significa que nada foi gravado.

## Modelo de ameaças

| Ameaça | Mitigação | Onde é provada |
| --- | --- | --- |
| Alguém chama a função do bot sem ser o bot | Segredo no cabeçalho, comparado por hash | grupo `AUTH` |
| Mensagem forjada chega ao n8n | O gatilho do Telegram recusa requisições sem o segredo do webhook (403). Confirmado lendo o código do nó; **não** coberto pela suíte | leitura do código do n8n |
| Cadastrar o chat de outra pessoa | O vínculo exige o token de uma conta logada e o chat id vindo do Telegram | `LINK` |
| Reuso ou vazamento do link | Uso único, 15 minutos, um pendente por usuário, só o hash guardado | `LINK` |
| Tomar um chat já conectado | Recusado enquanto o outro usuário não desconectar | `LINK` |
| Usuário logado chamando as funções do bot | `revoke` explícito; só `anon` executa as duas funções do bot | `PRIV` |
| Reenvio de mensagem | Id do evento determinístico | `IDEM` |
| Dados de um usuário aparecendo em outro | Dono definido pelo chat; RLS nas tabelas | `ISO` |
| Segredo do bot vazado | Troca com um comando; a função só insere | `CLEAN` |
| Funções internas expostas pelas permissões padrão do Supabase | `revoke` explícito | `PRIV` |

## Como foi testado

A suíte é SQL puro, executado em uma única sessão do `psql`. Um pequeno [harness](../db/tests/00_harness.sql) oferece `t.eq`, `t.has` e `t.raises`. Falhas esperadas são afirmadas com `t.raises`, então qualquer erro não previsto interrompe a execução em vez de passar em silêncio.

- **101 cenários em 13 grupos**, rodando em cerca de 20 segundos com `bash scripts/run-tests.sh`.
- As chamadas são feitas sob os papéis reais (`anon`, `authenticated`, `supabase_auth_admin`), porque boa parte dos erros que importam aqui são de permissão.
- **Teste de controle** da integridade, descrito acima.
- **Verificação por mutação, feita à mão:** removi `set constraints all immediate` da migration e a execução abortou com `permission denied`; troquei a autorização do bot para sempre verdadeira e 7 cenários falharam. Depois restaurei os arquivos. Isso não está automatizado.

O Postgres de teste não é o Supabase. Um [stub](../db/stub-supabase.sql) emula os papéis, `auth.uid()` e os privilégios padrão. Fora do que ele cobre, só o ambiente real responde.

## Erros e lições

- **Um segredo apareceu onde não devia.** No primeiro desenho, o segredo ficava no nó de código do workflow. Ao inspecionar o workflow durante o desenvolvimento, o valor apareceu em uma saída de terminal e teve de ser trocado. A correção estrutural foi tirá-lo do workflow: ele passou a viver em uma credencial do n8n e a trafegar em cabeçalho, e a função que o aceitava deixou de existir. Desde então, as leituras de workflows são filtradas, e o publicável passa por um sanitizador que recusa segredos.
- **`revoke ... from public` não basta no Supabase.** Funções novas em `public` podem ser concedidas direto aos papéis `anon` e `authenticated`, e essa concessão é separada da de `public`. Na emulação, o `anon` conseguia executar funções internas, como a que cria categorias padrão para um id qualquer. No projeto real, a consulta mostrou apenas `handle_new_user` e uma função que não vem das migrations do projeto, e a migration `0002` revogou a primeira por precaução. O hábito que ficou: listar o que o `anon` executa antes e depois de cada migration.
- **`set constraints` vale até o fim da transação.** Descobri ao escrever o teste de controle: duas capturas na mesma transação falham, porque a segunda já encontra o modo imediato e a verificação roda antes do lançamento existir. Com o PostgREST, cada chamada é uma transação, então não afeta o uso real, mas o teste precisou de uma transação para cada variante.
- **O import por linha de comando exige ids.** O workflow sanitizado, sem ids, falhava ao importar. O sanitizador agora gera ids estáveis para os nós.

## Limitações conhecidas

- **Hospedagem.** O n8n roda em um computador pessoal, atrás de um túnel temporário. Em uma ocasião o container parou e o bot ficou fora do ar sem aviso, porque ele não tem política de reinício. Para outras pessoas usarem, precisa de um servidor sempre ligado, endereço fixo e política de reinício.
- **Sem limite de envio.** O bot é público: qualquer pessoa pode mandar mensagens, e cada uma gera uma execução no n8n.
- **Segredo único.** Vale para todos os usuários. Trocar exige atualizar a credencial no n8n.
- **Categoria por palavra-chave.** Descrições sem palavra conhecida caem em "Outros".
- **Um chat privado por usuário.** Grupos são ignorados.
- **Sem teste automatizado do workflow** nem do webhook do Telegram. A suíte cobre o banco.
- **Escopo.** Não há separação entre finanças pessoais e de empresa, porque o app ainda não tem esse conceito.

## Próximos passos

1. Hospedar o n8n com endereço fixo e reinício automático.
2. Limitar envios por chat, antes de qualquer divulgação do bot.
3. Testar o workflow por contrato, com chamadas simuladas do Telegram e do Supabase.
4. Estudar o WhatsApp. A API oficial cobra pelas respostas do bot depois de uma cota gratuita, então o custo precisa entrar na decisão. O banco já guarda o vínculo por chat, e um novo canal exigiria uma tabela de vínculos por canal e um novo fluxo no n8n.
