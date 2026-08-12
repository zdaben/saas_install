# 🚀 SaaS Web CLI (saas_install)

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Debian%2012%2B%20%7C%20Ubuntu%2022.04%2B-lightgrey)
![Node](https://img.shields.io/badge/Node.js-%3E%3D22-success)
![Next.js](https://img.shields.io/badge/Framework-Next.js-black)

专为 **独立开发者** 和 **初创团队** 打造的 Node.js (尤其是 Next.js) 生产环境轻量级自动化部署与管理工具。

告别繁琐的手动配置，将环境搭建 (Node.js 22, PM2, Nginx, Certbot)、性能调优 (Swap 挂载、静态资源加速)、SSL 证书部署以及日常运维，统统整合进了一个交互式的全局命令 `saas` 中。只需执行一次安装，即可实现生产环境的**零宕机热更新**与**一键灾难恢复**。

---

## 🚀 一键执行命令 (推荐)

无论您是一台全新的服务器，还是已经上传了代码，都可以直接在终端执行此命令：

```bash
apt update -y && apt install curl wget sudo -y && curl -sSLo /usr/local/bin/saas https://raw.githubusercontent.com/zdaben/saas_install/main/saas.sh && chmod +x /usr/local/bin/saas && saas install
```

---

## ✨ 核心亮点

- 🤖 **一键自动化部署**：交互式配置域名与端口，支持空目录智能预装。自动完成 Node.js 22 环境构建、依赖安装与 Prisma 模型生成。
- 🛡️ **生产级环境加固**：智能检测物理内存并配置 Swap 防爆内存；使用 PM2 守护进程确保应用 24/7 高可用。
- ⚡ **Nginx 深度优化**：自动配置反向代理，**并将 `/_next/static/` 静态资源交由 Nginx 物理直吐**，极大降低 Node.js 负载，提升页面并发响应速度。
- 🔄 **零宕机极速发布**：功能解耦。修改业务代码后仅需一条 `saas build`，即可极速重新编译并执行 PM2 内存热重载，更新不断线。
- 🔒 **全自动 SSL 证书**：无缝集成 Certbot，自动申请 Let's Encrypt HTTPS 证书并配置自动续期。
- 📦 **轻量化数据灾备**：自动打包核心源码与环境变量（智能剔除庞大的 `node_modules` 和构建缓存），统一存放在系统级目录 `/var/webak` 中，安全且极度节省空间。

---

## 🛠️ 环境要求

- **操作系统**: Debian 12+ 或 Ubuntu 22.04+ (纯净系统最佳)
- **系统权限**: `root` 用户
- **网络前置**: 若需配置 HTTPS，请提前将您的域名（如 `app.example.com`）解析到该服务器的公网 IP。

---

## 📦 部署工作流指南

本工具非常智能，支持 **先配环境再传代码** 或 **先传代码再配环境** 两种工作流：

### 场景一：拿到一台全新服务器 (推荐小白使用)
1. 直接在服务器执行上面的【🚀 一键执行命令】。
2. 脚本会自动帮您装好 Node、PM2、Nginx，配置好 SSL 证书，并自动创建 ` /var/www/您的域名 ` 空目录。
3. 您通过 SFTP 工具将 Next.js 源码上传至上述空目录。
4. 终端执行 `saas update` (安装底层依赖)。
5. 终端执行 `saas build` (编译上线)。

### 场景二：代码已经传到服务器了
1. 确保代码存放在 `/var/www/您的域名` 目录下。
2. 执行上述的【🚀 一键执行命令】。
3. 脚本会自动检测到源码的存在，**一次性帮您完成环境配置、依赖安装、代码编译、服务拉起和 SSL 申请**。网站直接满血上线！

---

## 💻 命令行指南 (CLI Usage)

在终端中输入 `saas` 即可呼出高亮控制面板并查看当前运行状态。

| 命令 | 说明 |
| :--- | :--- |
| `saas` | 查看主面板（包含访问地址、应用名称、内部端口、运行目录等概览） |
| `saas install` | 初始化环境配置与安装部署（首次运行） |
| **`saas build`** | **【日常高频使用】** 修改网页代码后，执行此命令仅重新编译代码并平滑重启，极速上线 |
| **`saas update`** | **【更新底层环境】** 当您修改了 `package.json` 添加新库，或修改了数据库模型后执行此命令安装新依赖 |
| `saas status` | 查看 Node/Nginx 版本状态及 PM2 进程列表详细资源占用 |
| `saas top` | 进入 PM2 Monit 实时动态资源监控大屏 (按 `Ctrl+C` 退出) |
| `saas restart` | 强制重启 PM2 Node 进程以及 Nginx 服务 |
| `saas backup` | 轻量化打包备份核心源码、`.env` 变量及本地数据库，自动清理过期备份 |
| `saas recover` | 呼出交互式面板，从 `/var/webak` 历史归档中恢复代码并自动重建生产环境 |
| `saas uninstall` | 彻底卸载应用进程，清理 Nginx 代理规则、证书及源码文件目录 |

---

## 📂 目录结构说明

- **网站运行目录**: `/var/www/{你的域名}` (您的源码存放在此)
- **全局配置存储**: `/etc/saas_config.sh` (持久化保存您的域名、端口等信息)
- **全局命令路径**: `/usr/local/bin/saas`
- **系统级灾备目录**: `/var/webak/` (生成的备份文件存放在此，即使网站被卸载也会安全保留)

---

## ❓ 常见问题 (FAQ)

**Q: 运行 `saas build` 时提示编译失败怎么办？**
A: 请检查您上传的源码是否有语法错误，或者是否在本地测试过 `npm run build`。脚本在编译失败时会自动中止重载操作，**您的线上旧版本仍将保持正常运行**。查看具体报错并修复源码后，重新上传运行 `saas build` 即可。

**Q: `saas build` 和 `saas update` 有什么区别？**
A: `build` 只负责打包网页代码并重启，速度极快，适合日常改页面。`update` 负责升级 Node 版本、跑 `npm install` 下载新插件库、跑 `prisma generate` 刷新数据库结构。如果你加了新插件，就先跑 `update` 再跑 `build`。

**Q: 备份功能会备份我上传的图片和数据库吗？**
A: 会的。由于备份排除了庞大的 `node_modules` 和 `.next` 缓存，因此剩下的如 `public` 文件夹下的图片、根目录的 `.env` 密钥以及 SQLite `.db` 文件都会被安全且轻量化地打包进备份文件中。

---

## 📄 开源协议

本项目基于 [MIT License](LICENSE) 协议开源。欢迎提交 Issue 或 Pull Request 来共同完善这个工具！
