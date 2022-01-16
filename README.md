# livedoor-blog-article-check-notifier

「予約記事」が追加されるとDiscordに通知するクソスクリプトです。<br>
複数人でブログ運営している人におすすめ。

## Prepare

Edit the variable at the beginning of `main.sh`.
```
  USER="<your livedoor id>"
  API_KEY="<your livedoor blog api key>"
  BLOG_NAME="<blog owner livedoor id>"
  DISCORD_URL="<your discord webhook url https://discord.com/api/webhooks/****>"
```

(Optional)<br>
You can set the replacement settings to make it easier for humans to see.<br>
Please modify the `replacement_setting.ini` file.
```
your_livedoor_id=human_readable_name
abcdefg012=J.Doe
```

## Run

Operation on raspberry pi and MacOS has been confirmed.
```
bash /path/to/livedoor-blog-article-check-notifier/main.sh
```

## Run via cron
If you want to check regularly, set cron like

```
*/5 * * * * bash /path/to/livedoor-blog-article-check-notifier/main.sh
```

Recommended to change `APP_PATH` if run script via cron.
```
APP_PATH="/path/to/livedoor-blog-article-check-notifier_directory"
```

## Disclaim

This script is NOT authorized by Livedoor.<br>
We are not responsible for any damages caused by using this script.

This script is not intended to overload these sites or services.<br>
When using this script, please keep your posting frequency within a sensible range.
