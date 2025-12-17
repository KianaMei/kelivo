## Kelivo Web 部署（Go 网关 + Nginx 静态站）

你要的结构很简单：

- Nginx：只负责静态站 + 反向代理 `/v1/*` 到网关（同域名，避免 CORS）
- Go 网关：鉴权（`ACCESS_CODE`）+ 转发到上游（`UPSTREAM_BASE_URL`）并保留流式响应（SSE）
- 上传：`POST /webapi/upload`（multipart `file`），返回 `/files/<id>` URL

### 1) 准备前端静态文件

把 Flutter Web 构建产物放到 `deploy/webroot/` 下：

- 本地构建（在你自己电脑上做，别在小云主机上折腾）：`flutter build web --release`
- 然后把 `build/web/*` 拷贝到 `kelivo-web/deploy/webroot/`

### 2) 配置环境变量

在 `kelivo-web/deploy/` 下：

- 复制 `.env.example` 为 `.env`
- 填好 `UPSTREAM_BASE_URL`、`UPSTREAM_API_KEY`、`ACCESS_CODE`

### 3) 启动

在 `kelivo-web/deploy/` 下：

- `docker compose up -d --build`

### 4) Kelivo 里怎么填

把 Provider 的配置指向你的站点（Nginx 同域代理）：

- `baseUrl`: `http://<你的域名或IP>/v1`
- `apiKey`: 填 `.env` 里的 `ACCESS_CODE`
- `chatPath`: 保持默认（`/chat/completions`）即可

### 5) 生产建议（别把小鸡搞死）

- 用域名 + HTTPS：可以在 Nginx 前面再放一层 Caddy/Traefik 做自动证书，或直接把 Nginx 换成 Caddy。
- 不要在公网暴露 `gateway` 的 8080 端口：通过 `web` 反代即可（同域，省掉 CORS）。
- `ACCESS_CODE` 必须设置：否则任何人都能用你的上游 Key 烧钱。
- 上传文件会落在 `kelivo-web/deploy/data/`（compose 挂载到容器 `/data`），定期清理或改成对象存储。
