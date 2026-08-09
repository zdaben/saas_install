#!/bin/bash
#=================================================================#
#  System Required: Debian 12+ / Ubuntu 22.04+                    #
#  Description: SaaS Web (Next.js) CLI Management Tool v2.0       #
#  Author: zdaben / AI Assistant                                  #
#=================================================================#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

CONFIG_FILE="/etc/saas_config.sh"

# 加载持久化配置（如果存在）
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 初始化基础变量（用于展示或首次安装前的默认值）
DOMAIN=${DOMAIN:-"example.com"}
APP_PORT=${APP_PORT:-3000}
APP_NAME=${APP_NAME:-"saas-web"}
WEB_DIR=${WEB_DIR:-"/var/www/${DOMAIN}"}
BACKUP_DIR="${WEB_DIR}/backup"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：必须使用 root 用户或 sudo 运行此脚本。${PLAIN}"
        exit 1
    fi
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
DOMAIN="${DOMAIN}"
APP_PORT=${APP_PORT}
APP_NAME="${APP_NAME}"
WEB_DIR="${WEB_DIR}"
EOF
}

cmd_show_panel() {
    echo -e "\n${GREEN}===========================================================${PLAIN}"
    echo -e "${GREEN}SaaS Web (Next.js) 终端管理面板 v2.0${PLAIN}"
    echo -e "-----------------------------------------------------------"
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "访问地址: ${YELLOW}https://${DOMAIN}${PLAIN}"
        echo -e "应用名称: ${CYAN}${APP_NAME}${PLAIN} (PM2 守护)"
        echo -e "内部端口: ${CYAN}${APP_PORT}${PLAIN}"
        echo -e "运行目录: ${CYAN}${WEB_DIR}${PLAIN}"
    else
        echo -e "${YELLOW}尚未初始化配置，请先运行 saas install 进行部署。${PLAIN}"
    fi
    echo -e "-----------------------------------------------------------"
    echo -e "${GREEN}命令列表:${PLAIN}"
    echo -e "  ${YELLOW}saas status${PLAIN}    - 查看服务状态与资源占用 (PM2 & Nginx)"
    echo -e "  ${YELLOW}saas top${PLAIN}       - 实时监控进程资源占用 (PM2 Monit)"
    echo -e "  ${YELLOW}saas update${PLAIN}    - 重新安装依赖与编译最新代码 (零宕机热重载)"
    echo -e "  ${YELLOW}saas restart${PLAIN}   - 重启 PM2 服务和 Nginx"
    echo -e "  ${YELLOW}saas backup${PLAIN}    - 备份环境变量和配置 (包含本地数据库文件)"
    echo -e "  ${YELLOW}saas recover${PLAIN}   - 从历史备份恢复环境变量"
    echo -e "  ${YELLOW}saas install${PLAIN}   - 初始化安装环境 (支持自定义域名与端口)"
    echo -e "  ${RED}saas uninstall${PLAIN} - 卸载服务并清理所有相关文件"
    echo -e "-----------------------------------------------------------"
    echo -e "${GREEN}===========================================================${PLAIN}"
}

