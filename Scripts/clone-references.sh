#!/bin/zsh
# P20：取参考仓库。`./Scripts/clone-references.sh` 只报状态，加 `--fetch` 才真下载。
#
# 为什么要有这一支：`docs/github-references/`、`docs/lemon-cleaner/` 都在 `.gitignore` 里
# （各自带独立 `.git` 与许可证），所以**别人 clone 本仓库之后那些目录是空的**，
# 而 `docs/analysis/*.md` 里有一批按那些路径写的逐行引用。
# 引用审计（`./Scripts/p16-citation-audit.sh`）是发版前 checklist 的第 3e 步，
# 它跑不了就等于那一遍核验只有作者机器上做得到。P20 在干净克隆里第一次把它撞出来。
#
# 为什么表在文档里而不是抄一份在脚本里：这一支脚本**直接读**
# `docs/analysis/reference-repos.md` §2 那张表。钉住的 commit 一旦有两份，
# 就会有一份先漂——本项目为这类事已经记过好几笔。表形一改（列数、行数、格式）
# 本脚本会大声失败，而不是静默少抽一行。
#
# 默认不联网：--check 是只读的，--fetch 才 clone。取来的东西只用于读代码，
# 不进版本控制、不随产物分发（许可义务的分析见那份文档 §2 末尾一段）。
set -e

cd "$(dirname "$0")/.."
DOC=docs/analysis/reference-repos.md
MODE=check
for arg in "$@"; do
    case "$arg" in
        --fetch) MODE=fetch ;;
        --check) MODE=check ;;
        -h|--help)
            print -r -- "用法：./Scripts/clone-references.sh [--check|--fetch]"
            print -r -- "  --check（默认）只报每个参考仓库在不在、HEAD 对不对得上表里钉的 commit"
            print -r -- "  --fetch  把缺的取下来、把有的钉回表里那个 commit（会联网）"
            exit 0 ;;
        *) print -u2 -- "不认识参数：$arg（--help 看用法）"; exit 2 ;;
    esac
done

[[ -f $DOC ]] || { print -u2 -- "找不到 $DOC，本脚本判据全部来自那张表。"; exit 1; }

# 抽表：只认「第二列是 github URL」的那些行。字段顺序 = 项目 | 上游 | commit（日期）| 本地路径 | 许可证
typeset -a paths urls shas names
rows=0
while IFS= read -r line; do
    [[ $line == \|* ]] || continue
    url=$(print -r -- "$line" | awk -F'|' '{gsub(/[ `]/,"",$3); print $3}')
    [[ $url == https://github.com/* ]] || continue
    name=$(print -r -- "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
    # commit 那一格形如 `f32fa0c…`（2026-09-28）：取第一个 40 位十六进制串，日期不要
    sha=$(print -r -- "$line" | awk -F'|' '{print $4}' | grep -oE '[0-9a-f]{40}' | head -1)
    pth=$(print -r -- "$line" | awk -F'|' '{gsub(/[ `]/,"",$5); print $5}')
    if [[ -z $sha || -z $pth ]]; then
        print -u2 -- "表里有一行抽不出 commit 或本地路径，本脚本的字段顺序假设被打破了：$line"
        exit 1
    fi
    names+=$name; urls+=$url; shas+=$sha; paths+=$pth; rows=$(( rows + 1 ))
done < "$DOC"

# 行数不当门，但当一条自证：那张表加一行而这里没跟着变，说明列顺序漂了。
if (( rows < 6 )); then
    print -u2 -- "只从 $DOC 抽出 $rows 行（预期至少 6），表形八成变了——判据：第二列是 https URL、第三列带 40 位 commit、第四列是本地路径"
    exit 1
fi

print -r -- "# clone-references.sh 参考仓库状态（模式：$MODE）"
print -r -- "# date: $(date '+%Y-%m-%d %H:%M:%S %z')"
print -r -- "# 表源: $DOC §2（逐行现读，本脚本不另存一份 commit）"
print -r -- "# 抽出 $rows 行"

bad=0
# 下标从 1 起（zsh 数组），且不用 `{1..$#paths}`：花括号展开早于参数展开，
# 这一支脚本里宁可写成显式比较。
for (( i = 1; i <= ${#paths}; i++ )); do
    d=${paths[$i]}; want=${shas[$i]}; nm=${names[$i]}
    if [[ ! -d $d ]]; then
        print -r -- "缺   $nm  $d"
        bad=$(( bad + 1 ))
        if [[ $MODE == fetch ]]; then
            mkdir -p "${d:h}"
            # 按 sha 浅取：不 --unshallow（那会把整个历史拉下来，而我们只要这一份文件树）。
            git init -q "$d"
            git -C "$d" remote add origin ${urls[$i]}
            if ! git -C "$d" fetch --depth 1 -q origin "$want" 2>/dev/null; then
                print -u2 -- "取不到 $want（$nm）：上游可能已经把这一支历史缩短，或服务器不允许按 sha 取。"
                bad=$(( bad + 1 ))
            else
                git -C "$d" checkout -q --detach FETCH_HEAD
                print -r -- "取好 $nm  $d  HEAD=$(git -C "$d" rev-parse --short HEAD)"
                bad=$(( bad - 1 ))
            fi
        fi
        continue
    fi
    got=$(git -C "$d" rev-parse HEAD 2>/dev/null || true)
    if [[ -z $got ]]; then
        print -r -- "在   $nm  $d  但不是 git 仓库（读文件够用，报告里那几行 ref 会记 head=非git仓库）"
        continue
    fi
    if [[ ${got[1,40]} == $want ]]; then
        print -r -- "对   $nm  $d  HEAD=$(git -C "$d" rev-parse --short HEAD) == 表里钉的"
    else
        print -r -- "漂   $nm  $d  HEAD=$(git -C "$d" rev-parse --short HEAD) ≠ 表里的 ${want[1,7]}"
        bad=$(( bad + 1 ))
        if [[ $MODE == fetch ]]; then
            git -C "$d" fetch -q origin "$want" 2>/dev/null || git -C "$d" fetch -q --unshallow origin 2>/dev/null || true
            git -C "$d" checkout -q --detach "$want" 2>/dev/null \
                && { print -r -- "钉回 $nm  HEAD=$(git -C "$d" rev-parse --short HEAD)"; bad=$(( bad - 1 )); } \
                || print -u2 -- "钉不回 $want（$nm）：历史里没有这一支，得人工决定是改表还是留现状。"
        fi
    fi
done

if (( bad > 0 )); then
    print -r -- "结论：$bad 项不达标。引用审计（./Scripts/p16-citation-audit.sh）现在仍跑得动，"
    print -r -- "        但那一批引用会全落进「定位不到文件因而没试行号判据的」那一支，"
    print -r -- "        「命参考仓库」那一格是 0——**那是"没取到"，不是"文档没引"**，别看错。"
    print -r -- "        补齐：./Scripts/clone-references.sh --fetch"
    exit 1
fi
print -r -- "结论：全部在位且都对得上表里钉的 commit，引用审计的「命参考仓库」判据这一跑是有效的。"
