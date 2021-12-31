#!/bin/bash
# cronで実行する場合、ログ等の出力ファイルはカレントディレクトリに出力される
# 変更したい場合、APP_PATHを変更してください
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

  if [ -e ${LOCK_FILE} ];then
    log "lock found, exit"
    exit
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
  # 注目したい4項目を取り出す
  # 最初の1行は不要なので除去
  # スペース除去
  # 4行ごとに1記事
  # htmlタグ除去
  # 最後がyesなのがdraft
  cat ${1} | egrep "<(title|published|author|app:draft)>"  \
           | sed -e '1d' \
           | tr -d ' ' \
           | xargs -n4 \
           | sed -e 's/<[^>]*>//g' \
           | egrep " yes"
}

create_diff_message() {
  IFS_BACKUP=$IFS
  IFS=$'\n'

  # 現在日時より過去のdraft:yesは「予約記事」ではなく「下書き記事」なので、チェックの必要がある
  NOW_DATETIME=$(date +%Y%m%d%H%M%S)

  ADD_DIFF=($(
    diff -u ${1} ${2} | grep ^+ \
                      | grep -v ^+++ \
                      | sed -e 's/^+//' \
                      | sed -e 's/ yes$//' \
                      | sed -e 's/+09:00//'
  ))
  if [ ${#ADD_DIFF[*]} -ne 0 ]; then
    for i in ${ADD_DIFF[@]}; do
      DATETIME=$(echo ${i} | awk '{print $(NF-1)}' | sed -e 's/://g' -e 's/T//g' -e 's/-//g')
      if [ ${DATETIME} -gt ${NOW_DATETIME} ]; then
        log "new : ${i}"
        MESSAGE=${MESSAGE}"■新しい予約記事を検知しました\r"
        MESSAGE=${MESSAGE}" -> ${i}\r"
      else
        log "not-new (previous draft) : ${i}"
      fi
    done
  fi

  DEL_DIFF=($(
    diff -u ${1} ${2} | grep ^- \
                      | grep -v ^--- \
                      | sed -e 's/^-//' \
                      | sed -e 's/ yes$//' \
                      | sed -e 's/+09:00//'
  ))
  if [ ${#DEL_DIFF[*]} -ne 0 ]; then
    for i in ${DEL_DIFF[@]}; do
      DATETIME=$(echo ${i} | awk '{print $(NF-1)}' | sed -e 's/://g' -e 's/T//g' -e 's/-//g')
      if [ ${DATETIME} -gt ${NOW_DATETIME} ]; then
        log "deleted : ${i}"
        MESSAGE=${MESSAGE}"■予約記事の削除を検知しました\r"
        MESSAGE=${MESSAGE}" -> ${i}\r"
      else
        log "not-deleted (previous draft) : ${i}"
      fi
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
