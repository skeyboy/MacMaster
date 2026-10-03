#!/bin/zsh
# 「开发产物」页的取证夹具：在 /tmp 下造一片看着像真开发者目录的小树。
#
# 为什么只准放 /tmp：MM_PURGE_FIXTURE_HOME 沿用 MM_ORPHAN_FIXTURE_HOME 的守卫，
# /tmp 之外的取值会被忽略并打到 stderr——这一屏的终点是删除按钮，
# 钩子绝不能把用户的真项目当成可以随便圈的夹具。
#
# 用法：./Scripts/purge-fixture.sh            # 重建夹具，打印根目录
#       ./Scripts/purge-fixture.sh --clean    # 删掉夹具
#
# 截图时：
#   MM_OPEN_MODULE=cleaner MM_OPEN_TAB=dev \
#   MM_PURGE_FIXTURE_HOME=/tmp/macmaster-purge-fixture ./Scripts/p4-sweep.sh ...
#
# P6.1「续扫」三档靠三个预算钩子定格，全部零点击（详见 docs/analysis/hook-ledger.md）：
#   MM_DEV_ROOT_BUDGET_SECONDS=0.02                  首批：让 Documents 量到一半就截断
#   MM_DEV_CONTINUE_BUDGET_SECONDS=20 MM_DEV_AUTO_CONTINUE=1   ② 续扫之后
#   MM_DEV_CONTINUE_BUDGET_SECONDS=0.02 MM_DEV_AUTO_CONTINUE=1 ③ 同一根第二次仍截断
# 11 号那批 bulky 项目就是为这三档存在的：它们让"截断发生在半路"成为可能。
#
# 这棵树是**按分支画的**，不是按体积画的：每一处都对应界面上一个独立状态，
# 少一处就有一支拍不到。改动这里请同步改 docs/analysis/fidelity-cleaner.md 的状态表。
set -e
ROOT=/tmp/macmaster-purge-fixture
OUTSIDE=/tmp/macmaster-purge-outside      # 符号链接越界用例的真身

if [[ "${1:-}" == "--clean" ]]; then
  chmod -R u+rwX "$ROOT" 2>/dev/null || true
  rm -rf "$ROOT" "$OUTSIDE"
  print -r -- "已删除 $ROOT 与 $OUTSIDE"
  exit 0
fi

chmod -R u+rwX "$ROOT" 2>/dev/null || true
rm -rf "$ROOT" "$OUTSIDE"

