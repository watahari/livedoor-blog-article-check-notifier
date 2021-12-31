#!/bin/bash
# cronで実行する場合、ログ等の出力ファイルはカレントディレクトリに出力される.
# 変更したい場合、APP_PATHを変更してください.
APP_PATH="$(pwd)"

init() {
  USER="<your livedoor id>"
  API_KEY="<your livedoor blog api key>"
  BLOG_NAME="<blog owner livedoor id>"
  DISCORD_URL="<your discord webhook url https://discord.com/api/webhooks/****>"

  BOT_NAME="下書き記事見張るくん"

  # このログファイルは無限に肥大化するので、適宜logrotateしてください
  LOG_FILE=${APP_PATH}/livedoor-blog-article-check-notifier.log
  LOCK_FILE=${APP_PATH}/livedoor-blog-article-check-notifier.lock
  RESULT_FILE=${APP_PATH}/result.txt
  PREV_FILE=${APP_PATH}/prev_result.txt
  TMP_PREV_FILE=${APP_PATH}/.tmp_prev_result.txt
  TMP1=${APP_PATH}/.1.tmp.txt
  TMP2=${APP_PATH}/.2.tmp.txt
  TMP3=${APP_PATH}/.3.tmp.txt
  TMP4=${APP_PATH}/.4.tmp.txt

  if [ -e ${LOCK_FILE} ];then
    log "lock found, exit"
    exit 1
  else
    touch ${LOCK_FILE}
    log "START <$$>"
  fi

  if [ -e ${RESULT_FILE} ]; then
    if [ -e ${PREV_FILE} ]; then
      log "result before previous found, save as ${TMP_PREV_FILE}"
      mv ${PREV_FILE} ${TMP_PREV_FILE}
    fi
    log "previous data found, save as ${PREV_FILE}"
    mv ${RESULT_FILE} ${PREV_FILE}
  else
    log "previeus data not found"
  fi
  touch ${RESULT_FILE}
}

cleanup() {
  if [ -e ${TMP_PREV_FILE} ]; then
    rm ${TMP_PREV_FILE}
  fi
  if [ -e ${TMP1} ]; then
    rm ${TMP1}
  fi
  if [ -e ${TMP2} ]; then
    rm ${TMP2}
  fi
  if [ -e ${TMP3} ]; then
    rm ${TMP3}
  fi
  if [ -e ${TMP4} ]; then
    rm ${TMP4}
  fi
  log "FINISH <$$>"
  log "===================="
  rm ${LOCK_FILE}
  exit 0
}

revert_finish() {
  log "revert"
  if [ -e ${PREV_FILE} ]; then
    mv ${PREV_FILE} ${RESULT_FILE}
  fi
  if [ -e ${TMP_PREV_FILE} ]; then
    mv ${TMP_PREV_FILE} ${PREV_FILE}
  fi
  cleanup
}

log () {
  echo "[$(date '+%Y%m%dT%H:%M:%S')] $1" >> ${LOG_FILE}
}

get_article_api() {
  log "get articles"
  curl -H "Authorization:Basic $(printf ${USER}:${API_KEY} | openssl base64)" -m 1 -f "https://livedoor.blogcms.jp/atompub/${BLOG_NAME}/article" 2>> ${LOG_FILE}
  if [ $? -eq 0 ]; then
    log "--> get articles OK"
    return 0
  else
    return 1
  fi
}

get_data_updated() {
  grep "<updated>" $1 | head -1 | tr -d ' ' | sed -e's/<updated>//g' -e 's/<\/updated>//g'
}

check_data() {
  CURRENT_UPDATED=$(get_data_updated ${RESULT_FILE})
  log "current updated: ${CURRENT_UPDATED}"
  if [ ! -e ${PREV_FILE} ]; then
    log " it's first running"
    cp ${RESULT_FILE} ${PREV_FILE}
    cp ${PREV_FILE} ${TMP_PREV_FILE}
  else
    PREV_UPDATED=$(get_data_updated ${PREV_FILE})
    log "previous updated: ${PREV_UPDATED}"
    if [ "${CURRENT_UPDATED}" = "${PREV_UPDATED}" ];then
      log "not updated"
      log "  updated : ${CURRENT_UPDATED}"
      revert_finish
    fi
  fi
}

