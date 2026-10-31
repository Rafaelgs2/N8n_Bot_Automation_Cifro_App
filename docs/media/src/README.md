# Como os GIFs foram gerados

Os GIFs do [README](../../../README.md) são **simulações**: a interface é a do CIFRO, os dados são fictícios (o `demoState` do próprio app) e o Telegram é um celular desenhado com CSS. Este diretório guarda o gerador para que isso seja verificável, não para ser reutilizado como está.

## Peças

| Arquivo | Papel |
| --- | --- |
| `scenes-page.tsx` | Página do Next.js que monta as três cenas com os componentes reais do app (`TelegramLink`, `TransactionRows`) e uma API de roteiro (`window.scene`) |
| `capture.mjs` | Abre o Chrome sem janela, toca o roteiro de cada cena e grava os quadros pelo protocolo do DevTools. Sem dependências: o Node já traz `WebSocket` |
| `assemble.py` | Junta os quadros em um GIF com a paleta única e a duração real de cada quadro. Precisa do Pillow |

## Rodar

1. No repositório do CIFRO, copie `scenes-page.tsx` para `app/media-scenes/page.tsx` e rode `npm run dev` (porta 5173).
2. Para cada cena (`connect`, `register`, `workflow`):

   ```bash
   node capture.mjs connect ./frames
   python assemble.py connect ./frames conectar.gif 800 15 160
   ```

3. Apague `app/media-scenes` do app. A página não deve ser commitada lá.

Os argumentos do `assemble.py` são, em ordem: cena, pasta dos quadros, arquivo de saída, largura, quadros por segundo e número de cores.

## O que é simulado e o que é real

- **Real:** os componentes e o CSS do app, a lógica de conexão do bloco do Telegram (consulta o status a cada 3 segundos) e a lista de Lançamentos.
- **Simulado:** a API (uma função `fetch` falsa), o Telegram, o clique do cursor e os dados.
- **O diagrama do workflow** usa as posições e as ligações do workflow exportado, mas é desenhado em SVG. Não é o canvas do n8n.