# stamp <目录> <天数>：把目录连同里面所有条目统一推到 N 天前。
# 必须连内层文件一起推：判定"久未触碰"靠的是产物里有没有近 N 天改动过的文件，
# 只推目录 mtime 的话，界面上会老实显示"今天改动过"，那条分支就永远拍不到。
stamp() {
  local p=$1 t
  [[ $p = /* ]] || p="$ROOT/$p"
  t=$(date -v-${2}d +%Y%m%d%H%M)
  find "$p" -exec touch -t "$t" {} +
}

# art <项目>/<产物名> <天数> <每文件大小> <文件数>
art() {
  local dir="$ROOT/$1"
  mkdir -p "$dir"
  for i in $(seq 1 "$4"); do mkfile "$3" "$dir/part-$i.bin"; done
  stamp "$dir" "$2"
  print -r -- "  $1  ($2 天前, $4 个文件 × $3)"
}

manifest() { print -r -- "{}" > "$ROOT/$1"; }   # manifest <项目>/package.json 之类

print -r -- "建夹具 $ROOT"

# ── 1. 可回收：整组都久未触碰 ────────────────────────────
mkdir -p "$ROOT/Code/macmaster-web/src"
manifest Code/macmaster-web/package.json
print -r -- "console.log(1)" > "$ROOT/Code/macmaster-web/src/index.ts"
art Code/macmaster-web/node_modules 30 4m 3
art Code/macmaster-web/.next 12 2m 2

# ── 2. 近期在用：今天/三天前动过，勾选框可用但默认不勾 ────
mkdir -p "$ROOT/www/stale-site"
manifest www/stale-site/package.json
art www/stale-site/node_modules 0 1m 2      # 今天
art www/stale-site/build 3 1m 2             # 3 天前（< 7 天阈值）

# ── 3. monorepo：组头要带 pnpm-workspace 徽章，产物在项目深处 ──
mkdir -p "$ROOT/dev/monorepo-app/packages/web" "$ROOT/dev/monorepo-app/packages/api"
manifest dev/monorepo-app/pnpm-workspace.yaml
manifest dev/monorepo-app/package.json
manifest dev/monorepo-app/packages/web/package.json
print -r -- "[package]" > "$ROOT/dev/monorepo-app/packages/api/Cargo.toml"
art dev/monorepo-app/.turbo 20 1m 1
art dev/monorepo-app/packages/web/node_modules 45 6m 2
art dev/monorepo-app/packages/api/target 28 5m 2

# ── 4. 受保护：名字像产物，证据不足 ──────────────────────
# Go：vendor 是源码的一部分，bin 不是 .NET 输出
mkdir -p "$ROOT/Projects/go-tool/vendor/pkg" "$ROOT/Projects/go-tool/bin"
print -r -- "module x" > "$ROOT/Projects/go-tool/go.mod"
print -r -- "package main" > "$ROOT/Projects/go-tool/vendor/pkg/x.go"
print -r -- "binary" > "$ROOT/Projects/go-tool/bin/tool"
stamp Projects/go-tool/vendor 10; stamp Projects/go-tool/bin 10
# .NET：bin/Debug 有邻居 .csproj（可回收），obj 里没有 Debug/Release（受保护）
mkdir -p "$ROOT/Projects/dotnet-app/bin/Debug/net8.0" "$ROOT/Projects/dotnet-app/obj"
print -r -- "<Project/>" > "$ROOT/Projects/dotnet-app/App.csproj"
mkfile 2m "$ROOT/Projects/dotnet-app/bin/Debug/net8.0/App.dll"
print -r -- "{}" > "$ROOT/Projects/dotnet-app/obj/project.assets.json"
stamp "$ROOT/Projects/dotnet-app/bin" 30; stamp "$ROOT/Projects/dotnet-app/obj" 30
# 产物目录里含 .git：node_modules 这个名字再硬也压过它
mkdir -p "$ROOT/Projects/nested-repo"
manifest Projects/nested-repo/package.json
art Projects/nested-repo/node_modules 30 1m 1
mkdir -p "$ROOT/Projects/nested-repo/node_modules/.git"
print -r -- "gitdir: x" > "$ROOT/Projects/nested-repo/node_modules/.git/HEAD"
# .git 建完再压一次时间：新建条目会把宿主目录的 mtime 顶成"今天"，
# 那样拍到的就是"受保护 + 近期在用"两个状态挤在同一行，看不出受保护那支本来长什么样。
stamp Projects/nested-repo/node_modules 30
# Rust 项目里的 coverage：没有 package.json 作证，判受保护（同组里 target 可回收，一屏见两档）
mkdir -p "$ROOT/Projects/rust-cli"
print -r -- "[package]" > "$ROOT/Projects/rust-cli/Cargo.toml"
art Projects/rust-cli/target 60 8m 2
art Projects/rust-cli/coverage 60 1m 2
# 同一套名字规则的正分支：项目根有 package.json，dist 就升级为"上下文已证明"
mkdir -p "$ROOT/Projects/hybrid-app"
print -r -- "module x" > "$ROOT/Projects/hybrid-app/go.mod"
manifest Projects/hybrid-app/package.json
art Projects/hybrid-app/dist 15 4m 2

# ── 5. 最强证据：CACHEDIR.TAG（目录自述为缓存） ────────────
mkdir -p "$ROOT/Repos/toolcache/.gradle/caches"
print -r -- "apply plugin" > "$ROOT/Repos/toolcache/build.gradle"
mkfile 4m "$ROOT/Repos/toolcache/.gradle/caches/jars.bin"
print -r -- "Signature: 8a477f597d28d172789f06886806bc55" > "$ROOT/Repos/toolcache/.gradle/CACHEDIR.TAG"
stamp "$ROOT/Repos/toolcache/.gradle" 30

# ── 6. 未测得：目录在但没有读权限，体积必须显示"—" ─────────
mkdir -p "$ROOT/Repos/locked/build"
manifest Repos/locked/package.json
mkfile 3m "$ROOT/Repos/locked/build/out.bin"
stamp "$ROOT/Repos/locked/build" 20
chmod 000 "$ROOT/Repos/locked/build"

# ── 7. Swift 项目：.build 认名字，项目内 DerivedData 认上下文 ──
mkdir -p "$ROOT/Repos/swift-pkg/DerivedData"
print -r -- "// swift-tools-version" > "$ROOT/Repos/swift-pkg/Package.swift"
art Repos/swift-pkg/.build 40 5m 2
art Repos/swift-pkg/DerivedData 40 3m 2

# ── 8. 云同步：iCloud 目录里的产物，删了会同步到所有设备 ────
mkdir -p "$ROOT/Library/CloudStorage/DesignWork"
manifest Library/CloudStorage/DesignWork/package.json
art Library/CloudStorage/DesignWork/dist 30 2m 2

# ── 9. AI agent worktree 容器：藏在点目录下，常规发现进不去 ──
mkdir -p "$ROOT/.claude/worktrees/agent-run/demo-app" "$ROOT/.codex/worktrees/run2/api"
manifest .claude/worktrees/agent-run/demo-app/package.json
manifest .codex/worktrees/run2/api/package.json
art .claude/worktrees/agent-run/demo-app/node_modules 25 3m 2
art .codex/worktrees/run2/api/.next 18 2m 2

# ── 10. 越界与假容器：这两处都**不该**出现在界面上 ──────────
# 散落在家目录根的 node_modules：它是产物名，不能当"项目容器的集合"来扫，
# 否则它里面的 dist/build 会被当成项目产物送进删除清单（Mole #1459 的坑）。
art node_modules 30 1m 2
# 符号链接指向夹具之外的真目录：物理包含校验必须把它丢掉
mkdir -p "$OUTSIDE/node_modules"
mkfile 5m "$OUTSIDE/node_modules/part-1.bin"
stamp "$OUTSIDE/node_modules" 40
mkdir -p "$ROOT/Projects/sneaky"
manifest Projects/sneaky/package.json
ln -s "$OUTSIDE/node_modules" "$ROOT/Projects/sneaky/node_modules"

# ── 11. bulky 根：P6.1「续扫」三档取证用 ──────────────────
# 一个搜索根里放十几个项目、每个产物 120 个文件。为什么非要"胖"：截断只会发生在
# **成案/测量**阶段（浅层发现实测 0.06 秒），所以要让 MM_DEV_ROOT_BUDGET_SECONDS
# 能落在"量到一半"的窗口里——候选太少的话要么整根扫完、要么一个都没量到，
# 「第一批量到的行在第二批被直接复用」那一档就拍不出来。
for i in $(seq 1 12); do
  mkdir -p "$ROOT/Documents/bulk-$i/src"
  manifest Documents/bulk-$i/package.json
  art Documents/bulk-$i/node_modules 40 40k 120
done

print -r -- "→ $ROOT"
# 读不到的那个目录会让 du 报错，这里它是**故意**造的（未测得那支），所以吞掉再报总量
du -sh "$ROOT" 2>/dev/null || print -r -- "  （du 跳过无权限目录：Repos/locked/build）"
print -r -- "产物目录清点（天数=距上次改动，负数表示"今天"）："
for d in $(find "$ROOT" -type d \( -name node_modules -o -name target -o -name .next -o -name build \
    -o -name dist -o -name coverage -o -name vendor -o -name .gradle -o -name .turbo -o -name obj \
    -o -name bin -o -name .build -o -name DerivedData \) | sort); do
  mtime=$(stat -f %m "$d" 2>/dev/null || echo 0)
  age=$(( ( $(date +%s) - mtime ) / 86400 ))
  n=$(ls -A "$d" 2>/dev/null | wc -l | tr -d ' ')
  printf '  %-52s %4s 天  %s 项\n' "${d#$ROOT/}" "$age" "$n"
done
