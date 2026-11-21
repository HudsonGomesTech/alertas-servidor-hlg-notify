#!/usr/bin/env bash
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
