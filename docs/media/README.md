# Roteiro das gravações

Os GIFs e o vídeo ainda não existem. Grave, confira a lista de privacidade abaixo e só então adicione os arquivos a esta pasta.

## Antes de gravar

Use uma **conta de teste com dados fictícios**, nunca a sua. Confira, em cada quadro:

- [ ] nenhum e-mail pessoal na tela;
- [ ] nenhum chat id do Telegram visível (feche o painel "Conectado" ou borre o número);
- [ ] nenhuma URL do túnel (`trycloudflare.com`) ou do projeto Supabase;
- [ ] o n8n sem credenciais abertas, sem o nó **Gravar no Cifro** em modo de edição e sem o JSON do workflow;
- [ ] o nome de usuário do bot, se o bot ainda não tiver limite de envio: prefira esconder;
- [ ] nenhuma notificação de outro aplicativo.

## GIF 1: `conectar.gif` (até 20 s)

1. Perfil → Registrar pelo Telegram → **Conectar Telegram**.
2. Quadro "Falta um passo" → **Abrir no Telegram**.
3. No Telegram, toque em **Iniciar** e mostre a resposta "Telegram conectado".
4. Volte ao Perfil: o selo muda sozinho para **Conectado**.

## GIF 2: `registrar.gif` (até 25 s)

1. No Telegram, envie `almoço 32,50` e mostre a confirmação com conta e categoria.
2. Envie `uber 18,90`.
3. Abra Lançamentos no app e mostre as duas despesas, com a categoria certa.
4. Opcional: reenvie a mesma mensagem pelo encaminhamento e mostre que nada duplica.

## GIF 3: `workflow.gif` (até 15 s)

Canvas do n8n com o fluxo inteiro à vista. Passe o mouse pelos ramos de erro. Não abra nenhum nó que mostre credencial.

## Vídeo (opcional, 60 a 90 s)

Junte os três, com uma narração curta: o problema, o vínculo por link de uso único, uma despesa entrando e a suíte de testes passando no terminal (`bash scripts/run-tests.sh`).

## Dicas

- Mantenha cada GIF abaixo de 5 MB, em 800 px de largura ou menos.
- Depois de adicionar os arquivos, descomente as duas imagens no `README.md`.
