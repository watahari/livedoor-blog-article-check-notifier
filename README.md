# livedoor-blog-article-check-notifier

「下書き記事」が追加されるとDiscordに通知するクソスクリプトです。<br>
複数人でブログ運営している人におすすめ。

# prepare

Edit the variable at the beginning of `main.sh`.
```
  USER="<your livedoor id>"
  API_KEY="<your livedoor blog api key>"
  BLOG_NAME="<blog owner livedoor id>"
  DISCORD_URL="<your discord webhook url https://discord.com/api/webhooks/****>"
```

# run

Operation on raspberry pi and MacOS has been confirmed.
```
bash /path/to/livedoor-blog-article-check-notifier/main.sh
```

If you want to check regularly, set cron like

```
*/5 * * * * bash /path/to/livedoor-blog-article-check-notifier/main.sh
```

# Disclaim

This script is NOT authorized by Livedoor.<br>
We are not responsible for any damages caused by using this script.

This script is not intended to overload these sites or services.<br>
When using this script, please keep your posting frequency within a sensible range.
