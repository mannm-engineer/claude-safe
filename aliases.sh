# Bí danh của claude-safe. install.sh thêm vào ~/.bashrc và ~/.zshrc một dòng nạp file này; đường dẫn phải khớp với
# install.sh. $HOME được thay lúc dùng.

# Chạy Claude Code trong container cho project đang đứng (xem compose.yaml).
alias claude-safe='docker compose -f "$HOME/.local/share/claude-safe/compose.yaml" --env-file "$HOME/.local/share/claude-safe/compose.env" --project-directory . run --rm claude'
