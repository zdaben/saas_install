#!/bin/bash
#=================================================================#
#  System Required: Debian 12+ / Ubuntu 22.04+                    #
#  Description: SaaS Web (Next.js) CLI Management Tool            #
#  Author: zdaben / AI Assistant                                  #
#=================================================================#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

CONFIG_FILE="/etc/saas_config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

DOMAIN=${DOMAIN:-"example.com"}
APP_PORT=${APP_PORT:-3000}
APP_NAME=${APP_NAME:-"saas-web"}
WEB_DIR=${WEB_DIR:-"/var/www/${DOMAIN}"}
BACKUP_DIR="/var/webak"

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

# 自动修复 Next.js / Prisma 常见编译错误
fix_nextjs_build_issues() {
    echo -e "${GREEN}==> 检查并修复代码依赖...${PLAIN}"
    npm i baseline-browser-mapping@latest -D >/dev/null 2>&1 || true

    if [ -f "package.json" ]; then
        if grep -q '"file-saver"' package.json && ! grep -q '"@types/file-saver"' package.json; then
            echo -e "${YELLOW}==> 检测到缺少 @types/file-saver，正在自动补全以防止编译报错...${PLAIN}"
            npm i --save-dev @types/file-saver >/dev/null 2>&1 || true
        fi
    fi

    if [ -f "prisma.config.ts" ]; then
        if grep -q "directUrl:" prisma.config.ts && ! grep -q "//.*directUrl:" prisma.config.ts; then
            echo -e "${YELLOW}==> 自动注释 prisma.config.ts 中不支持的 directUrl 属性...${PLAIN}"
            sed -i 's/directUrl:/\/\/ directUrl:/g' prisma.config.ts
        fi
    fi
}

