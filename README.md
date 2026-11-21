# Alertas de servidor no celular com o HLG Notify (grátis, Android)

Para quem quer ser avisado quando algo acontece no servidor, no site ou num script, sem depender de e-mail (que cai no spam e ninguém vê na hora). O aviso chega como notificação no celular, em cinco níveis.

Documentação oficial: https://notify.hlgcloud.com.br/docs.html

## O que você precisa
- Um celular Android (o app ainda não existe para iPhone).
- Um computador ou servidor com terminal (Linux, macOS ou Windows com `curl`). A função do passo 6 precisa de `bash`.
- Nenhuma conta: o HLG Notify não pede cadastro.

## 1. Criar o canal
1. Abra https://notify.hlgcloud.com.br e toque em **Criar meu canal**.
2. Você recebe na hora um **código do canal** (parecido com `hlg-7ad4p7x7`), um **QR Code** e dois tokens.
3. **Guarde agora o token de publicação (publish token).** Ele aparece uma única vez e não pode ser recuperado.

| Item | É segredo? | Para que serve |
|---|---|---|
| Código do canal | Não | Endereço do canal |
| Token de inscrição (enroll), dentro do QR | Não | Só coloca um aparelho no canal, pode ser compartilhado |
| Token de publicação (publish) | **Sim, trate como senha** | Manda avisos, vê os aparelhos e apaga o histórico |

Para convidar outras pessoas, envie só o arquivo de **convite** (QR). O arquivo de **credenciais admin** é só seu.

## 2. Ligar o celular ao canal
1. Instale o app **HLG Notify** no Android, pela Google Play.
2. Toque em **Ler QR do canal** e escaneie o QR da tela do passo 1.
3. Pronto: o celular entra no canal. Um canal pode ter vários aparelhos, e todos recebem os mesmos avisos.

## 3. Mandar o primeiro aviso
Troque `CODIGO_DO_CANAL` e `SEU_TOKEN_DE_PUBLICACAO` pelos seus:

```bash
curl -w "\nHTTP %{http_code}\n" -d "primeira notificação" -H "Authorization: Bearer SEU_TOKEN_DE_PUBLICACAO" https://notify.hlgcloud.com.br/v1/publish/CODIGO_DO_CANAL
```

A resposta certa é `HTTP 202`, com o número de aparelhos em `devices`. O celular deve tocar em poucos segundos, mesmo com o app fechado.

## 4. Título, prioridade e tags
```bash
curl -X POST https://notify.hlgcloud.com.br/v1/publish/CODIGO_DO_CANAL -H "Authorization: Bearer SEU_TOKEN_DE_PUBLICACAO" -H "Content-Type: application/json" -d '{"title":"Disco cheio","body":"O servidor web está com 95% do disco usado. Libere espaço hoje.","priority":4,"tags":["servidor-web"]}'
```

Só `body` é obrigatório. Também existem `click_url` (link aberto ao tocar na notificação) e `data` (JSON extra).

## 5. Os cinco níveis de aviso
| Prioridade | Cor | O que acontece no celular | Use para |
|---|---|---|---|
| 1 | Verde-claro | Silencioso, sem vibrar | Informação que pode esperar |
| 2 | Verde | Toca, sem vibrar | Rotina que terminou |
| 3 (padrão) | Amarelo | Toca e vibra | Algo para ver hoje |
| 4 | Laranja | Salta na tela | Problema que precisa de você logo |
| 5 | Vermelho | Avisa mesmo com o Não Perturbe ligado | Emergência de verdade |

O som e a vibração de cada nível são ajustados nas configurações do Android, com atalho em **Configurações** no app. Guarde o 5 para o que realmente não pode esperar.

## 6. Avisar do seu script
Primeiro, guarde o canal e o token num arquivo só seu, com permissão 600, nunca dentro do script:

```bash
mkdir -p ~/.config/hlg-notify
touch ~/.config/hlg-notify/env
chmod 600 ~/.config/hlg-notify/env
nano ~/.config/hlg-notify/env
```

Conteúdo do arquivo:

```bash
HLG_CANAL=CODIGO_DO_CANAL
HLG_TOKEN=SEU_TOKEN_DE_PUBLICACAO
```

Depois, cole esta função no seu script bash (ela também está em [`hlg_notify.sh`](hlg_notify.sh)):

```bash
# Envia um aviso pelo HLG Notify.
# Uso: hlg_notify "Título" "Mensagem" [prioridade 1-5, padrão 3]
# Retorna 0 se o aviso foi aceito (HTTP 202) e diferente de 0 se não saiu.
hlg_notify() {
  local titulo=$1 corpo=$2 prioridade=${3:-3}
  local arquivo=${HLG_ENV:-$HOME/.config/hlg-notify/env}
  local url=${HLG_URL:-https://notify.hlgcloud.com.br}
  local HLG_CANAL HLG_TOKEN codigo

  case $prioridade in
    [1-5]) ;;
    *) echo "hlg_notify: prioridade deve ser de 1 a 5" >&2; return 2 ;;
  esac
  if [ -z "$corpo" ]; then
    echo "hlg_notify: a mensagem é obrigatória" >&2; return 2
  fi
  if [ ! -r "$arquivo" ]; then
    echo "hlg_notify: não consegui ler $arquivo" >&2; return 2
  fi
  . "$arquivo"

  _hlg_json() {
    local s
    s=$(printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037')
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
  }

  # O token vai por um arquivo temporário do shell, para não aparecer na lista de processos.
  codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST \
    -K <(printf 'header = "Authorization: Bearer %s"\n' "$HLG_TOKEN") \
    -H "Content-Type: application/json" \
    -d "{\"title\":\"$(_hlg_json "$titulo")\",\"body\":\"$(_hlg_json "$corpo")\",\"priority\":$prioridade}" \
    "$url/v1/publish/$HLG_CANAL")

  if [ "$codigo" != "202" ]; then
    echo "hlg_notify: aviso não enviado (HTTP $codigo)" >&2
    return 1
  fi
}
```

Exemplos de uso:

```bash
hlg_notify "Backup concluído" "Banco salvo com sucesso." 2

/opt/backup.sh || hlg_notify "Backup falhou" "Veja o log em /var/log/backup.log." 4
```

## 7. Boas práticas
- Só avise o que importa. Aviso de tudo vira ruído.
- Escreva para um humano: o que aconteceu, onde e o que fazer.
- Confira o retorno: se o código não for `202`, o aviso não saiu.
- Token vazou ou foi perdido? Ele não pode ser trocado nem recuperado. Crie um canal novo, escaneie o QR e atualize seus scripts.
- Nunca coloque o token em repositório, print, vídeo ou mensagem.

## Limites
| Limite | Valor |
|---|---|
| Mensagens guardadas por canal | As 100 mais recentes |
| Tamanho da mensagem (título + corpo + link) | 3500 bytes |
| Envios por canal | 60 por minuto |
| Criação de canais | 5 por minuto, por IP |

## Resolvendo problemas
| Sintoma | Causa provável |
|---|---|
| Código `401` | Token errado |
| Código `404` | Código do canal digitado errado |
| `202` com `"devices": 0` | Nenhum aparelho inscrito no canal |
| `202`, mas o celular não toca | Canal silenciado, app sem permissão de notificação ou economia de bateria bloqueando |
| Nada chega com o Não Perturbe ligado | Só a prioridade 5 passa por ele |
