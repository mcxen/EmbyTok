# NAS Docker 部署经验总结

本文是从零到可用的 NAS/Docker 部署实操总结，重点覆盖飞牛（fnOS）和常见踩坑。

## 目标

- 容器内提供 Web（静态站点）+ 文件服务 API
- NAS 上视频目录挂载到容器 `/media`
- 浏览器访问 `http://NAS_IP:5176` 正常播放

## 快速路径

### 1) 直接使用 Compose（有项目源码）

```bash
cd /path/to/EmbyTok
EMBYTOK_MEDIA_PATH=/vol02/1000-0-c6abec40 EMBYTOK_PORT=5176 docker compose up -d --build
```

### 2) 只有镜像包（无源码）

```bash
docker load -i /path/to/embytok_local_amd64.tar

docker run -d --name embytok --restart unless-stopped \
  -p 5176:5176 \
  -e HOST=0.0.0.0 -e PORT=5176 -e SERVE_WEB=true \
  -e WEB_ROOT=/app/dist -e LAN_CONFIG_FILE=/app/data/lan-media-config.json \
  -e MEDIA_ROOT=/media -e BROWSE_ROOTS=/media \
  -v /path/to/lan-media-config.json:/app/data/lan-media-config.json \
  -v /vol02/1000-0-c6abec40:/media:ro \
  embytok:local
```

## 关键配置要点

### 1) 容器路径必须是 `/media`

宿主机路径和容器路径不是同一个概念。  
容器内只认 `/media`，所以必须把 NAS 真实路径映射到 `/media`：

```text
/vol02/1000-0-c6abec40  ->  /media
```

并且环境变量必须是：

```text
MEDIA_ROOT=/media
BROWSE_ROOTS=/media
```

### 2) 5173 不会启动

`5173` 是开发模式端口，只在 `npm run dev` 时存在。  
Docker 生产模式只监听 `5176`。

### 3) 管理页先建服务

进入 `http://NAS_IP:5176/admin`（管理员密码 `admin`），创建服务并设为当前。  
首页需要选择“文件服务”，并选中服务名（例如 `111`）。

## 常见问题排查

### 1) 镜像拉取失败/超时

优先在飞牛 Docker 的 GUI 里设置镜像源；如果使用命令行：

```bash
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://dockerproxy.com",
    "https://registry.docker-cn.com"
  ]
}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
```

### 2) Mac 是 arm64，但 NAS 需要 amd64（推荐方案）

GHCR 已发布多架构镜像，可直接在本机拉取 amd64 后导出，再上传到 NAS：

```bash
# 登录（私有仓库需要）
docker login ghcr.io -u <user> -p <github_pat>

# 拉取 amd64 架构镜像
docker pull --platform linux/amd64 ghcr.io/<owner>/<repo>:vX.Y.Z

# 导出为 tar
docker save -o embytok_vX.Y.Z_amd64.tar ghcr.io/<owner>/<repo>:vX.Y.Z
```

上传到 NAS 后导入并运行：

```bash
scp embytok_vX.Y.Z_amd64.tar <user>@<nas_ip>:/vol1/1000/DockerSpace/EmbyTok/

ssh <user>@<nas_ip>
cd /vol1/1000/DockerSpace/EmbyTok
sudo docker load -i embytok_vX.Y.Z_amd64.tar
```

接着按“快速路径”的 `docker run` 或 `docker compose` 启动。

### 2) `exec format error`

这是镜像架构不匹配：

- NAS 是 `amd64`（x86_64）
- Mac 默认构建是 `arm64`

需要构建 `linux/amd64` 镜像并再上传。

#### Mac + Colima 构建 amd64

```bash
brew install qemu
colima start -p amd64 --arch x86_64 --runtime docker
export DOCKER_HOST=unix://$HOME/.colima/amd64/docker.sock
docker build -t embytok:local .
docker save -o embytok_local_amd64.tar embytok:local
```

### 3) 首页没视频

API 是正常返回的，但前端没切到服务：

1. 登录页选“文件服务”
2. 服务名选择管理页设置的服务（如 `111`）
3. 必要时退出登录或无痕窗口重进

验证接口：

```text
http://NAS_IP:5176/api/folder/services
http://NAS_IP:5176/api/folder/videos?feedType=latest&serviceId=<ID>
```

## 推荐的最小验证流程

1. `http://NAS_IP:5176/admin` 能看到视频数
2. `.../api/folder/videos` 能返回 `items`
3. 首页选择正确服务后显示视频流

## FAQ

### Q: 为什么映射了本地路径还是看不到视频？

因为容器内路径不对。必须把宿主机路径映射到 `/media`，并把 `MEDIA_ROOT`/`BROWSE_ROOTS` 设为 `/media`。

### Q: 我需要上传整个项目吗？

不需要。上传镜像包后用 `docker run` 即可启动。