cmd_show_panel() {
    echo -e "\n${GREEN}===========================================================${PLAIN}"
    echo -e "${GREEN}SaaS Web (Next.js) 终端管理面板${PLAIN}"
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
    echo -e "  ${YELLOW}saas status${PLAIN}    - 查看服务状态与资源占用"
    echo -e "  ${YELLOW}saas top${PLAIN}       - 实时监控进程资源占用"
    echo -e "  ${CYAN}saas build${PLAIN}     - 编译网站源码并平滑重启"
    echo -e "  ${YELLOW}saas update${PLAIN}    - 更新系统环境、NPM 依赖与 Prisma 模型"
    echo -e "  ${YELLOW}saas restart${PLAIN}   - 重启 PM2 服务和 Nginx"
    echo -e "  ${YELLOW}saas backup${PLAIN}    - 备份站点数据 (自动剔除编译缓存与依赖库)"
    echo -e "  ${YELLOW}saas recover${PLAIN}   - 恢复站点数据并自动重新编译"
    echo -e "  ${YELLOW}saas install${PLAIN}   - 初始化安装环境 (支持空目录预装)"
    echo -e "  ${RED}saas uninstall${PLAIN} - 卸载服务并清理相关文件"
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
    save_config
    
    echo -e "\n${GREEN}==> 准备环境与基础依赖...${PLAIN}"
    apt update && apt install -y curl vim nginx certbot python3-certbot-nginx jq tar cron unzip
    
    NEED_NODE_UPDATE=true
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node -v | cut -d 'v' -f 2 | cut -d '.' -f 1)
        if [ "$NODE_VERSION" -ge 22 ]; then
            NEED_NODE_UPDATE=false
            echo -e "${CYAN}已检测到兼容的 Node.js 版本 (v${NODE_VERSION})，跳过安装。${PLAIN}"
        fi
    fi

    if $NEED_NODE_UPDATE; then
        echo -e "${GREEN}==> 检测到 Node 版本过低，正在安装 Node.js 22 LTS...${PLAIN}"
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
        apt-get install -y nodejs
    fi

    if ! command -v pm2 &> /dev/null; then
        echo -e "${GREEN}==> 安装 PM2 进程管理器...${PLAIN}"
        npm install -g pm2
    fi

    MEM_TOTAL=$(free -m | awk '/Mem/{print $2}')
    if [ "$MEM_TOTAL" -le 2048 ] && [ ! -f /swapfile ]; then
        echo -e "${GREEN}==> 配置虚拟内存 (Swap)...${PLAIN}"
        SWAP_SIZE_MB=$([ "$MEM_TOTAL" -le 600 ] && echo 2048 || echo 1024)
        fallocate -l ${SWAP_SIZE_MB}M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=${SWAP_SIZE_MB} status=none
        chmod 600 /swapfile && mkswap /swapfile >/dev/null 2>&1 && swapon /swapfile
        grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    fi

    if [ ! -d "$WEB_DIR" ]; then
        echo -e "${GREEN}==> 创建运行目录: ${CYAN}${WEB_DIR}${PLAIN}"
        mkdir -p "$WEB_DIR"
        chown -R root:root "$WEB_DIR"
    fi

    HAS_CODE=true
    if [ ! -f "$WEB_DIR/package.json" ]; then
        echo -e "${YELLOW}==> 提示: 目录中未检测到源码 (缺少 package.json)。将跳过应用编译步骤。${PLAIN}"
        HAS_CODE=false
    fi

    if $HAS_CODE; then
        cd "$WEB_DIR"
        npm install
        fix_nextjs_build_issues
        npx prisma generate 2>/dev/null || true
        echo -e "${GREEN}==> 开始编译生产环境代码...${PLAIN}"
        npm run build || { echo -e "${RED}项目构建失败，请检查源码或日志。${PLAIN}"; exit 1; }
    fi

    echo -e "${GREEN}==> 配置 Nginx 代理与静态文件规则...${PLAIN}"
    cat > /etc/nginx/sites-available/${DOMAIN}.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    client_max_body_size 50M;

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

    read -p "是否立即通过 Certbot 申请并部署 SSL 证书? (y/n) [y]: " ENABLE_SSL
    ENABLE_SSL=${ENABLE_SSL:-y}
    if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
        read -p "请输入接收证书到期通知的邮箱 (留空则不填): " SSL_EMAIL
        CERT_EMAIL_ARG=$([ -n "$SSL_EMAIL" ] && echo "-m $SSL_EMAIL" || echo "--register-unsafely-without-email")
        certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos $CERT_EMAIL_ARG --redirect || true
    fi

    if $HAS_CODE; then
        echo -e "${GREEN}==> 启动 PM2 守护进程...${PLAIN}"
        if pm2 status | grep -q "${APP_NAME}"; then
            pm2 reload ${APP_NAME}
        else
            pm2 start npm --name "${APP_NAME}" -- run start
        fi
        pm2 save
        pm2 startup | tail -n 1 | bash || true
    fi

    if [ ! -f "/usr/local/bin/saas" ]; then
        cp "$0" /usr/local/bin/saas
        chmod +x /usr/local/bin/saas
    fi

    echo -e "\n${GREEN}===========================================================${PLAIN}"
    if $HAS_CODE; then
        echo -e "✅ 安装部署完成！请访问: ${YELLOW}https://${DOMAIN}${PLAIN}"
    else
        echo -e "✅ 基础运行环境配置完毕！请上传代码后运行: ${YELLOW}saas update${PLAIN}"
    fi
    echo -e "${GREEN}===========================================================${PLAIN}"
}

cmd_update() {
    check_root
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}系统未配置，请先运行 saas install。${PLAIN}"
        exit 1
    fi
    
    cd "$WEB_DIR"
    read -p "此命令将更新系统环境与依赖库 (NPM)，确认执行？(y/n) [y]: " CONFIRM
    CONFIRM=${CONFIRM:-y}
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        exit 0
    fi

    if command -v node &> /dev/null; then
        NODE_VERSION=$(node -v | cut -d 'v' -f 2 | cut -d '.' -f 1)
        if [ "$NODE_VERSION" -lt 22 ]; then
            echo -e "${GREEN}==> 升级 Node.js 22 LTS...${PLAIN}"
            curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
            apt-get install -y nodejs
        fi
    fi

    echo -e "${GREEN}==> 安装依赖包...${PLAIN}"
    npm install
    fix_nextjs_build_issues
    npx prisma generate 2>/dev/null || true
    
    echo -e "${GREEN}✅ 环境与依赖包更新完毕！${PLAIN}"
    echo -e "${YELLOW}提示: 如需将代码改动生效，请随后执行 ${CYAN}saas build${YELLOW} 进行重新编译。${PLAIN}"
}

