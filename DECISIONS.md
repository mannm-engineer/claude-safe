# Vì sao `compose.yaml` khác devcontainer gốc

Setup này chạy Claude Code trong container bằng `Dockerfile` và `init-firewall.sh` lấy nguyên văn từ dev container
mẫu của Anthropic (`anthropics/claude-code`, commit `52c76441cae91f6891e4712306bffb057ff6fec5`), đặt trong thư mục
`anthropic/`, thay `devcontainer.json` bằng `compose.yaml` để dùng từ terminal, không cần IDE.

Lịch sử git được dựng để đọc từng khác biệt một:
- Commit `feat: Claude Code sandbox mirroring Anthropic's devcontainer`: `compose.yaml` giống `devcontainer.json`
  ở mọi điểm làm được bằng Compose.
- Mỗi commit `feat(diff-N)` đổi đúng một điểm. Xem: `git log -p` hoặc `git show <commit>`.

## Cách dùng

Cài, một lần trên mỗi máy (chạy lại để cập nhật). Cần Docker có Docker Compose v2; trên Windows chạy trong Git Bash:
```
curl -fsSL https://raw.githubusercontent.com/mannm-engineer/claude-safe/master/install.sh | bash
```
Script tải repo (bản nén, không cần git) về `~/.local/share/claude-safe`, build image, và tạo lệnh `claude-safe`:
bí danh trong `aliases.sh` của bản cài, nạp bằng một dòng thêm vào `~/.bashrc` và `~/.zshrc`.

Mỗi lần dùng, mở terminal mới, đứng ở thư mục gốc của project:
```
claude-safe                    # vào zsh trong container, rồi gõ claude
claude-safe claude --resume    # vào thẳng claude, kèm tham số
claude-history                 # mở lịch sử session mới nhất của project trong VS Code (xem bằng Git Graph)
```

Lệnh trần (không qua `claude-safe`) cần `--env-file <thư mục cài>/compose.env`; thiếu thì Compose báo lỗi (xem diff-7
và "Tính năng thêm: ghi lịch sử").

## Commit gốc: giống devcontainer

Tái hiện: mỗi project một volume `~/.claude` và một volume lịch sử lệnh; gắn project vào `/workspace`; user `node`;
`CLAUDE_CONFIG_DIR` (nên `.claude.json` nằm trong volume); firewall chạy sau khi container khởi động, có cơ chế chờ
(`healthcheck` + `up --wait` thay cho `waitFor`); container chạy nền, mỗi cửa sổ `exec` vào; Claude Code tự cập nhật;
`TZ` lấy từ máy thật lúc build (mặc định `America/Los_Angeles`); mỗi project một image, build lại từ cache mỗi lần mở
(`pull_policy: build`).

Hai chỗ không thể giống hệt:
- Compose không tự tính được `${devcontainerId}` từ đường dẫn, nên volume đặt tên theo `PROJECT_NAME` (từ diff-7: theo
  tên thư mục project, do Compose tự lấy).
- Công cụ devcontainer tự đánh dấu thư mục project là `safe.directory` của git; Compose không làm, nên đặt qua
  biến `GIT_CONFIG_*`. Thiếu thì git từ chối mọi lệnh trong project ("detected dubious ownership"), vì thư mục gắn từ
  máy thật có chủ sở hữu khác user `node`.

Đã kiểm chứng: `up -d --wait` chỉ báo Healthy sau khi firewall chạy xong; hai lần `exec` vào cùng một container;
`example.com` bị chặn.

Còn mở: theo dõi upstream. Định kỳ so `Dockerfile` và `init-firewall.sh` với nhánh `main` của
`anthropics/claude-code`, nhất là danh sách domain trong firewall, rồi build lại nếu có thay đổi.

## diff-1: firewall chạy trước mọi thứ, lỗi thì không chạy gì