cmd_install() {
    check_root
    
    echo -e "${CYAN}--- SaaS 部署配置初始化 ---${PLAIN}"
    read -p "请输入要绑定的域名 (默认: ${DOMAIN}): " INPUT_DOMAIN
    DOMAIN=${INPUT_DOMAIN:-$DOMAIN}
    
    read -p "请输入应用运行端口 (默认: ${APP_PORT}): " INPUT_PORT
    APP_PORT=${INPUT_PORT:-$APP_PORT}
    
    read -p "请输入 PM2 守护应用名称 (默认: ${APP_NAME}): " INPUT_NAME
    APP_NAME=${INPUT_NAME:-$APP_NAME}
    
    WEB_DIR="/var/www/${DOMAIN}"
    BACKUP_DIR="${WEB_DIR}/backup"
    
    save_config
    
    echo -e "\n${GREEN}==> 准备环境与基础依赖...${PLAIN}"
    apt update && apt install -y curl vim nginx certbot python3-certbot-nginx jq tar cron unzip
    
    # 智能检查 Node.js 版本 (>=20)
    NEED_NODE_UPDATE=true
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node -v | cut -d 'v' -f 2 | cut -d '.' -f 1)
        if [ "$NODE_VERSION" -ge 20 ]; then
            NEED_NODE_UPDATE=false
            echo -e "${CYAN}已检测到兼容的 Node.js 版本 (v${NODE_VERSION})，跳过安装。${PLAIN}"
        fi
    fi

    if $NEED_NODE_UPDATE; then
        echo -e "${GREEN}==> 安装 Node.js 20 LTS...${PLAIN}"
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
    fi

    # 检查并安装 PM2
    if ! command -v pm2 &> /dev/null; then
        echo -e "${GREEN}==> 安装 PM2 进程管理器...${PLAIN}"
        npm install -g pm2
    fi

    # 配置 Swap 内存 (防爆内存策略)
    MEM_TOTAL=$(free -m | awk '/Mem/{print $2}')
    if [ "$MEM_TOTAL" -le 2048 ] && [ ! -f /swapfile ]; then
        echo -e "${GREEN}==> 检测到物理内存较小 (${MEM_TOTAL}MB)，配置虚拟内存 (Swap)...${PLAIN}"
        SWAP_SIZE_MB=$([ "$MEM_TOTAL" -le 600 ] && echo 2048 || echo 1024)
        fallocate -l ${SWAP_SIZE_MB}M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=${SWAP_SIZE_MB} status=none
        chmod 600 /swapfile && mkswap /swapfile >/dev/null 2>&1 && swapon /swapfile
        grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    fi

    if [ ! -d "$WEB_DIR" ]; then
        echo -e "${RED}错误: 运行目录 $WEB_DIR 不存在。${PLAIN}"
        echo -e "${YELLOW}提示: 请先将 Next.js 源码解压或克隆至该目录，然后再执行 saas install。${PLAIN}"
        exit 1
    fi

    echo -e "${GREEN}==> 开始编译与构建应用...${PLAIN}"
    cd "$WEB_DIR"
    npm install
    npx prisma generate 2>/dev/null || echo -e "${YELLOW}未检测到 Prisma 架构，已跳过。${PLAIN}"
    npm run build || { echo -e "${RED}项目构建 (npm run build) 失败，请检查源码或日志。${PLAIN}"; exit 1; }

    # Nginx 优化配置 (Next.js 静态文件直接由 Nginx 承载)
    echo -e "${GREEN}==> 配置 Nginx 代理与静态加速...${PLAIN}"
    cat > /etc/nginx/sites-available/${DOMAIN}.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    client_max_body_size 50M;

    # 静态文件走 Nginx 物理路径，提升并发性能
    location /_next/static/ {
        alias ${WEB_DIR}/.next/static/;
        expires 365d;
        access_log off;
    }

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/${DOMAIN}.conf /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl reload nginx

    # SSL 证书交互式配置
    read -p "是否立即通过 Certbot 申请并部署 SSL 证书? (y/n) [y]: " ENABLE_SSL
    ENABLE_SSL=${ENABLE_SSL:-y}
    if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
        read -p "请输入接收证书到期通知的邮箱 (留空则不填): " SSL_EMAIL
        CERT_EMAIL_ARG=$([ -n "$SSL_EMAIL" ] && echo "-m $SSL_EMAIL" || echo "--register-unsafely-without-email")
        
        echo -e "${GREEN}==> 正在通过 Certbot 申请 SSL 证书...${PLAIN}"
        certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos $CERT_EMAIL_ARG --redirect || \
        echo -e "${YELLOW}警告：SSL 配置异常，可能是由于 DNS 未解析，后续可手动运行 certbot 修复。${PLAIN}"
    fi

    # 启动 PM2
    echo -e "${GREEN}==> 配置并启动 PM2 守护进程...${PLAIN}"
    if pm2 status | grep -q "${APP_NAME}"; then
        pm2 reload ${APP_NAME}
    else
        pm2 start npm --name "${APP_NAME}" -- run start
    fi
    pm2 save
    pm2 startup | tail -n 1 | bash || true

    # 自动注册全局命令
    if [ ! -f "/usr/local/bin/saas" ]; then
        echo -e "${GREEN}==> 注册系统全局命令 saas...${PLAIN}"
        cp "$0" /usr/local/bin/saas
        chmod +x /usr/local/bin/saas
    fi

    echo -e "\n${GREEN}✅ 安装部署完成！请访问 http(s)://${DOMAIN}${PLAIN}"
}