cmd_build() {
    check_root
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}系统未配置，请先运行 saas install。${PLAIN}"
        exit 1
    fi
    
    cd "$WEB_DIR"
    read -p "确认开始编译代码并重启服务？(y/n) [y]: " CONFIRM
    CONFIRM=${CONFIRM:-y}
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    echo -e "${GREEN}==> 开始编译生产环境代码...${PLAIN}"
    npm run build || { echo -e "${RED}编译失败，中止更新。请检查代码是否有误。${PLAIN}"; exit 1; }

    echo -e "${GREEN}==> 重载 Node 服务...${PLAIN}"
    if pm2 status | grep -q "${APP_NAME}"; then
        pm2 reload ${APP_NAME}
    else
        pm2 start npm --name "${APP_NAME}" -- run start
    fi
    pm2 save
    echo -e "${GREEN}✅ 代码编译完成，服务已重启！${PLAIN}"
}

cmd_status() {
    check_root
    echo -e "\n${GREEN}▶ 基础运行环境:${PLAIN}"
    echo -e "Node.js 版本: $(node -v 2>/dev/null || echo '未安装')"
    echo -e "Nginx 状态:   $(systemctl is-active nginx 2>/dev/null || echo '异常')"
    echo -e "\n${GREEN}▶ PM2 服务列表 (${APP_NAME}):${PLAIN}"
    pm2 list
    echo -e "\n${GREEN}▶ 应用详细资源看板:${PLAIN}"
    pm2 show ${APP_NAME} | grep -E 'status|uptime|restarts|memory|cpu' || echo "无信息"
}

cmd_top() {
    check_root
    pm2 monit
}

cmd_restart() {
    check_root
    pm2 restart ${APP_NAME} || true
    systemctl restart nginx || true
    echo -e "${GREEN}✅ 重启完毕。${PLAIN}"
}

cmd_backup() {
    check_root
    echo -e "${GREEN}==> 正在备份站点源码与配置...${PLAIN}"
    mkdir -p "${BACKUP_DIR}"
    local DATE=$(date +%Y%m%d_%H%M%S)
    local FILE="${BACKUP_DIR}/${DOMAIN}_${DATE}.tar.gz"
    
    echo -e "${YELLOW}目标: 打包核心源码与环境变量 (剔除 node_modules 与编译缓存)...${PLAIN}"
    tar -czf "${FILE}" \
        --exclude='./node_modules' \
        --exclude='./.next' \
        --exclude='./.git' \
        -C "${WEB_DIR}" .
    
    echo -e "${YELLOW}生成 SHA256 完整性校验码...${PLAIN}"
    sha256sum "${FILE}" > "${FILE}.sha256"
    
    find "${BACKUP_DIR}" -name "${DOMAIN}_*.tar.gz" -mtime +7 -delete 2>/dev/null || true
    find "${BACKUP_DIR}" -name "${DOMAIN}_*.tar.gz.sha256" -mtime +7 -delete 2>/dev/null || true
    
    echo -e "${GREEN}✅ 备份完成！文件路径: ${CYAN}${FILE}${PLAIN}"
}

