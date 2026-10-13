#!/bin/zsh
# 把 tag 推上去之后，GitHub 那一头真的发出了什么——这一支只回答这个问题。
#
# 为什么要有这一支：§10 的第 1–3 步全部跑在**本地构建的候选产物**上，而用户拿到的是
# Actions 在 runner 上打出来的那一份。两者之间有四道从前只能靠说的接缝：
#   ① Release 的正文是不是仓库里那一篇发版说明（workflow 是把整个文件当正文交的）
#   ② 附件档的 sha256 与 `SHA256SUMS.txt` 里写的是不是同一个数（下载链路会不会掉包）
#   ③ 产物 plist 里的版本号与提交号是不是这一版该有的那一对（`1.0.1` / 构建 `1` / 不带 `-dirty`）
#   ④ 编译输入那一段源码指纹与本地核验过的那一份**是否逐字相同**——只有这一段相同，
#      "764 条单测通过"这句话才适用于用户手上这个二进制
# 前十四轮都没有把这一面变成可重跑的数，只是读网页。
#
# 凭据：仓库是私有的，匿名 API 取不到。这一支用 git 自己的凭据助手要一份 token
# （`git credential fill`），**只放进子进程的请求头，一次都不打印**。
# 产物落在一处临时目录，退出即删——证据只留日志，七兆的二进制不入库。
#
# 用法：
#   ./Scripts/p35b-release-verify.sh v1.0.1 > docs/verification/p35b-release/release.log
#
# 退出码：0 全绿；2 取不到 Release、附件或凭据；3 sha256 与 SHA256SUMS / API 报的不一致；
#         4 plist 的版本号、提交号或指纹段不符；5 正文与仓库里那篇对不上。
set -e

cd "$(dirname "$0")/.."
TAG=${1:?用法: ./Scripts/p35b-release-verify.sh <tag，例如 v1.0.1>}
REPO=$(git config --get remote.origin.url | sed -E 's#.*(github\.com[:/])##; s#\.git$##')
API="https://api.github.com/repos/$REPO"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mm-release-verify.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

printf '# p35b-release-verify.sh %s  %s\n' "$TAG" "$(date '+%Y-%m-%d %H:%M:%S %z')"
printf '# repo: %s branch=%s\n' "$(git rev-parse --short HEAD)$(git diff --quiet || echo -dirty)" \
  "$(git rev-parse --abbrev-ref HEAD)"
printf '# api: %s\n' "$API"

TOK=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')
if [[ -z "$TOK" ]]; then
  print -u2 '取不到 github.com 的凭据（git credential fill 返回空）——这一支不重试、不猜。'
  exit 2
fi
get() { curl -sfS -H "Authorization: Bearer $TOK" "$@"; }

# ---- ① Release 本体：tag 指向哪一笔、正文多长、附件有几个 ----
get "$API/releases/tags/$TAG" > "$WORK/rel.json" || { print -u2 "取不到 $TAG 的 Release"; exit 2; }
python3 - "$WORK/rel.json" "$WORK/assets.tsv" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
print('# release: id=%s tag=%s name=%s target=%s draft=%s prerelease=%s published=%s'
      % (r['id'], r['tag_name'], r['name'], r['target_commitish'][:7],
         r['draft'], r['prerelease'], r['published_at']))
print('# release: body_len=%d 字符  body_head=%r' % (len(r['body']), r['body'][:24]))
out = open(sys.argv[2], 'w')
for a in sorted(r['assets'], key=lambda a: a['name']):
    d = (a.get('digest') or '').replace('sha256:', '')
    print('# asset: %s  %s 字节  id=%s  api-digest=%s  state=%s'
          % (a['name'], a['size'], a['id'], d or '-', a['state']))
    out.write('%s\t%s\t%s\n' % (a['id'], a['name'], d))
out.close()
PY

# ---- ② 正文与仓库里那篇发版说明逐字相等 ----
# workflow 用 `--notes-file` 交整个文件，所以正文应等于 tag 那一棵树上的它。
# GitHub 会剥掉正文末尾的空白，判据按"剥掉尾部空白后相等"，并把这一处如实打出来。
git show "$TAG:RELEASE-NOTES.md" > "$WORK/notes.md"
python3 - "$WORK/rel.json" "$WORK/notes.md" <<'PY'
import json, sys
body = json.load(open(sys.argv[1]))['body']
file = open(sys.argv[2], encoding='utf-8').read()
print('# notes: 逐字相等=%s  剥尾部空白后相等=%s  （正文 %d 字符 / 文件 %d 字符 / 文件 %d 字节）'
      % (body == file, body.rstrip() == file.rstrip(), len(body), len(file),
         len(file.encode('utf-8'))))
if body.rstrip() != file.rstrip():
    print('# notes: 正文头 %r 对不上文件头 %r' % (body[:24], file[:24]))
    sys.exit(5)
PY

# ---- ③ 三份附件都下回来，sha256 三方对齐（本地 / API 报的 / 清单里写的） ----
SUMS=$(awk -F'\t' '$2 ~ /SHA256SUMS/ {print $2; exit}' "$WORK/assets.tsv")
get -H "Accept: application/octet-stream" -L \
  "$API/releases/assets/$(awk -F'\t' -v n="$SUMS" '$2==n {print $1}' "$WORK/assets.tsv")" \
  -o "$WORK/$SUMS"