- **Bản gốc:** firewall là `postStartCommand`; `waitFor` chỉ chờ script chạy xong, không quan tâm thành hay bại.
- **Ở đây:** firewall ở `entrypoint`, nối bằng `&&`: lỗi thì không lệnh nào chạy.
- **Vì sao:** mục tiêu của sandbox là chạy `--dangerously-skip-permissions` an toàn, nên không bao giờ được vào
  container khi firewall chưa bật. Đặt ở `entrypoint` chứ không ở `command`, vì lệnh truyền vào
  `run --rm claude <lệnh>` thay thế `command` và sẽ bỏ qua firewall.
- **Được:** không có cách nào vào container không có firewall.
- **Mất:** firewall lỗi thì không dùng được sandbox cho tới khi sửa xong (đó là chủ ý).
- **Kiểm chứng:** bỏ `cap_add` để firewall lỗi. Commit gốc: container vẫn Healthy, vẫn vào được, `example.com`
  trả về 200 (không có firewall). diff-1: container dừng với mã 4, `up --wait` báo lỗi. Lệnh truyền vào `run` cũng
  chỉ chạy sau khi firewall bật xong.

## diff-2: mỗi cửa sổ một container dùng một lần (`run --rm`)

- **Bản gốc:** một container mỗi project, chạy nền; mọi cửa sổ vào chung.
- **Ở đây:** mỗi cửa sổ `run --rm` một container mới, xóa khi thoát. Các cửa sổ cùng project dùng chung volume.
- **Vì sao:** xóa sạch mọi thứ ngoài volume sau mỗi lần dùng. Nếu Claude bị prompt injection rồi cài thứ gì (gói npm
  toàn cục, script trong `~/.zshrc`, file trong `/tmp`), tất cả mất khi thoát. Một lệnh duy nhất, không phải nhớ
  `down`; không cần cơ chế chờ firewall (shell nối tiếp firewall trong cùng một lệnh).
- **Được:** môi trường luôn bắt đầu đúng từ image; firewall phân giải lại IP mỗi lần mở; không có container nằm chờ.
- **Mất (khi mở nhiều cửa sổ cùng project):**
  - Không gọi được `localhost` của nhau; các phiên `claude` không nhắn tin được cho nhau.
  - Mỗi container đánh số PID từ 1, nên `claude` ở các cửa sổ thường cùng PID và ghi đè sổ đăng ký
    `~/.claude/sessions/<PID>.json` của nhau. Đã kiểm chứng (2026-10-02, hai phiên tương tác, Remote Control thật):
    chỉ sổ đăng ký sai; Remote Control, transcript, memory, đăng nhập không bị ảnh hưởng.
  - Nhiều container cùng làm mới một token: chưa kiểm chứng (xấu nhất là một cửa sổ bị đòi đăng nhập lại).
- **Đã cân nhắc:** container chạy nền như bản gốc (`up -d --wait` + `exec` + `down`, cần cơ chế chờ firewall), và
  một script tự mở, tự vào chung, tự dọn khi cửa sổ cuối thoát (cần một script cho mỗi loại shell). Chọn `run --rm` vì
  đơn giản nhất, chạy được trên mọi hệ điều hành chỉ với Docker, và giữ được "xóa sạch sau mỗi lần dùng".

## diff-3: tắt tự cập nhật Claude Code

- **Bản gốc:** Claude Code tự cập nhật.
- **Ở đây:** `DISABLE_AUTOUPDATER=1`.
- **Vì sao:** với `run --rm`, bản cập nhật nằm trong lớp ghi của container và mất khi thoát, nên lần sau lại tải lại.
- **Được:** không tải lại mỗi lần; biết chính xác phiên bản đang chạy.
- **Mất:** phải build lại image để cập nhật. Bước `npm install …@latest` nằm trong cache nên build lại thường vẫn ra bản
  cũ: dùng `docker build --no-cache`, hoặc khóa `--build-arg CLAUDE_CODE_VERSION=<số>` rồi đổi số khi cập nhật.

## diff-4: một image cho mọi project

