# EmbyTok

EmbyTok 是一个为 Emby 媒体服务器设计的竖屏视频浏览客户端，提供类似 TikTok 的体验，让用户能够以更现代、便捷的方式浏览个人媒体库。

<div style="display:flex; flex-direction:row;">
<img src="https://gitee.com/miguyomi/embytok/raw/master/tmp/1.jpg" width="24%" />
<img src="https://gitee.com/miguyomi/embytok/raw/master/tmp/2.jpg" width="24%" />
<img src="https://gitee.com/miguyomi/embytok/raw/master/tmp/3.jpg" width="24%" />
<img src="https://gitee.com/miguyomi/embytok/raw/master/tmp/4.jpg" width="24%" />
</div>

## 功能特性

- 📱 **TikTok 式浏览体验**：全屏竖屏视频浏览，上下滑动切换视频
- 🎵 **音频控制**：一键静音/取消静音，直观的音量图标反馈
- ❤️ **收藏功能**：点赞并收藏喜欢的视频，支持在收藏夹中浏览
- 🔍 **多种浏览模式**：
  - 最新视频
  - 随机推荐
  - 收藏夹
- 📁 **媒体库管理**：支持多个媒体库的浏览、选择和隐藏
- 🧭 **局域网文件服务模式**：服务端可直接挂载本地文件夹，局域网设备通过浏览器访问并播放
- 🌐 **响应式设计**：适配移动端和桌面端，自动调整布局
- ⏩ **滑动控制进度**：左右滑动调整视频播放进度
- 📦 **Android 应用**：可通过 Capacitor 构建为原生 Android 应用
- 📱 **视图切换**：支持视频流视图和网格视图的一键切换
- 📐 **方向过滤**：可选择只显示垂直、水平或两者都显示的视频
- 🖥️ **全屏模式**：支持进入/退出全屏播放
- 🎯 **自动布局**：根据屏幕方向自动调整最佳显示方式
- 📱 **竖屏优化**：专为手机竖屏体验优化的界面设计
- ♾️ **无限连播模式**：支持视频自动连续播放，无需手动操作
- 📱 **平板模式**：支持平板模式
- 📱 **iOS 原生应用（UIKit）**：支持 Emby / 文件服务 MP4 播放、底部进度条控制、网格“查看全部”

## 技术栈

- React 18
- TypeScript
- Vite
- Tailwind CSS
- Capacitor (用于构建 Android 应用)
- Lucide React (图标)
- 多架构 Docker 支持 (AMD64/ARM64)
- Nginx 生产环境部署
- PWA 支持
- UIKit + AVFoundation (iOS 原生播放器)

## 安装和设置

### 前置要求

- Node.js (v14 或更高版本)
- npm 或 yarn

### 安装步骤

1. 克隆仓库：
   ```bash
   git clone <repository-url>
   cd embytok
   ```

2. 安装依赖：
   ```bash
   npm install
   ```

3. 启动开发环境（前端 + 文件服务后端）：
   ```bash
   npm run dev
   ```
   仅启动前端可使用：
   ```bash
   npm run dev:web
   ```
   前端仅局域网暴露可使用：
   ```bash
   npm run dev:lan
   ```
   如果你要调试“文件服务模式”（含 `/api/admin/*`），也可以使用：
   ```bash
   npm run dev:stack
   ```

4. 构建生产版本：
   ```bash
   npm run build
   ```

## 局域网文件夹服务端

如果你不使用 Emby/Plex，可以直接启用“文件服务”模式。  
管理员在网页管理页中配置多个“视频流服务”（服务名 + 文件夹路径）后，局域网其他设备只需选择服务名称即可使用。

### 1) 构建前端

```bash
npm run build
```

### 2) 启动文件夹服务端

```bash
npm run lan:server
```

若你在开发时看到如下错误：
- `http proxy error: /api/admin/...`
- `connect ECONNREFUSED 127.0.0.1:5176`

表示前端代理已生效，但本地文件服务后端未启动。请使用 `npm run dev`（或 `npm run dev:stack`）同时启动前后端；如果你使用的是 `npm run dev:web`，需要额外启动 `npm run lan:server`。

可选参数：
- `PORT`：服务端端口（默认 `5176`）
- `HOST`：监听地址（默认 `0.0.0.0`，可被局域网访问）
- `WEB_ROOT`：前端静态资源目录（默认 `dist`）
- `SERVE_WEB`：是否托管网页（默认 `true`）
- `LAN_CONFIG_FILE`：服务配置持久化文件（默认 `./lan-media-config.json`）
- `MEDIA_ROOT`：首次启动时可选，用于创建默认视频流服务
- `BROWSE_ROOTS`：管理页可浏览的目录根（逗号分隔）

