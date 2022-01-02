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
  # 多重実行回避のためロック機構があるが、不測の事態での長期間ロック発生時に運用作業をしなければならないのは面倒.
  # LOCK_IGNORED_SEC秒以上前のロックファイルは無視する救済措置を用意している.
  LOCK_FILE=${APP_PATH}/livedoor-blog-article-check-notifier.lock
  LOCK_IGNORED_SEC=600
  RESULT_FILE=${APP_PATH}/result.txt
  PREV_FILE=${APP_PATH}/prev_result.txt
  TMP_PREV_FILE=${APP_PATH}/.tmp_prev_result.tmp.txt
  TMP_DRAFT_NOW=${APP_PATH}/.result_draft.tmp.txt
  TMP_DRAFT_PREV=${APP_PATH}/.prev_result_draft.tmp.txt
  TMP1=${APP_PATH}/.1.tmp.txt
  TMP2=${APP_PATH}/.2.tmp.txt
  TMP3=${APP_PATH}/.3.tmp.txt
  TMP4=${APP_PATH}/.4.tmp.txt

  if [ -e ${LOCK_FILE} ];then
    NOW_UT=$(date +%s)
    LOCK_UT=$(date -r ${LOCK_FILE} '+%s')
    LOCK_TERM_UT=$((${NOW_UT}-${LOCK_UT}))
    # LOCK_IGNORED_SEC秒以上lockがある場合の救済措置
    if [ ${LOCK_TERM_UT} -gt ${LOCK_IGNORED_SEC} ];then
      log "lock found, but ${LOCK_TERM_UT} seconds heve passed. "
      log "ignoring lock file."
    else
      log "lock found (${LOCK_TERM_UT}sec) exit."
      exit 1
    fi
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
  if [ -e ${TMP_DRAFT_NOW} ]; then
    rm ${TMP_DRAFT_NOW}
  fi
  if [ -e ${TMP_DRAFT_PREV} ]; then
    rm ${TMP_DRAFT_PREV}
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

  # 注目したい5項目を取り出す
  # 最初の2行は不要なので除去
  # スペース除去
  # 5行ごとに1記事
  # htmlタグ除去
  # JSTオフセット部分は固定なので除去
  # 最後がyesなのがdraft
  cat ${1} | egrep "<(title|id|published|author|app:draft)>"  \
           | sed -e '1,2d' \
           | tr -d ' ' \
           | xargs -n5 \
           | sed -e 's/<[^>]*>//g' \
           | sed -e 's/+09:00//' \
           | egrep " yes" \
           > ${TMP1}

  # 過去のdraftは除外する. 現在日時より過去のdraft:yesは「下書き記事」なので、日時チェックの必要がある.
  # なお、未来日時の「予約記事」と「下書き記事」は見分けられない.
  NOW_DATETIME=$(date +%Y%m%d%H%M%S)
  ARRAY=($(cat ${TMP1}))
  if [ -e ${TMP2} ]; then
    rm ${TMP2}
  fi
  if [ ${#ARRAY[*]} -ne 0 ]; then
    log "check draft ${1}"""
    for i in ${ARRAY[@]}; do
      DATETIME=$(echo ${i} | awk '{print $(NF-2)}' | sed -e 's/://g' -e 's/T//g' -e 's/-//g')
      if [ ${DATETIME} -gt ${NOW_DATETIME} ]; then
        log " draft detected : ${i}"
        # title,id,authorのみ出力する
        echo "${i}" | awk '{print $1,$2,$4}' >> ${TMP2}
      fi
    done
  fi

  IFS=${IFS_BACKUP}

  if [ -e ${TMP2} ]; then
    cat ${TMP2}
  else
    printf "\r"
  fi
}

create_diff_message() {
  IFS_BACKUP=$IFS
  IFS=$'\n'

  # idに注目し、差分を取得する
  #  => article自体の追加/削除通知に利用する
  cat ${1} | awk '{print $(NF-1)}' > ${TMP1}
  cat ${2} | awk '{print $(NF-1)}' > ${TMP2}
  ID_ADD_DIFF=($(
    diff -u ${TMP1} ${TMP2} | grep ^+ \
                            | grep -v ^+++ \
                            | sed -e 's/^+//'
  ))
  ID_DEL_DIFF=($(
    diff -u ${TMP1} ${TMP2} | grep ^- \
                            | grep -v ^--- \
                            | sed -e 's/^-//'
  ))
  # 後ほど使うので、ID_ADD/DEL_DIFFをTMP4に出力しておく
  rm ${TMP1}
  if [ ${#ID_ADD_DIFF[*]} -ne 0 ]; then
    for i in ${ID_ADD_DIFF[@]}; do
        echo ${i} >> ${TMP1}
    done
  fi
  if [ ${#ID_DEL_DIFF[*]} -ne 0 ]; then
    for i in ${ID_DEL_DIFF[@]}; do
        echo ${i} >> ${TMP1}
    done
  fi
  cat ${TMP1} | sort > ${TMP4}

  # titleとauthorに注目し、差分を取得する
  #  => articleのタイトル変更検知に利用する
  cat ${1} | awk '{print $1,$(NF-1),$(NF)}' > ${TMP1}
  cat ${2} | awk '{print $1,$(NF-1),$(NF)}' > ${TMP2}
  diff -u ${TMP1} ${TMP2} | grep ^\[+-\] \
                          | grep -v ^+++ \
                          | grep -v ^--- \
                          | awk '{print $2}' \
                          | sort \
                          > ${TMP3}
  # id差分と突き合わせて、純粋なtitle変更のみの差分に修正する
  rm ${TMP1}
  comm -13 ${TMP4} ${TMP3} | sort | uniq > ${TMP1}
  TITLE_DIFF=($(cat ${TMP1}))

  # 追加検知
  if [ ${#ID_ADD_DIFF[*]} -ne 0 ]; then
    MESSAGE=${MESSAGE}"■新しい未来記事が作成されました\r"
    MESSAGE=${MESSAGE}"\`\`\`"
    for i in ${ID_ADD_DIFF[@]}; do
      M=$(grep ${i} ${2} | awk '{print $1" by "$3}')
      MESSAGE=${MESSAGE}"${M}\r"
    done
    MESSAGE=${MESSAGE}"\`\`\`"
  fi

  # 削除検知
  if [ ${#ID_DEL_DIFF[*]} -ne 0 ]; then
    MESSAGE=${MESSAGE}"■未来記事の削除を検知しました\r"
    MESSAGE=${MESSAGE}"\`\`\`"
    for i in ${ID_DEL_DIFF[@]}; do
      M=$(grep ${i} ${1} | awk '{print $1" by "$3}')
      MESSAGE=${MESSAGE}"${M}\r"
    done
    MESSAGE=${MESSAGE}"\`\`\`"
  fi

  # タイトル変更検知
  if [ ${#TITLE_DIFF[*]} -ne 0 ]; then
    MESSAGE=${MESSAGE}"■未来記事の記事名変更を検知しました\r"
    for i in ${TITLE_DIFF[@]}; do
      MESSAGE=${MESSAGE}"\`\`\`"
      M="- "$(grep $i ${1} | awk '{print $1}')"\r+ "$(grep $i ${2} | awk '{print $1}')
      MESSAGE=${MESSAGE}"${M}\r"
      MESSAGE=${MESSAGE}"\`\`\`"
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

get_draft_articles ${PREV_FILE} | sort > ${TMP_DRAFT_PREV}
get_draft_articles ${RESULT_FILE} | sort > ${TMP_DRAFT_NOW}

MESSAGE=""
create_diff_message ${TMP_DRAFT_PREV} ${TMP_DRAFT_NOW}
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