- **Bản gốc:** mỗi project một image.
- **Ở đây:** `image: claude-safe` cho mọi project.
- **Vì sao:** không đặt thì Compose tạo và giữ một image riêng cho mỗi project (`claude-<project>-claude`), và build
  riêng cho từng project.
- **Được:** một image, build một lần, một chỗ để cập nhật.
- **Mất:** không có project nào dùng image riêng được (muốn thì phải tách file compose).

## diff-5: đặt múi giờ lúc chạy

- **Bản gốc:** `TZ` ghi vào image lúc build, lấy từ máy thật, mặc định `America/Los_Angeles`.
- **Ở đây:** `TZ: Asia/Ho_Chi_Minh` trong `environment:`, ghi đè giá trị trong image lúc chạy.
- **Vì sao:** Windows thường không có biến `TZ`, nên bản gốc chạy giờ Los Angeles. Sai múi giờ thì Claude Code thấy
  sai ngày (mỗi sáng ở Việt Nam, Los Angeles hay UTC vẫn là hôm trước), giờ trong commit git và log cũng sai. Đặt lúc
  chạy thay vì lúc build: đổi múi giờ không cần build lại, một image dùng cho mọi múi giờ, và lệnh build không cần tham
  số.
- **Được:** đúng giờ Việt Nam; đổi bằng một dòng.
- **Mất:** múi giờ ghi trong `compose.yaml`, người dùng ở múi giờ khác phải sửa dòng này.
- **Kiểm chứng:** với image build bằng `TZ=Asia/Ho_Chi_Minh`, đặt `TZ` lúc chạy thành `America/New_York` hay `UTC`
  thì `date`, Node.js (`Intl...timeZone`) và giờ trong commit git đều theo giá trị lúc chạy.

## diff-6: build image riêng bằng `docker build`

- **Bản gốc:** build mỗi lần mở (`pull_policy: build` ở commit gốc).
- **Ở đây:** `compose.yaml` không còn phần `build:`; build bằng `docker build -t claude-safe <thư mục>/anthropic`,
  một lần trên mỗi máy và mỗi khi sửa `Dockerfile` hoặc `init-firewall.sh`. `pull_policy: never`.
- **Vì sao:**
  - Build mỗi lần mở tốn khoảng 5 giây dù không có gì đổi (đo được: 7,8–8,6 giây so với 2,8–3,0 giây), và có thể cần
    mạng để kiểm tra image gốc `node:20` (chưa kiểm chứng trường hợp mất mạng).
  - `compose build` đòi đặt `PROJECT_NAME`, `PROJECT_DIR` dù build không dùng tới; tách ra thì hết.
  - Mở đường cho việc chạy từ thư mục project bằng `--project-directory .`, khi đó `build: context: .` sẽ trỏ nhầm
    vào thư mục project.
  - `pull_policy: never`: thiếu image thì báo lỗi rõ ràng "No such image", thay vì tự tải
    `docker.io/library/claude-safe` từ Docker Hub.
- **Được:** mở nhanh; chủ động quyết định lúc nào image đổi (nhất là phiên bản Claude Code); `compose.yaml` chỉ còn
  phần chạy.
- **Mất:** máy mới phải chạy `docker build` một lần; sửa `Dockerfile` phải nhớ build lại.
- **Đã cân nhắc:** `pull_policy: build` (giống bản gốc, tự thấy `Dockerfile` đã sửa, chậm hơn khoảng 5 giây mỗi lần);
  giữ `build:` với `pull_policy: never` (mở nhanh, nhưng không dùng được với `--project-directory .` và vẫn đòi hai biến
  khi build).

## diff-7: cài một lệnh, chạy bằng `claude-safe` từ thư mục project

- **Bản gốc:** mở project bằng VS Code (hay Dev Containers CLI); `${devcontainerId}` tự tính từ đường dẫn.
- **Trước diff-7:** mỗi lần dùng phải đặt hai biến `PROJECT_DIR`, `PROJECT_NAME` (cú pháp khác nhau ở mỗi shell) rồi
  mới chạy được; máy mới phải tự lấy repo, build, nhớ lệnh.