cmd_update() {
    check_root
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}系统未配置，请先运行 saas install。${PLAIN}"
        exit 1
    fi
    
    cd "$WEB_DIR"
    echo -e "${YELLOW}注意: 请确保您已经上传了最新的代码文件至: ${CYAN}${WEB_DIR}${PLAIN}"
    read -p "确认已覆盖文件并开始平滑升级？(y/n) [y]: " CONFIRM
    CONFIRM=${CONFIRM:-y}
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "已取消更新。"
        exit 0
    fi

    echo -e "${GREEN}==> 安装潜在的新依赖包...${PLAIN}"
    npm install
    
    echo -e "${GREEN}==> 生成架构类型...${PLAIN}"
    npx prisma generate 2>/dev/null || true
    
    echo -e "${GREEN}==> 开始编译生产环境代码...${PLAIN}"
    npm run build || { echo -e "${RED}编译失败，回滚操作被中止。请检查代码错误。${PLAIN}"; exit 1; }

    echo -e "${GREEN}==> 重载 Node 服务 (零宕机)...${PLAIN}"
    pm2 reload ${APP_NAME}
    pm2 save
    echo -e "${GREEN}✅ 系统已更新至最新版本代码。${PLAIN}"
}

cmd_status() {
    check_root
    echo -e "\n${GREEN}▶ 基础运行环境:${PLAIN}"
    echo -e "Node.js 版本: $(node -v 2>/dev/null || echo '未安装')"
    echo -e "Nginx 状态:   $(systemctl is-active nginx 2>/dev/null || echo '异常')"
    
    echo -e "\n${GREEN}▶ PM2 服务列表 (${APP_NAME}):${PLAIN}"
    pm2 list
    
    echo -e "\n${GREEN}▶ 应用详细资源看板:${PLAIN}"
    pm2 show ${APP_NAME} | grep -E 'status|uptime|restarts|memory|cpu' || echo "无法获取详细信息。"
}

cmd_top() {
    check_root
    echo -e "${YELLOW}提示: 正在进入实时监控模式，按 'q' 或 Ctrl+C 退出。${PLAIN}"
    pm2 monit
}

cmd_restart() {
    check_root
    echo -e "${GREEN}==> 正在重启应用服务与 Web 容器...${PLAIN}"
    pm2 restart ${APP_NAME} || echo -e "${YELLOW}PM2 服务重启失败或未找到。${PLAIN}"
    systemctl restart nginx || echo -e "${YELLOW}Nginx 重启失败。${PLAIN}"
    echo -e "${GREEN}✅ 重启指令执行完毕。${PLAIN}"
}

