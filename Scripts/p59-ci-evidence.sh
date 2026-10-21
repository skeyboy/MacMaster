#!/bin/bash
# 取 v1.1.0 那一跑的 CI 与 Release 现读，落一份小抄进 docs/verification/p59-release/
# 只用现读的 gh 输出，不手抄。
set -u
OUT=docs/verification/p59-release/ci-run-summary.log
RUN=39568660418
{
  printf '# date: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '# repo: %s branch=%s\n' "$(git rev-parse --short HEAD)" "$(git rev-parse --abbrev-ref HEAD)"
  printf '# run: %s\n' "$RUN"
  printf '\n## gh run view --json（run 的结论，不是 watch 的退出码）\n'
  gh run view "$RUN" --json databaseId,status,conclusion,attempt,event,headSha,workflowName,url
  printf '\n## gh run view --json jobs（13 步逐步结论）\n'
  gh run view "$RUN" --json jobs --jq '.jobs[0] | {name:.name, conclusion:.conclusion, steps:[.steps[]|{n:.name,c:.conclusion}]}'
  printf '\n## 九包全量单测那一步在 CI 机器上读到的结论行（原样抄自 gh run view --log）\n'
  gh run view "$RUN" --log | grep -F '合计：'
  printf '\n## gh release view v1.1.0（远端 Release 本体）\n'
  gh release view v1.1.0 --json tagName,name,isDraft,isPrerelease,publishedAt,targetCommitish,url
  printf '\n## 三个附件（名称/字节/API digest）\n'
  gh release view v1.1.0 --json assets --jq '.assets[]|{name:.name,size:.size,digest:.digest}'
  printf '\n## gh release list（Latest 现在指谁）\n'
  gh release list --limit 10
  printf '\n## tag 与分支的远端落点\n'
  git ls-remote origin refs/heads/main 'refs/tags/v1.1.0'
  printf '\n## v1.1.0 那枚 tag peel 到的提交\n'
  git rev-parse --short 'v1.1.0^{commit}'
} > "$OUT" 2>&1
echo "wrote $OUT ($(wc -l < "$OUT") 行)"