- **Ở đây:** `install.sh` (khoảng 20 dòng) tải repo, build image, tạo `claude-safe`. `claude-safe`
  chạy `docker compose -f <cài>/compose.yaml --env-file <cài>/compose.env --project-directory . run --rm claude`:
  - `--project-directory .`: `.` trong `compose.yaml` là thư mục đang đứng, nên `.:/workspace` thay được `PROJECT_DIR`.
  - Tên project, tức tiền tố tên volume, do Compose tự lấy từ tên thư mục và tự chuẩn hóa (`My Shop_1` thành
    `myshop_1`), nên thay được `PROJECT_NAME`, và giống nhau trên mọi shell.
  - `--env-file <cài>/compose.env` (không có `COMPOSE_PROJECT_NAME`): Compose đọc file `.env` trong thư mục project, và
    `COMPOSE_PROJECT_NAME` trong `.env` của project sẽ đổi tên project, tức là gắn **volume của project khác** (đăng
    nhập, session, memory). Chỉ định `compose.env` thì Compose không đọc `.env` của project.
  - Volume đổi tên thành `claude-config`, `claude-commandhistory` (thành `<tên thư mục>_claude-config`): nếu chính project
    dùng Compose (cùng tên project) và có volume tên `config`, hai bên sẽ dùng chung volume.
- **Vì sao gọn như vậy:** không có dòng code nào tự tính tên hay sửa `PATH`: `claude-safe` là một bí danh cố định.
- **Được:** máy mới chỉ cần Docker và một lệnh cài; một lệnh dùng; không biến môi trường; `.env` của project không chiếm
  được volume của project khác.
- **Mất:**
  - Dùng lệnh trần thì phải nhớ `--env-file`; ở diff-7, quên thì `.env` của project lại đổi được tên (từ khi có ghi
    lịch sử, quên thì Compose báo lỗi).
  - Phải đứng ở thư mục gốc của project: container chỉ thấy thư mục đang đứng.
  - Hai thư mục cùng tên ở hai nơi dùng chung volume; đổi tên thư mục project thì ra volume mới (đăng nhập lại, không
    thấy session cũ, dù vẫn còn trong volume cũ).
  - Tên volume không còn như trước diff-7 (`claude-<tên>_config`): volume cũ không được dùng lại.
  - Windows chỉ dùng được từ Git Bash (không có lệnh cho cmd, PowerShell). Git Bash tự đổi tham số bắt đầu bằng `/`
    thành đường dẫn Windows trước khi đưa cho `docker`: `claude-safe cat /etc/hosts` thành
    `C:/Program Files/Git/etc/hosts`; viết `//etc/hosts` để tránh.
  - Cài lại ghi đè thư mục cài, kể cả `aliases.sh` (sửa tay trong đó sẽ mất).
- **Kiểm chứng** (cài vào `HOME` tạm, tải từ bản nén `git archive` của repo, giống bản GitHub trả về):
  script cài tải đúng, build được, tạo `claude-safe`; cài lại không thêm dòng nạp trùng.
  `claude-safe` (lúc còn `install.cmd`: từ bash, cmd và PowerShell) cho cùng tên (`My Shop_1` thành `myshop_1`,
  `Dự án (v2)` thành `dnv2`); thư mục có `.env` ghi `COMPOSE_PROJECT_NAME=shop` vẫn dùng volume của chính nó. Chưa thử trên macOS, Linux thật và
  với remote thật.
