# 🚀 SaaS Web CLI (saas_install)

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Debian%2012%2B%20%7C%20Ubuntu%2022.04%2B-lightgrey)
![Node](https://img.shields.io/badge/Node.js-%3E%3D20-success)
![Next.js](https://img.shields.io/badge/Framework-Next.js-black)

专为 **独立开发者** 和 **初创团队** 打造的 Node.js (尤其是 Next.js) 生产环境轻量级自动化部署与管理工具。

告别繁琐的手动配置，将环境搭建 (Node.js 20, PM2, Nginx, Certbot)、性能调优 (Swap 挂载、静态资源加速)、SSL 证书部署以及日常运维，统统整合进了一个交互式的全局命令 `saas` 中。只需执行一次安装，即可实现生产环境的**零宕机热更新**与**一键灾难恢复**。

---

## 🚀 一键执行命令

```bash
apt update -y && apt install curl wget sudo -y && curl -sSLo /usr/local/bin/saas https://raw.githubusercontent.com/zdaben/saas_install/main/saas.sh && chmod +x /usr/local/bin/saas && saas install
```

## ✨ 核心亮点

- 🤖 **一键自动化部署**：交互式配置域名与端口，自动处理 NPM 依赖安装、Prisma 生成与 Next.js 生产环境构建。
- 🛡️ **生产级环境加固**：智能检测物理内存并配置 Swap 防爆内存；使用 PM2 守护进程确保应用 24/7 高可用。
- ⚡ **Nginx 深度优化**：自动配置反向代理，**并将 `/_next/static/` 静态资源交由 Nginx 物理直吐**，极大降低 Node.js 负载，提升页面并发响应速度。
- 🔄 **零宕机平滑升级**：一条 `saas update` 命令，自动拉取依赖、重新编译并执行 PM2 内存热重载 (Reload)，更新不断线。
- 🔒 **全自动 SSL 证书**：无缝集成 Certbot，自动申请 Let's Encrypt HTTPS 证书并配置自动续期。
- 📦 **傻瓜式数据灾备**：自动打包备份 `.env` 环境变量、Prisma 配置与 SQLite 本地数据库文件，支持列表式交互恢复。

---

## 🛠️ 环境要求

- **操作系统**: Debian 12+ 或 Ubuntu 22.04+ (纯净系统最佳)
- **系统权限**: `root` 用户
- **网络前置**: 请提前将您的域名（如 `app.example.com`）解析到服务器的公网 IP。

---

## ⚠️ 部署前必读 (极其重要)

本脚本主要用于**运行环境配置与应用构建**，它**不会**帮你从 GitHub 拉取代码。
在执行安装脚本之前，**请务必将您的 Next.js 项目源码传输或克隆到对应的网站目录下**。

例如，如果你打算绑定的域名是 `app.example.com`，请提前执行：
```bash
mkdir -p /var/www/app.example.com
# 将你的源码通过 git clone、scp 或 sftp 上传到该目录中
# 确保该目录下有 package.json 等核心文件
```

---

## 📦 快速开始

### 1. 下载并运行脚本

```bash
# 下载脚本
wget -O saas.sh https://raw.githubusercontent.com/zdaben/saas_install/main/saas.sh

# 赋予执行权限
chmod +x saas.sh

# 运行初始化安装
./saas.sh install
```

### 2. 交互式配置

安装过程中，脚本会向您询问以下信息（直接回车可使用默认值）：
1. **绑定的域名** (例如: `app.example.com`)
2. **应用运行端口** (例如: `3000`)
3. **PM2 守护名称** (例如: `saas-web`)
4. 是否自动申请 SSL 证书及其通知邮箱。

安装完成后，脚本会自动将自身注册为全局命令 `saas`。此后，您可以在服务器的任何目录下直接使用 `saas` 命令。

---

## 💻 命令行指南 (CLI Usage)

在终端中输入 `saas` 即可呼出高亮控制面板并查看当前运行状态。

支持的具体命令如下：

| 命令 | 说明 |
| :--- | :--- |
| `saas` | 查看主面板（包含访问地址、应用名称、内部端口、运行目录等概览） |
| `saas install` | 初始化环境配置与安装部署（首次运行） |
| `saas update` | **（最常用）** 当你上传了新代码后，执行此命令自动重新编译并平滑重启服务 |
| `saas status` | 查看 Node/Nginx 版本状态及 PM2 进程列表详细资源占用 |
| `saas top` | 进入 PM2 Monit 实时动态资源监控大屏 (按 `Ctrl+C` 退出) |
| `saas restart` | 强制重启 PM2 Node 进程以及 Nginx 服务 |
| `saas backup` | 打包备份环境变量 (`.env`)、Prisma 配置及本地数据库 (`.sqlite`/`.db`) |
| `saas recover` | 呼出交互式面板，从历史归档中选择并恢复环境配置与本地数据 |
| `saas uninstall` | 彻底卸载应用进程，清理 Nginx 代理规则、证书及相关文件目录 |

---

## 📂 目录结构说明

- **网站运行目录**: `/var/www/{你的域名}` (您的源码应存放于此)
- **全局配置存储**: `/etc/saas_config.sh` (持久化保存您的域名、端口等信息)
- **全局命令路径**: `/usr/local/bin/saas`
- **数据备份目录**: `/var/www/{你的域名}/backup/`

---

## ❓ 常见问题 (FAQ)

**Q: 运行 `saas update` 时提示编译失败怎么办？**
A: 请检查您上传的源码是否完整，或者是否在本地测试过 `npm run build`。脚本在编译失败时会自动中止重载操作，您的线上旧版本仍将保持正常运行。查看具体报错修复源码后，重新上传并运行 `saas update` 即可。

**Q: 我的项目使用了本地 SQLite 数据库，每次更新会覆盖吗？**
A: 不会。`saas update` 仅执行依赖安装和重新编译，不会删除您的数据库文件。但为了安全，建议在进行重大更新前先执行一次 `saas backup`。

**Q: 可以修改 Nginx 配置吗？**
A: 当然可以。Nginx 的配置文件生成在 `/etc/nginx/sites-available/{你的域名}.conf`，您可以随意修改，修改后执行 `nginx -t && systemctl reload nginx` 或 `saas restart` 生效。

---

## 📄 开源协议

本项目基于 [MIT License](LICENSE) 协议开源。欢迎提交 Issue 或 Pull Request 来共同完善这个工具！