cmd_backup() {
    check_root
    echo -e "${GREEN}==> 正在打包环境配置与本地数据...${PLAIN}"
    mkdir -p "${BACKUP_DIR}"
    local DATE=$(date +%Y%m%d_%H%M%S)
    local FILE="${BACKUP_DIR}/saas_cfg_${DATE}.tar.gz"
    
    cd "${WEB_DIR}"
    # 尽力备份配置环境变量、数据库架构以及潜在的 SQLite 本地数据库文件
    tar czf "${FILE}" .env* prisma/*.prisma prisma/*.sqlite prisma/*.db 2>/dev/null || echo -e "${YELLOW}提示: 部分文件未找到，已打包存在的部分。${PLAIN}"
    
    # 清理过期备份
    find "${BACKUP_DIR}" -name "saas_cfg_*.tar.gz" -mtime +7 -delete 2>/dev/null || true
    echo -e "${GREEN}✅ 数据备份完成: ${CYAN}${FILE}${PLAIN}"
}

cmd_recover() {
    check_root
    echo -e "${CYAN}--- 环境变量与数据恢复面板 ---${PLAIN}"
    
    if [ ! -d "${BACKUP_DIR}" ] || ! ls "${BACKUP_DIR}"/saas_cfg_*.tar.gz 1> /dev/null 2>&1; then
        echo -e "${YELLOW}错误: 未找到任何历史备份记录！${PLAIN}"
        exit 1
    fi
    
    ls -lh "${BACKUP_DIR}"/saas_cfg_*.tar.gz | awk '{print NR". "$9" ("$5")"}' | sed "s|${BACKUP_DIR}/||"
    read -p "请选择需要恢复的编号 (输入 0 取消): " IDX
    
    # 输入合法性校验，避免引起进程异常崩溃
    if ! [[ "$IDX" =~ ^[0-9]+$ ]] || [ "$IDX" -eq 0 ]; then
        echo "已取消数据恢复。"
        exit 0
    fi
    
    local MAX_IDX=$(ls "${BACKUP_DIR}"/saas_cfg_*.tar.gz | wc -l)
    if [ "$IDX" -gt "$MAX_IDX" ] || [ "$IDX" -lt 1 ]; then
        echo -e "${RED}输入无效编号，取消操作。${PLAIN}"
        exit 1
    fi
    
    FILE=$(ls "${BACKUP_DIR}"/saas_cfg_*.tar.gz | sed -n "${IDX}p")
    echo -e "${YELLOW}即将覆盖当前的 .env 配置及本地数据库...${PLAIN}"
    tar xzf "${FILE}" -C "${WEB_DIR}"
    echo -e "${GREEN}✅ 恢复完成。建议运行 ${YELLOW}saas restart${PLAIN} 使配置生效。${PLAIN}"
}

cmd_uninstall() {
    check_root
    echo -e "${RED}警告：此操作不可逆！将删除 PM2 进程、Nginx 代理规则、配置文件及整个源码目录。${PLAIN}"
    echo -e "涉及目录: ${CYAN}${WEB_DIR}${PLAIN}"
    read -p "若确认卸载，请输入 'yes': " CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        echo -e "${GREEN}==> 停止并注销 PM2 进程...${PLAIN}"
        pm2 stop ${APP_NAME} 2>/dev/null || true
        pm2 delete ${APP_NAME} 2>/dev/null || true
        pm2 save --force
        
        echo -e "${GREEN}==> 清除 Nginx 规则与证书...${PLAIN}"
        rm -f /etc/nginx/sites-available/${DOMAIN}.conf
        rm -f /etc/nginx/sites-enabled/${DOMAIN}.conf
        certbot delete --cert-name ${DOMAIN} --non-interactive 2>/dev/null || true
        systemctl reload nginx || true
        
        echo -e "${GREEN}==> 移除项目文件与全局命令...${PLAIN}"
        rm -rf "${WEB_DIR}"
        rm -f "$CONFIG_FILE"
        rm -f /usr/local/bin/saas
        
        echo -e "${GREEN}✅ SaaS 应用与运行环境已彻底卸载。${PLAIN}"
    else
        echo "已取消卸载操作。"
    fi
}

case "$1" in
    install)   cmd_install ;;
    update)    cmd_update ;;
    status)    cmd_status ;;
    top)       cmd_top ;;
    restart)   cmd_restart ;;
    backup)    cmd_backup ;;
    recover)   cmd_recover ;;
    uninstall) cmd_uninstall ;;
    *) cmd_show_panel ;;
esac