- **Đã cân nhắc:**
  - Truyền tên bằng `-p claude-<tên thư mục>`: xem mục "Vì sao không dùng `-p`" ngay dưới.
  - Đặt `name:` cứng trong `compose.yaml`: không chặn được `.env` (`COMPOSE_PROJECT_NAME` ưu tiên hơn `name:`), và mọi
    project dùng chung một volume. Đã thử cả hai điều.
  - Script cài thêm thư mục cài vào `PATH` (registry trên Windows, khối đánh dấu trong file cấu hình shell): dài hơn
    nhiều, và `setx PATH` của Windows cắt `PATH` dài hơn 1024 ký tự.
  - Tên `claude-safe` (lệnh, image, thư mục cài, repo): `claudebox`, `claude-box`, `claude-pod`, `claude-sandbox` đều
    đã là tên của nhiều dự án khác cùng loại. "safe" là lời hứa mạnh hơn những gì setup làm được (firewall vẫn cho đi
    tới GitHub, npm, API của Anthropic; Claude vẫn sửa được mọi thứ trong project), và tên có chữ "Claude" (nhãn hiệu
    của Anthropic): hợp để dùng cá nhân, phải đổi nếu thương mại hóa.
  - Thêm `install.cmd` cho cmd và PowerShell (đã có, rồi bỏ): ghi `claude-safe.cmd` một dòng vào
    `%LOCALAPPDATA%\Microsoft\WindowsApps` (thư mục vốn có trong `PATH`), đã chạy được. Bỏ vì phải giữ hai script đồng
    bộ, và đường dẫn cài phải khác nhau theo hệ điều hành (`LOCALAPPDATA` hay `~/.local/share`, kèm `cygpath` cho Git
    Bash); dev trên Windows hầu như đã có Git Bash.
  - Ghi thẳng từng dòng `alias` vào `~/.bashrc` (đã có, rồi bỏ): muốn cài lại cập nhật được bí danh thì phải xóa dòng
    cũ trong file của người dùng (file tạm, giữ symlink). Nạp `aliases.sh` thì `~/.bashrc` chỉ thêm một dòng cố định.

### Vì sao không dùng `-p`

`-p claude-<tên thư mục>` là cách đã làm và chạy được trước bản hiện tại. Nó có hai ưu điểm: `-p` có ưu tiên cao nhất
nên tự chặn được `.env` của project (không cần `--env-file`), và tên có tiền tố `claude-`. Bỏ vì nó kéo theo gần hết số
code của phần cài và chạy:

```
truyền -p claude-<tên>
  → phải tự chuẩn hóa tên thư mục: Compose từ chối tên có chữ hoa, khoảng trắng... khi truyền bằng -p,
    dù nó tự chuẩn hóa khi tự lấy tên thư mục
    → claude-safe cần logic: bash dùng tr/sed; cmd không có hàm đổi chữ thường, phải duyệt từng ký tự
      → không viết được thành một dòng bí danh, phải là file script riêng (claude-safe, claude-safe.cmd)
        → file script phải nằm trong PATH
          → script cài phải sửa PATH: registry trên Windows (không dùng được setx PATH), khối đánh dấu trong ~/.bashrc
```

Không có `-p` thì cả chuỗi biến mất: Compose tự lấy và chuẩn hóa tên, `claude-safe` là một lệnh cố định, script cài chỉ
thêm một dòng nạp bí danh. (Lúc so sánh còn hỗ trợ cmd, nên bảng dưới có hai script.)

| | Có `-p` | Không `-p` (lúc so sánh) |
|---|---|---|
| File script `claude-safe` | 2 file (13 và 35 dòng) | Không có |
| Script cài (có tự tải repo) | 2 file, khoảng 50–60 dòng mỗi file | 2 file, khoảng 17 dòng mỗi file |
| Sửa `PATH` | Có | Không |
| Tên giống nhau giữa bash và cmd | **Không**, với tên thư mục có dấu: `Dự án (v2)` thành `claude-d---n--v2-` ở cmd nhưng `claude-d------n--v2-` ở Git Bash không có locale UTF-8 (bash đếm `ự` là 3 byte), tức là hai volume khác nhau | Có: Compose đặt tên (`dnv2` ở cả hai) |

