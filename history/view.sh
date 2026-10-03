#!/usr/bin/env bash
# Mở lịch sử một session của project đang đứng trong VS Code, để xem bằng Git Graph (bí danh claude-history):
#   claude-history                       session mới nhất
#   claude-history <session id>          session cụ thể
# Repo lịch sử chỉ có phần .git (bare), VS Code không mở được, nên clone ra ~/.cache/claude-safe-view rồi mở bản clone;
# mở lại thì git pull để lấy các lượt mới. Bản clone chỉ để xem: sửa hay xóa không ảnh hưởng lịch sử gốc.
set -euo pipefail

install_dir=$(cd "$(dirname "$0")/.." && pwd)
# Tên project do chính Compose tính, giống hệt lúc chạy claude-safe.
project=$(docker compose -f "$install_dir/compose.yaml" --env-file "$install_dir/compose.env" --project-directory . \
  config | sed -n 's/^name: //p')
history="$HOME/.local/share/claude-safe-history/$project"   # phải khớp với compose.env
[ -d "$history" ] || { echo "Chưa có lịch sử cho project $project ($history)." >&2; exit 1; }

session=${1:-$(ls -t "$history" | head -n 1)}
view="$HOME/.cache/claude-safe-view/$project/$session"
if [ -d "$view/.git" ]; then git -C "$view" pull -q; else git clone -q "$history/$session" "$view"; fi
echo "Lịch sử session $session của $project: $view (mở Git Graph ở thanh trạng thái của VS Code)"
code "$view"