get_draft_articles() {
  IFS_BACKUP=$IFS
  IFS=$'\n'

  # 注目したい4項目を取り出す
  # 最初の1行は不要なので除去
  # スペース除去
  # 4行ごとに1記事
  # htmlタグ除去
  # JSTオフセット部分は固定なので除去
  # 最後がyesなのがdraft
  cat ${1} | egrep "<(title|published|author|app:draft)>"  \
           | sed -e '1d' \
           | tr -d ' ' \
           | xargs -n4 \
           | sed -e 's/<[^>]*>//g' \
           | sed -e 's/+09:00//' \
           | egrep " yes" \
           > ${TMP3}

  # 過去のdraftは除外する. 現在日時より過去のdraft:yesは「下書き記事」なので、日時チェックの必要がある.
  # なお、未来日時の「予約記事」と「下書き記事」は見分けられない.
  NOW_DATETIME=$(date +%Y%m%d%H%M%S)
  ARRAY=($(cat ${TMP3}))
  if [ -e ${TMP4} ]; then
    rm ${TMP4}
  fi
  if [ ${#ARRAY[*]} -ne 0 ]; then
    log "check draft ${1}"""
    for i in ${ARRAY[@]}; do
      DATETIME=$(echo ${i} | awk '{print $(NF-2)}' | sed -e 's/://g' -e 's/T//g' -e 's/-//g')
      if [ ${DATETIME} -gt ${NOW_DATETIME} ]; then
        log " draft detected : ${i}"
        # titleとauthorのみ出力する
        echo "${i}" | awk '{print $1,$3}' >> ${TMP4}
      fi
    done
  fi

  IFS=${IFS_BACKUP}

  if [ -e ${TMP4} ]; then
    cat ${TMP4}
  else
    printf "\r"
  fi
}

create_diff_message() {
  IFS_BACKUP=$IFS
  IFS=$'\n'

  # 追加検知
  ADD_DIFF=($(
    diff -u ${1} ${2} | grep ^+ \
                      | grep -v ^+++ \
                      | sed -e 's/^+//'
  ))
  if [ ${#ADD_DIFF[*]} -ne 0 ]; then
    MESSAGE=${MESSAGE}"■新しい未来記事が作成されました\r"
    for i in ${ADD_DIFF[@]}; do
      MESSAGE=${MESSAGE}"${i}\r"
    done
  fi

  # 削除検知
  DEL_DIFF=($(
    diff -u ${1} ${2} | grep ^- \
                      | grep -v ^--- \
                      | sed -e 's/^-//'
  ))
  if [ ${#DEL_DIFF[*]} -ne 0 ]; then
    MESSAGE=${MESSAGE}"■未来記事の削除を検知しました\r"
    for i in ${DEL_DIFF[@]}; do
      DATETIME=$(echo ${i} | awk '{print $(NF-1)}' | sed -e 's/://g' -e 's/T//g' -e 's/-//g')
      MESSAGE=${MESSAGE}"DELETED -> ${i}\r"
    done
  fi

  IFS=${IFS_BACKUP}
}


# ==========
# Main process
# ==========

init

get_article_api > ${RESULT_FILE}
if [ $? -ne 0 ]; then
  log "get failed"
  revert_finish
fi
check_data

get_draft_articles ${PREV_FILE} | sort > ${TMP1}
get_draft_articles ${RESULT_FILE} | sort > ${TMP2}

MESSAGE=""
create_diff_message ${TMP1} ${TMP2}
if [ "${MESSAGE}" != "" ]; then
  curl -H "Content-Type: application/json" -X POST -d "{\"username\": \"${BOT_NAME}\", \"content\": \"${MESSAGE}\"}" ${DISCORD_URL} >> ${LOG_FILE} 2>&1
  if [ $? -eq 0 ]; then
    log "--> post discord OK"
  else
    revert_finish
  fi
else
  log "no diff found"
fi

cleanup
