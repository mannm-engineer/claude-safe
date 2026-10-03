#!/usr/bin/env bash
# Cài hoặc cập nhật claude-safe trên macOS, Linux, Windows (Git Bash) (cần Docker có Docker Compose v2):
#   curl -fsSL https://raw.githubusercontent.com/mannm-engineer/claude-safe/master/install.sh | bash
# Tải repo về ~/.local/share/claude-safe, build image, thêm vào ~/.bashrc và ~/.zshrc một dòng nạp aliases.sh (bí danh
# claude-safe). Mở terminal mới, đứng ở thư mục gốc của project, gõ claude-safe.
set -euo pipefail

url=https://github.com/mannm-engineer/claude-safe/archive/refs/heads/master.tar.gz
dir="$HOME/.local/share/claude-safe"   # phải khớp với aliases.sh
# Bí danh nằm trong aliases.sh của bản cài: cài lại là cập nhật, không phải sửa ~/.bashrc. Đã gỡ thì dòng này bỏ qua.
line='if [ -f ~/.local/share/claude-safe/aliases.sh ]; then . ~/.local/share/claude-safe/aliases.sh; fi'

install_claude_safe() {
  rm -rf "$dir" && mkdir -p "$dir"
  curl -fsSL "$url" | tar -xz --strip-components=1 -C "$dir"
  docker build -t claude-safe "$dir/anthropic"
  for rc in ~/.bashrc ~/.zshrc; do grep -qsF "$line" "$rc" || echo "$line" >> "$rc"; done
}

install_claude_safe
echo "Xong. Mở terminal mới, đứng ở thư mục gốc của project và gõ: claude-safe"