Hai ưu điểm của `-p` đều có cách thay rẻ hơn: `.env` chặn bằng `--env-file`, nằm sẵn trong `claude-safe` nên người dùng
không phải nhớ; tiền tố `claude-` (để không trùng với Compose của chính project) chuyển sang tên volume
(`claude-config`).

## Tính năng thêm: ghi lịch sử

Không có trong bản gốc. Mục đích: ghi lại mọi thay đổi Claude Code tạo ra trong `~/.claude` (transcript, `.claude.json`,
memory, settings...) trước và sau mỗi lượt chat, bằng git, để hiểu Claude Code hoạt động thế nào, kiểm tra Claude có sửa
cấu hình của chính nó không, khôi phục, hay thống kê.

- **Luôn bật:** `compose.yaml` gắn vào container `history/managed-settings.json` (hook ở `SessionStart`,
  `UserPromptSubmit`, `Stop`, `SessionEnd`) và `history/hook-commit.sh`, cả hai chỉ đọc, cùng thư mục lịch sử.
- **Lưu ở:** `~/.local/share/claude-safe-history`, **ngoài** thư mục cài (cài lại xóa thư mục cài). Xem:
  `git --git-dir=<thư mục lịch sử>/<project>/<session id> log --stat`, hoặc `claude-history [<session id>]` ở thư
  mục project (`history/view.sh`): repo lịch sử là bare repo, VS Code không mở được, nên lệnh clone nó ra
  `~/.cache/claude-safe-view/<project>/<session id>` (mở lại thì `git pull`) rồi `code` mở bản clone. Tên project lấy
  từ `docker compose ... config`, nên luôn khớp với tên Compose dùng lúc chạy.
- **Mỗi session một repo** (`<project>/<session id>`): commit của một repo chỉ chứa thay đổi của đúng session đó (với
  file riêng của session) cộng file dùng chung. Không cần khóa: chỉ hook của chính session ghi vào repo, và chúng chạy
  lần lượt.
- **Chọn file bằng UUID, không bằng tên thư mục.** `info/exclude` của mỗi repo:
  ```
  *????????-????-????-????-????????????*    bỏ mọi file/thư mục có UUID trong tên
  !*<session id>*                           trừ của chính session
  .credentials.json
  sessions/                                 sổ đăng ký phiên: nhiễu
  plugins/marketplaces/                     repo git: git chỉ lưu được con trỏ, và cảnh báo trong log
  ```
  File riêng của một session luôn có session id trong tên (transcript `<id>.jsonl`, `projects/.../<id>/` của subagent,
  `file-history/<id>/`, `session-env/<id>/`, `todos/<id>-...`), file dùng chung thì không. Nhờ vậy hook không cần biết
  cấu trúc thư mục của Claude Code, và thư mục theo session mà bản sau thêm vào tự được xử lý đúng.
- **Đường dẫn tuyệt đối** cho các file gắn vào: với `--project-directory .`, đường dẫn tương đối tính từ thư mục
  project, không phải thư mục cài. `compose.env` trong repo ghi sẵn, Compose thay `${HOME}` lúc chạy:
  ```
  CLAUDE_SAFE_HOME=${HOME}/.local/share/claude-safe
  ```
  Git Bash đưa `HOME` cho `docker` dưới dạng `C:\Users\...`, nên một dòng dùng được trên mọi máy. Bản trước cho script
  cài ghi đường dẫn vào `compose.env`: thêm vài dòng, và Git Bash phải đổi `/c/...` thành `C:/...` bằng `cygpath -m`.
  Hệ quả có lợi: lệnh trần thiếu `--env-file` giờ báo lỗi (thiếu `CLAUDE_SAFE_HOME`) thay vì lặng lẽ đọc `.env` của
  project.
- **Script cài tạo sẵn thư mục lịch sử:** nếu để Docker tự tạo, nó thuộc root, quyền 755, và hook (user `node`) không ghi
  được (đã gặp).