printf '# sums-file: %s（%s 字节）\n' "$SUMS" "$(wc -c < "$WORK/$SUMS" | tr -d ' ')"
sed 's/^/# sums-line: /' "$WORK/$SUMS"

while IFS=$'\t' read -r ID NAME DIGEST; do
  if [[ "$NAME" == *SHA256SUMS* ]]; then continue; fi
  get -H "Accept: application/octet-stream" -L "$API/releases/assets/$ID" -o "$WORK/$NAME"
  LOCAL=$(shasum -a 256 "$WORK/$NAME" | cut -d' ' -f1)
  IN_SUMS=$(awk -v n="$NAME" '$2==n {print $1}' "$WORK/$SUMS")
  API_OK=$([[ -n "$DIGEST" && "$DIGEST" == "$LOCAL" ]] && echo 相同 || echo 不符)
  SUMS_OK=$([[ -n "$IN_SUMS" && "$IN_SUMS" == "$LOCAL" ]] && echo 相同 || echo 不符)
  printf '# sha256: %s  本地=%s  与 api 报的=%s  与清单里写的=%s\n' "$NAME" "$LOCAL" "$API_OK" "$SUMS_OK"
  if [[ "$API_OK" != 相同 || "$SUMS_OK" != 相同 ]]; then
    print -u2 "$NAME 的 sha256 对不上"
    exit 3
  fi
done < "$WORK/assets.tsv"

# ---- ④ 产物 plist：版本号、提交号、源码指纹段 ----
ZIP=$(ls "$WORK"/*.zip | head -1)
unzip -q -o "$ZIP" -d "$WORK/x"                 # ditto 打的档，解回来验 bundle 结构与可执行位
APP="$WORK/x/MacMaster.app"
[[ -d "$APP" ]] || { print -u2 "zip 解不开出 bundle：$ZIP"; exit 4; }
plutil -lint "$APP/Contents/Info.plist" >/dev/null   # 只是确认这是一份能解析的 plist

printf '# plist: '
plutil -p "$APP/Contents/Info.plist" \
  | grep -E 'ShortVersion|CFBundleVersion|MMGitCommit|MMSourceDigest|LSMinimumSystem' \
  | sed -E 's/^ *"?([^"]+)"? => "?([^"]+)"?,?$/\1=\2;/' | tr -d '\n'; print ''

VER=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
BUILD=$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")
COMMIT=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist")
DIGEST=$(plutil -extract MMSourceDigest raw "$APP/Contents/Info.plist")
WANT_VER=${TAG#v}
TREE=$(source ./Scripts/mm-provenance.sh >/dev/null 2>&1; mm_source_digest .)

printf '# check: 版本号 %s（期望 %s）构建 %s → %s\n' "$VER" "$WANT_VER" "$BUILD" \
  "$([[ "$VER" == "$WANT_VER" ]] && echo 对 || echo 错)"
printf '# check: MMGitCommit=%s → %s\n' "$COMMIT" \
  "$([[ "$COMMIT" != *-dirty ]] && echo 干净树（不带 -dirty） || echo 脏树)"
printf '# check: 指纹段 产物=%s 本地工作树=%s → 编译输入 %s\n' "${DIGEST##*+}" "${TREE##*+}" \
  "$([[ "${DIGEST##*+}" == "${TREE##*+}" ]] && echo 逐字相同 || echo 不同)"
if [[ "$VER" != "$WANT_VER" || "$COMMIT" == *-dirty || "${DIGEST##*+}" != "${TREE##*+}" ]]; then
  print -u2 '产物 plist 的版本号 / 提交号 / 指纹段有一条不符'
  exit 4
fi

# ---- ⑤ 那一跑 Actions 的结论（不再靠人眼看网页） ----
TARGET=$(python3 -c "import json;print(json.load(open('$WORK/rel.json'))['target_commitish'])")
get "$API/commits/$TARGET/check-runs?per_page=50" > "$WORK/checks.json"
python3 - "$WORK/checks.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for c in d.get('check_runs', []):
    if c.get('status') != 'completed':
        print('# ci: %s  status=%s（还没跑完）' % (c['name'], c['status']))
        continue
    print('# ci: %s  conclusion=%s  html_url=%s' % (c['name'], c['conclusion'], c['html_url']))
PY

# ---- ⑥ 签名与 Gatekeeper：ad-hoc、未公证——已知限制，不是这一遍新发现的缺陷 ----
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/# verify: /' | tail -3
codesign -dv --verbose=2 "$APP" 2>&1 \
  | grep -E 'Identifier|flags|Signature=|TeamIdentifier' | tr '\n' ' ' | sed 's/^/# codesign: /'
print ''
spctl --assess --type execute -vv "$APP" 2>&1 | sed 's/^/# spctl: /'
printf '# verdict: %s 的 Release 附件与本地核验过的同一棵编译输入树\n' "$TAG"
