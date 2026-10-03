#!/usr/bin/env bash
# Hook (history/managed-settings.json) gọi script này ở SessionStart, UserPromptSubmit, Stop, SessionEnd để commit trạng
# thái ~/.claude (gồm .claude.json, nhờ CLAUDE_CONFIG_DIR) vào repo lịch sử của riêng session:
#   /history/<project>/<session id>   (trên máy thật: ~/.local/share/claude-safe-history/...)
# Mỗi session một repo nên không cần khóa: chỉ hook của chính session ghi vào repo đó, và chúng chạy lần lượt.
# info/exclude dựa trên UUID: bỏ mọi file có UUID trong tên (file của session khác, skill đồng bộ theo mã tổ chức...),
# trừ file có session id của chính session; file dùng chung (.claude.json, history.jsonl, memory...) vẫn được commit.
# Luôn kết thúc thành công để không chặn Claude; lỗi ghi vào /history/hook-commit.log. Xem DECISIONS.md.
input=$(cat)
event="$1"
sid=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
[ -d /history ] && [ -n "$sid" ] || exit 0
repo="/history/${CLAUDE_HISTORY_PROJECT:-unknown}/$sid"
exec 2>>/history/hook-commit.log

# Repo chỉ rõ bằng --git-dir, nên git không kiểm tra chủ sở hữu (chỉ kiểm tra khi tự dò repo): không cần safe.directory.
history_git() { git --git-dir="$repo" --work-tree="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "$@"; }

if [ ! -d "$repo" ]; then
  git init -q --bare "$repo" || exit 0
  history_git config core.autocrlf false
  history_git config user.name "automation[bot]"
  history_git config user.email "automation-bot@noreply.localhost"
  printf '%s\n' '*????????-????-????-????-????????????*' "!*$sid*" '.credentials.json' 'sessions/' \
    'plugins/marketplaces/' > "$repo/info/exclude"
fi
# Khóa của git bị bỏ lại khi một hook trước bị giết giữa lúc commit (container dừng ngang). Lúc session vừa khởi động
# (kể cả khi resume) không ai khác đang ghi repo này, nên xóa là an toàn.
[ "$event" = session-start ] && rm -f "$repo/index.lock"

# Claude Code ghi .claude.json qua file tạm rồi đổi tên; git có thể gặp file tạm vừa biến mất: thử lại.
for attempt in 1 2 3; do history_git add -A && break; sleep 0.5; done
history_git diff --cached --quiet || history_git commit -q -m "[$event]" >/dev/null
exit 0