- **Được:** hook khoảng 20 dòng (không khóa, không thử lại khi tranh chấp, không phụ thuộc cấu trúc thư mục); nhiều phiên
  cùng project không trộn file riêng vào commit của nhau; skill đồng bộ theo mã tổ chức (hơn 230 file ở lượt đầu) tự bị
  loại vì tên có UUID.
- **Mất:**
  - File dùng chung (`.claude.json`, `history.jsonl`, memory...) vào repo của mọi session đang chạy (lưu trùng), và khi
    nhiều phiên chạy cùng lúc thì không biết phiên nào sửa chúng. Đây là giới hạn bản chất: thứ gì dùng chung thì thay
    đổi lên nó không thuộc riêng phiên nào. Khi quan sát hành vi theo từng lượt chat, chỉ mở một cửa sổ cho project.
  - Session bị dừng ngang (container bị giết): phần ghi sau hook cuối chỉ vào lịch sử khi **resume đúng session đó**
    (resume giữ nguyên session id, trừ `--fork-session`), lẫn vào commit `[session-start]` lúc đó. Dữ liệu vẫn đầy đủ
    trong volume.
  - Mọi file có UUID khác trong tên bị bỏ qua hẳn (skill, plugin đồng bộ, `cache/model-catalog/...`): muốn ghi thì thêm
    một dòng `!` vào mẫu.
  - Dựa trên quy ước "file riêng của session có session id trong tên", không có tài liệu nào cam kết.
  - Repo nằm trên thư mục gắn từ máy thật: trên Windows mỗi lần commit khoảng 0,2–0,6 giây.
  - Không tắt được theo từng lần chạy: mọi session đều ghi. Muốn tắt hẳn thì bỏ ba dòng gắn lịch sử và dòng
    `CLAUDE_HISTORY_PROJECT` trong `compose.yaml`; khi đó lệnh trần thiếu `--env-file` không còn bị báo lỗi.
- **`index.lock` bị bỏ lại** khi hook bị giết giữa lúc commit: hook xóa nó ở `SessionStart`, vì lúc session vừa khởi
  động (kể cả resume) không ai khác ghi repo đó.
