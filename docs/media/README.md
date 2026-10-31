# Mídia do repositório

## O que está aqui

| Arquivo | O que é |
| --- | --- |
| `conectar.gif` | **Simulação** do fluxo de vínculo, com a interface real do CIFRO, dados fictícios e um celular simulado |
| `registrar.gif` | **Simulação** de duas despesas entrando pelo bot e aparecendo em Lançamentos |
| `workflow.gif` | Diagrama animado gerado do workflow exportado, **não** uma captura do n8n |
| `src/` | O gerador dos GIFs ([como funciona](src/README.md)) |

Nenhum deles é uma gravação do bot em uso, e cada quadro traz uma legenda dizendo isso. O README principal repete o aviso.

## Trocar por gravações reais

Quando o n8n estiver hospedado e o bot estável, gravações reais valem mais do que simulações. O roteiro abaixo serve para isso. Se trocar, apague o aviso de "simulação" do README e das legendas.

### Antes de gravar

Use uma **conta de teste com dados fictícios**, nunca a sua. Confira, em cada quadro:

- [ ] nenhum e-mail pessoal na tela;
- [ ] nenhum chat id do Telegram visível (feche o painel "Conectado" ou borre o número);
- [ ] nenhuma URL do túnel (`trycloudflare.com`) ou do projeto Supabase;
- [ ] o n8n sem credenciais abertas, sem o nó **Gravar no Cifro** em modo de edição e sem o JSON do workflow;
- [ ] o nome de usuário do bot escondido, enquanto o bot não tiver limite de envio;
- [ ] nenhuma notificação de outro aplicativo.

### GIF de conectar (até 20 s)

1. Perfil → Registrar pelo Telegram → **Conectar Telegram**.
2. Quadro "Falta um passo" → **Abrir no Telegram**.
3. No Telegram, toque em **Iniciar** e mostre a resposta "Telegram conectado".
4. Volte ao Perfil: o selo muda sozinho para **Conectado**.

### GIF de registrar (até 25 s)

1. No Telegram, envie `almoço 32,50` e mostre a confirmação com conta e categoria.
2. Envie `uber 18,90`.
3. Abra Lançamentos no app e mostre as duas despesas, com a categoria certa.

### GIF do workflow (até 15 s)

Canvas do n8n com o fluxo inteiro à vista. Passe o mouse pelos ramos de erro. Não abra nenhum nó que mostre credencial.

### Dicas

- Mantenha cada GIF abaixo de 5 MB, em 800 px de largura ou menos.