示例：

```bash
MEDIA_ROOT=/Volumes/Media/Movies PORT=8088 npm run lan:server
```

启动后，控制台会输出局域网访问地址。其他设备打开该地址即可使用浏览器浏览和播放视频。

### 3) 管理页配置服务（管理员执行）

1. 可通过以下任一入口进入管理页：
   - 直接访问 `http://服务端IP:端口/admin`，输入管理员密码 `admin`
   - 在登录页选择 **文件服务** 后点击 **打开管理页面（配置文件夹服务）**
   - 已登录后从左侧菜单进入 **设置**，点击 **管理员面板** 并输入密码 `admin`
2. 在管理页里：
   - 浏览并选择服务端文件夹
   - 填写服务名称
   - 保存并设为当前服务
3. 可重复添加多个服务（例如：电影库、剧集库、纪录片库）。

服务配置会保存到 `lan-media-config.json`，服务端重启后会自动恢复。

### 4) 网页端连接（其他设备）

在登录页选择 **文件服务**，填入服务端地址（例如 `http://192.168.1.50:5176`），然后在“视频流服务名称”中选择服务后连接即可。

## 使用方法

1. 启动应用后，在登录界面输入您的 Emby 服务器信息：
   - 服务器地址（例如：http://192.168.1.100:8096）
   - 用户名
   - 密码（如果需要）

2. 登录成功后，您可以：
   - 上下滑动浏览视频
   - 点击视频播放/暂停
   - 使用右侧控制栏点赞、查看信息、控制音频
   - 通过左上角菜单切换媒体库和浏览模式
   - 左右滑动控制视频播放进度
   - 点击网格图标切换到网格视图

## 构建 Android 应用

1. 确保您已安装 Android Studio 和 Android SDK

2. 添加 Android 平台：
   ```bash
   npm run cap:add
   ```

3. 同步项目：
   ```bash
   npm run cap:sync
   ```

4. 构建 APK：
   ```bash
   ./build-apk.sh
   ```

## iOS 原生应用（UIKit）

最低系统要求：iOS 16 / iPadOS 16。

### 1) 打开项目

使用 Xcode 打开：
```
ios-native/EmbyTokNative.xcodeproj
```

### 2) 配置签名

在 Target → Signing & Capabilities 中选择你的开发团队（个人/企业）。  
如果遇到 Bundle Identifier 冲突，请改成唯一值。

### 3) 运行到真机

1. 选择你的 iPhone/iPad 作为运行目标
2. 点击 Run（▶）
3. 首次运行需在设备设置中信任开发者证书

### 4) 连接方式

支持以下后端：
1. Emby（MP4 直链）
2. 文件服务（Folder Server，局域网）

> 目前 iOS 原生仅实现 MP4 直链播放。Plex/HLS 后续可继续扩展。

## Docker 部署

项目包含 Docker 支持，可以轻松部署为 Web 应用。支持多架构（AMD64/ARM64），可在不同硬件平台上运行。

### 镜像信息

- **镜像名称**：crpi-90mw3693mrc3nsxp.cn-shanghai.personal.cr.aliyuncs.com/migumigu/embytok
- **支持架构**：AMD64 (x86_64), ARM64 (aarch64)
- **标签**：latest, 1.0.2

### 直接使用 Docker 命令

```bash
# 拉取并运行镜像（Docker 会自动选择适合您硬件架构的版本）
docker run -d \
  --name embytok-web \
  --restart unless-stopped \
  -p 8080:80 \
  crpi-90mw3693mrc3nsxp.cn-shanghai.personal.cr.aliyuncs.com/migumigu/embytok:latest
```

### 使用 Docker Compose

#### 简单部署

使用 `docker-compose.simple.yml` 进行快速部署：

```yaml
version: '3.8'

services:
  # EmbyTok 前端应用 - 简单版配置
  embytok:
    image: crpi-90mw3693mrc3nsxp.cn-shanghai.personal.cr.aliyuncs.com/migumigu/embytok:latest
    container_name: embytok-web
    restart: unless-stopped
    ports:
      - "5175:80"  # Web界面端口
    environment:
      - NODE_ENV=production
    network_mode: bridge
networks: {}
```

运行简单配置：

```bash
docker-compose -f docker-compose.simple.yml up -d
```

默认情况下，应用将在端口 5175 上可用。

## 配置

应用使用 localStorage 存储以下用户配置：
- 服务器配置（URL、用户ID、访问令牌）
- 隐藏的媒体库列表

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个项目。

## 许可证

[MIT License](LICENSE)

## 免责声明

EmbyTok 是一个非官方的 Emby 客户端，与 Emby 官方没有关联。使用时请确保遵守您所在地区的相关法律法规。