- **Kiểm chứng** (cài vào `HOME` tạm, chưa đăng nhập; 2026-10-03): hai session cùng project chạy song song có hai
  repo riêng, không repo nào chứa file mang UUID của session khác, log không lỗi; `index.lock` giả bị dọn ở
  `session-start` và commit tiếp tục. Cài và commit được từ Git Bash (`~/.local/share`); nguồn mount trộn `\` và `/`
  (`C:\Users\...\x/.local/share/...`) chạy được; lệnh trần thiếu `--env-file` báo lỗi. Mẫu UUID thử trên cấu trúc thư
  mục giả gồm subagent, `file-history`, `session-env`, `todos`, skill đồng bộ. Chưa thử: commit `[after-turn]` khi đã
  đăng nhập, phiên dài, resume thật.
- **Đã cân nhắc:**
  - Tùy chọn, bằng lệnh riêng `claude-safe-history` (thêm `-f history/compose.history.yaml`; đã có, rồi bỏ): quên gõ
    đúng lệnh là mất lịch sử của session đó, và thêm một file compose, một bí danh.
  - Tiêu đề commit kèm 70 ký tự đầu của prompt (đã có, rồi bỏ): dễ lướt trong Git Graph, nhưng thêm code và đã gây
    hai lỗi (cắt sai ở dấu nháy khi đọc JSON bằng sed; treo lượt chat vài chục giây với prompt dài, vì gsub của jq 1.6
    chạy theo bình phương độ dài). Prompt vốn đã nằm trong transcript của chính commit đó.
  - Một repo cho mỗi project, hook `git add -A` (bản trước): commit của phiên này lẫn file riêng của phiên khác cùng
    project; cần khóa (nhiều hook cùng ghi một repo). Ưu điểm duy nhất: phần còn sót của session bị dừng ngang được commit
    ở lần hook kế tiếp của bất kỳ session nào.
  - Hook chỉ `git add` file của session mình trong một repo chung: phải biết cấu trúc thư mục; file của session đã chết
    không ai commit; phức tạp hơn.
  - Một repo cho mỗi project, mỗi session một `git worktree` (nhánh, `HEAD`, index riêng; đã thử với git 2.39 trong
    image): hook vẫn chỉ `git add -A` và `commit`, file dùng chung chỉ lưu một lần, xem mọi session bằng
    `git log --all`, so sánh bằng `git diff A B`. Nhưng thêm bước chuẩn bị: `extensions.worktreeConfig` và
    `core.excludesFile` riêng mỗi worktree (`info/exclude` dùng chung), commit rỗng làm gốc (git 2.39 chưa có
    `worktree add --orphan`), thư mục giả cho `worktree add --no-checkout` (phải giữ, nếu không `prune` xóa worktree),
    tắt `gc.auto`; và có trạng thái dùng chung: hai session mở lần đầu cùng lúc tranh nhau tạo repo, cần khóa. Muốn xem
    chung thì vẫn gom được các repo riêng bằng `git fetch` vào một repo khác, không phải đổi hook.
  - Mỗi cửa sổ một volume `~/.claude` riêng: tách hoàn toàn, nhưng mỗi cửa sổ phải đăng nhập, mất `/resume` và memory
    chung giữa các cửa sổ.
  - Lưu lịch sử trong volume Docker: nhanh hơn 10–20 lần, nhưng chỉ xem được qua container, xóa volume là mất, và volume
    mới thuộc root.

## Thiếu do không dùng công cụ devcontainer

Những thứ công cụ devcontainer (VS Code, Dev Containers CLI) tự làm, không nằm trong `devcontainer.json`:

| Điểm | Ảnh hưởng |
|---|---|
| Cấu hình VS Code (`customizations.vscode`) | Không ảnh hưởng khi dùng terminal |
| `consistency=delegated` ở mount project | Không ảnh hưởng: Docker hiện nay bỏ qua |
| Network: Compose tạo network riêng cho mỗi project, bản gốc dùng default bridge | Cách ly tốt hơn: dải `/24` mà firewall cho phép chỉ chứa container của chính project. Firewall đi theo nhánh "Restoring Docker DNS rules" (đã chạy được) |
| Chép `~/.gitconfig` từ máy thật | **Còn mở:** Claude không `git commit` được khi chưa có danh tính git |
| Chuyển tiếp SSH agent và git credential helper | Cố ý không làm: an toàn hơn; push từ máy thật |
| Chỉnh UID của `node` cho khớp máy thật (`updateRemoteUserUID`) | Chỉ ảnh hưởng máy Linux có UID khác 1000: không ghi được vào project |
| Tên volume `claude-code-config-<id>` | Chuyển giữa hai cách thì phải đăng nhập lại, không thấy session cũ |
| Đánh dấu thư mục project là `safe.directory` | Đã bù ở commit gốc bằng `GIT_CONFIG_*` |

## Phương án đã thử và bỏ

**Một volume chung cho mọi project** (để chỉ đăng nhập một lần). Claude Code gắn session, memory và trust theo đường
dẫn, nên phương án này phải gắn mỗi project vào một đường dẫn riêng (`/workspace/<tên>`) để chúng không trộn vào nhau.
Bỏ vì khi nhiều project chạy song song, nhiều container cùng ghi một volume:
- Sổ đăng ký `sessions/<PID>.json` bị ghi đè lẫn nhau (PID trùng giữa các container).
- Nhiều container cùng làm mới một token (chưa kiểm chứng).
- Ghi lịch sử bằng git: một commit lẫn thay đổi của project khác.
- Không còn cách ly giữa các project (một project bị prompt injection đọc được session và token của project khác).
Mỗi project một volume (như bản gốc) gói các vấn đề này lại trong phạm vi một project; cái giá là mỗi project mới phải
đăng nhập một lần. Với volume riêng, đường dẫn riêng không còn cần thiết, nên project gắn vào `/workspace` như bản gốc.