cmd_recover() {
    check_root
    echo -e "${CYAN}--- 网站恢复面板 ---${PLAIN}"
    
    if [ ! -d "${BACKUP_DIR}" ] || ! ls "${BACKUP_DIR}"/${DOMAIN}_*.tar.gz 1> /dev/null 2>&1; then
        echo -e "${YELLOW}错误: 未找到备份记录！${PLAIN}"
        exit 1
    fi
    
    echo -e "${YELLOW}可用备份列表：${PLAIN}"
    ls -lh "${BACKUP_DIR}"/${DOMAIN}_*.tar.gz | awk '{print NR". "$9" ("$5")"}' | sed "s|${BACKUP_DIR}/||"
    echo -e "-----------------------------------------------------------"
    read -p "请选择需要恢复的编号 (输入 0 取消): " IDX
    
    if ! [[ "$IDX" =~ ^[0-9]+$ ]] || [ "$IDX" -eq 0 ]; then exit 0; fi
    local MAX_IDX=$(ls "${BACKUP_DIR}"/${DOMAIN}_*.tar.gz | wc -l)
    if [ "$IDX" -gt "$MAX_IDX" ] || [ "$IDX" -lt 1 ]; then exit 1; fi
    
    FILE=$(ls "${BACKUP_DIR}"/${DOMAIN}_*.tar.gz | sed -n "${IDX}p")
    
    echo -e "${RED}警告：将覆盖 ${WEB_DIR} 下的源码，并重新执行安装与编译！${PLAIN}"
    read -p "确认继续？(yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then exit 0; fi

    echo -e "${YELLOW}验证文件哈希...${PLAIN}"
    if [ -f "${FILE}.sha256" ]; then
        if ! cd "$(dirname "$FILE")" && sha256sum -c "$(basename "${FILE}.sha256")" >/dev/null 2>&1; then
            echo -e "${RED}验证失败：备份文件可能已损坏。${PLAIN}"
            exit 1
        fi
        cd - >/dev/null
    fi
    
    echo -e "${YELLOW}==> 停止应用服务防止文件冲突...${PLAIN}"
    pm2 stop ${APP_NAME} 2>/dev/null || true

    echo -e "${YELLOW}==> 解压核心源码与配置...${PLAIN}"
    tar -xzf "${FILE}" -C "${WEB_DIR}"
    
    echo -e "${GREEN}==> 源码恢复成功，正在重建生产环境...${PLAIN}"
    cd "${WEB_DIR}"
    npm install
    npx prisma generate 2>/dev/null || true
    npm run build || { echo -e "${RED}恢复后编译失败，请检查代码兼容性。${PLAIN}"; exit 1; }
    
    echo -e "${GREEN}==> 重启应用服务以加载恢复的数据...${PLAIN}"
    pm2 restart ${APP_NAME} || pm2 start npm --name "${APP_NAME}" -- run start
    pm2 save
    
    echo -e "${GREEN}✅ 网站已成功恢复并重新上线！${PLAIN}"
}

cmd_uninstall() {
    check_root
    echo -e "${RED}警告：此操作将删除 PM2 进程、Nginx 代理规则及整个源码目录。${PLAIN}"
    read -p "确认卸载请输入 'yes': " CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        pm2 stop ${APP_NAME} 2>/dev/null || true
        pm2 delete ${APP_NAME} 2>/dev/null || true
        pm2 save --force
        
        rm -f /etc/nginx/sites-available/${DOMAIN}.conf
        rm -f /etc/nginx/sites-enabled/${DOMAIN}.conf
        certbot delete --cert-name ${DOMAIN} --non-interactive 2>/dev/null || true
        systemctl reload nginx || true
        
        rm -rf "${WEB_DIR}"
        rm -f "$CONFIG_FILE"
        rm -f /usr/local/bin/saas
        
        echo -e "${GREEN}✅ 卸载完成。备份文件已安全保留在 ${BACKUP_DIR}。${PLAIN}"
    else
        echo "已取消卸载操作。"
    fi
}

case "$1" in
    install)   cmd_install ;;
    update)    cmd_update ;;
    build)     cmd_build ;;
    status)    cmd_status ;;
    top)       cmd_top ;;
    restart)   cmd_restart ;;
    backup)    cmd_backup ;;
    recover)   cmd_recover ;;
    uninstall) cmd_uninstall ;;
    *) cmd_show_panel ;;
esac
