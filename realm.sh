#!/bin/bash

# ========================================
# 全局配置
# ========================================
CURRENT_VERSION="1.1.2"
REALM_DIR="/root/realm"
CONFIG_FILE="$REALM_DIR/config.toml"
SERVICE_FILE="/etc/systemd/system/realm.service"
LOG_FILE="/var/log/realm_manager.log"
PROXY_CONFIG_FILE="$REALM_DIR/.proxy_config"

# 代理变量（初始为空）
PROXY=""

# GitHub 相关 URL（将在代理配置后设置）
BASE_RAW_URL="https://raw.githubusercontent.com/qqrrooty/EZrealm/main"
BASE_GITHUB_URL="https://github.com"
UPDATE_URL=""
VERSION_CHECK_URL=""

# ========================================
# 颜色定义
# ========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========================================
# URL 初始化函数
# ========================================
init_urls() {
    UPDATE_URL="${PROXY}${BASE_RAW_URL}/realm.sh"
    VERSION_CHECK_URL="${PROXY}${BASE_RAW_URL}/version.txt"
}

# ========================================
# 中国 IP 检测
# ========================================
check_china_ip() {
    local country=""

    # 尝试多个 IP 检测服务
    # 方法1: ip-api.com
    country=$(curl -sL --connect-timeout 5 "http://ip-api.com/line?fields=countryCode" 2>/dev/null | head -n1)

    # 方法2: ipinfo.io (备用)
    if [[ -z "$country" ]]; then
        country=$(curl -sL --connect-timeout 5 "https://ipinfo.io/country" 2>/dev/null | head -n1)
    fi

    # 方法3: ipapi.co (备用)
    if [[ -z "$country" ]]; then
        country=$(curl -sL --connect-timeout 5 "https://ipapi.co/country_code" 2>/dev/null | head -n1)
    fi

    # 判断是否为中国
    if [[ "$country" == "CN" ]]; then
        return 0  # 在中国
    else
        return 1  # 不在中国
    fi
}

# ========================================
# 代理配置
# ========================================
setup_proxy() {
    echo -e "\n${BLUE}▶ 正在检测网络环境...${NC}"

    # 确保目录存在
    mkdir -p "$REALM_DIR"

    # 检查是否已有保存的代理配置
    if [[ -f "$PROXY_CONFIG_FILE" ]]; then
        local saved_proxy
        saved_proxy=$(cat "$PROXY_CONFIG_FILE" 2>/dev/null)
        if [[ -n "$saved_proxy" ]]; then
            echo -e "${GREEN}✓ 检测到已保存的代理配置${NC}"
            echo -e "  代理地址: ${CYAN}${saved_proxy}${NC}"
            read -rp "是否使用此代理？(Y/n): " use_saved
            use_saved=${use_saved:-Y}
            if [[ "$use_saved" =~ ^[Yy]$ ]]; then
                PROXY="$saved_proxy"
                init_urls
                echo -e "${GREEN}✓ 已启用代理${NC}"
                return 0
            fi
        fi
    fi

    # 检测是否在中国
    if check_china_ip; then
        echo -e "${YELLOW}⚠ 检测到您的 IP 位于中国大陆${NC}"
        echo -e "${YELLOW}  由于网络原因，访问 GitHub 可能较慢或失败${NC}"
        echo -e ""
        read -rp "是否配置 GitHub 反代加速？(Y/n): " use_proxy
        use_proxy=${use_proxy:-Y}

        if [[ "$use_proxy" =~ ^[Yy]$ ]]; then
            echo -e ""
            echo -e "${BLUE}请输入反代地址（直接回车使用默认值）${NC}"
            echo -e "${CYAN}默认反代: https://acc.banez.de/${NC}"
            echo -e "${YELLOW}提示: 反代地址格式应为 https://xxx.xxx/ (末尾带斜杠)${NC}"
            echo -e ""
            read -rp "反代地址: " custom_proxy

            # 使用默认值或用户输入
            if [[ -z "$custom_proxy" ]]; then
                PROXY="https://acc.banez.de/"
            else
                # 确保地址末尾有斜杠
                if [[ ! "$custom_proxy" =~ /$ ]]; then
                    custom_proxy="${custom_proxy}/"
                fi
                PROXY="$custom_proxy"
            fi

            echo -e ""
            echo -e "${BLUE}▶ 正在测试代理连接...${NC}"

            # 测试代理是否可用
            if curl -sL --connect-timeout 10 "${PROXY}https://raw.githubusercontent.com/qqrrooty/EZrealm/main/version.txt" &>/dev/null; then
                echo -e "${GREEN}✓ 代理连接成功！${NC}"

                # 询问是否保存配置
                read -rp "是否保存此代理配置？(Y/n): " save_config
                save_config=${save_config:-Y}
                if [[ "$save_config" =~ ^[Yy]$ ]]; then
                    echo "$PROXY" > "$PROXY_CONFIG_FILE"
                    echo -e "${GREEN}✓ 代理配置已保存${NC}"
                fi
            else
                echo -e "${YELLOW}⚠ 代理连接测试失败，但仍将尝试使用${NC}"
                echo -e "${YELLOW}  如果后续下载失败，请检查代理地址是否正确${NC}"
            fi

            init_urls
            echo -e "${GREEN}✓ 已配置代理: ${PROXY}${NC}"
        else
            echo -e "${YELLOW}▶ 将直接连接 GitHub（可能较慢）${NC}"
            init_urls
        fi
    else
        echo -e "${GREEN}✓ 网络环境正常，无需配置代理${NC}"
        init_urls
    fi
}

# ========================================
# 清除代理配置
# ========================================
clear_proxy_config() {
    if [[ -f "$PROXY_CONFIG_FILE" ]]; then
        rm -f "$PROXY_CONFIG_FILE"
        PROXY=""
        init_urls
        echo -e "${GREEN}✓ 代理配置已清除${NC}"
    else
        echo -e "${YELLOW}▶ 没有保存的代理配置${NC}"
    fi
}

# ========================================
# 代理管理菜单
# ========================================
manage_proxy() {
    echo -e "\n${YELLOW}代理设置管理：${NC}"
    echo -e ""

    # 显示当前状态
    if [[ -n "$PROXY" ]]; then
        echo -e "当前代理: ${GREEN}${PROXY}${NC}"
    else
        echo -e "当前代理: ${YELLOW}未配置${NC}"
    fi

    if [[ -f "$PROXY_CONFIG_FILE" ]]; then
        echo -e "已保存配置: ${CYAN}$(cat "$PROXY_CONFIG_FILE")${NC}"
    fi

    echo -e ""
    echo "1. 重新配置代理"
    echo "2. 手动输入代理地址"
    echo "3. 清除代理配置"
    echo "4. 测试当前代理"
    echo "0. 返回主菜单"
    echo -e ""
    read -rp "请选择: " choice

    case $choice in
        1)
            # 强制重新检测并配置
            PROXY=""
            rm -f "$PROXY_CONFIG_FILE" 2>/dev/null
            setup_proxy
            ;;
        2)
            echo -e ""
            echo -e "${BLUE}请输入反代地址${NC}"
            echo -e "${YELLOW}提示: 反代地址格式应为 https://xxx.xxx/ (末尾带斜杠)${NC}"
            echo -e "${CYAN}示例: https://acc.banez.de/${NC}"
            echo -e ""
            read -rp "反代地址: " custom_proxy

            if [[ -z "$custom_proxy" ]]; then
                echo -e "${RED}✖ 未输入地址${NC}"
                return
            fi

            # 确保地址末尾有斜杠
            if [[ ! "$custom_proxy" =~ /$ ]]; then
                custom_proxy="${custom_proxy}/"
            fi

            PROXY="$custom_proxy"
            init_urls

            # 测试代理
            echo -e "${BLUE}▶ 正在测试代理连接...${NC}"
            if curl -sL --connect-timeout 10 "${PROXY}https://raw.githubusercontent.com/qqrrooty/EZrealm/main/version.txt" &>/dev/null; then
                echo -e "${GREEN}✓ 代理连接成功！${NC}"
                read -rp "是否保存此代理配置？(Y/n): " save_config
                save_config=${save_config:-Y}
                if [[ "$save_config" =~ ^[Yy]$ ]]; then
                    echo "$PROXY" > "$PROXY_CONFIG_FILE"
                    echo -e "${GREEN}✓ 代理配置已保存${NC}"
                fi
            else
                echo -e "${YELLOW}⚠ 代理连接测试失败，但已设置${NC}"
            fi
            ;;
        3)
            clear_proxy_config
            ;;
        4)
            if [[ -z "$PROXY" ]]; then
                echo -e "${YELLOW}▶ 当前未配置代理，测试直连...${NC}"
                if curl -sL --connect-timeout 10 "https://raw.githubusercontent.com/qqrrooty/EZrealm/main/version.txt" &>/dev/null; then
                    echo -e "${GREEN}✓ 直连 GitHub 成功${NC}"
                else
                    echo -e "${RED}✖ 直连 GitHub 失败，建议配置代理${NC}"
                fi
            else
                echo -e "${BLUE}▶ 测试代理: ${PROXY}${NC}"
                if curl -sL --connect-timeout 10 "${PROXY}https://raw.githubusercontent.com/qqrrooty/EZrealm/main/version.txt" &>/dev/null; then
                    echo -e "${GREEN}✓ 代理连接成功${NC}"
                else
                    echo -e "${RED}✖ 代理连接失败${NC}"
                fi
            fi
            ;;
        0|*)
            return
            ;;
    esac
}

# ========================================
# 初始化检查
# ========================================
init_check() {
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}✖ 必须使用root权限运行本脚本${NC}"
        exit 1
    fi

    # 检查并安装必要工具
    local missing_tools=()

    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    if ! command -v wget &> /dev/null; then
        missing_tools+=("wget")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${YELLOW}▶ 正在安装必要工具: ${missing_tools[*]}...${NC}"
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y "${missing_tools[@]}"
        elif command -v yum &> /dev/null; then
            yum install -y "${missing_tools[@]}"
        elif command -v dnf &> /dev/null; then
            dnf install -y "${missing_tools[@]}"
        elif command -v pacman &> /dev/null; then
            pacman -Sy --noconfirm "${missing_tools[@]}"
        else
            echo -e "${RED}✖ 无法自动安装工具，请手动安装: ${missing_tools[*]}${NC}"
            exit 1
        fi
    fi

    # 创建必要目录
    mkdir -p "$REALM_DIR"
    if [[ ! -w $(dirname "$LOG_FILE") ]]; then
        echo -e "${RED}✖ 日志目录不可写，请检查权限${NC}"
        exit 1
    fi
    touch "$LOG_FILE" || {
        echo -e "${RED}✖ 无法创建日志文件${NC}"
        exit 1
    }

    log "脚本启动 v$CURRENT_VERSION"
}

# ========================================
# 日志系统
# ========================================
log() {
    local log_msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$log_msg" >> "$LOG_FILE"
}

# ========================================
# 版本比较函数
# ========================================
version_compare() {
    if [[ "$1" == "$2" ]]; then
        return 0  # 版本相同
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1  # 当前版本更高
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2  # 远程版本更高
        fi
    done
    return 0
}

# ========================================
# 自动更新模块
# ========================================
check_update() {
    echo -e "\n${BLUE}▶ 正在检查更新...${NC}"
    
    # 获取远程版本（更严格的过滤）
    remote_version=$(curl -sL $VERSION_CHECK_URL 2>> "$LOG_FILE" | head -n1 | sed 's/[^0-9.]//g')
    if [[ -z "$remote_version" ]]; then
        log "版本检查失败：无法获取远程版本"
        echo -e "${RED}✖ 无法获取远程版本信息，请检查网络连接${NC}"
        return 1
    fi
    
    # 验证版本号格式
    if ! [[ "$remote_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "版本检查失败：无效的远程版本号 '$remote_version'"
        echo -e "${RED}✖ 远程版本号格式错误${NC}"
        return 1
    fi

    # 版本比较
    version_compare "$CURRENT_VERSION" "$remote_version"
    case $? in
        0)
            echo -e "${GREEN}✓ 当前已是最新版本 v${CURRENT_VERSION}${NC}"
            return 1
            ;;
        1)
            echo -e "${YELLOW}⚠ 本地版本 v${CURRENT_VERSION} 比远程版本 v${remote_version} 更高${NC}"
            return 1
            ;;
        2)
            echo -e "${YELLOW}▶ 发现新版本 v${remote_version}${NC}"
            return 0
            ;;
    esac
}

perform_update() {
    echo -e "${BLUE}▶ 开始更新...${NC}"
    log "尝试从 $UPDATE_URL 下载更新"
    
    # 下载临时文件
    if ! curl -sL $UPDATE_URL -o "$0.tmp"; then
        log "更新失败：下载脚本失败"
        echo -e "${RED}✖ 下载更新失败，请检查网络${NC}"
        return 1
    fi
    
    # 验证下载内容
    if ! grep -q "CURRENT_VERSION" "$0.tmp"; then
        log "更新失败：下载文件无效"
        echo -e "${RED}✖ 下载文件校验失败${NC}"
        rm -f "$0.tmp"
        return 1
    fi
    
    # 替换脚本
    chmod +x "$0.tmp"
    mv -f "$0.tmp" "$0"
    log "更新完成，重启脚本"
    
    echo -e "${GREEN}✓ 更新成功，重新启动脚本...${NC}"
    # 传递参数跳过更新检查
    exec "$0" "--no-update" "$@"
}

# ========================================
# 架构检测
# ========================================
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            echo "x86_64-unknown-linux-gnu"
            ;;
        aarch64|arm64)
            echo "aarch64-unknown-linux-gnu"
            ;;
        armv7l|armhf)
            echo "armv7-unknown-linux-gnueabihf"
            ;;
        *)
            echo ""
            ;;
    esac
}

# ========================================
# 获取已安装的 Realm 版本
# ========================================
get_installed_version() {
    if [[ -x "$REALM_DIR/realm" ]]; then
        "$REALM_DIR/realm" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1
    else
        echo ""
    fi
}

# ========================================
# 核心功能模块
# ========================================
deploy_realm() {
    log "开始安装Realm"
    echo -e "${BLUE}▶ 正在安装Realm...${NC}"

    # 检测系统架构
    local arch_suffix
    arch_suffix=$(detect_arch)
    if [[ -z "$arch_suffix" ]]; then
        echo -e "${RED}✖ 不支持的系统架构: $(uname -m)${NC}"
        echo -e "${YELLOW}  支持的架构: x86_64, aarch64, armv7l${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ 检测到系统架构: $(uname -m) → ${arch_suffix}${NC}"

    mkdir -p "$REALM_DIR"
    cd "$REALM_DIR" || exit 1

    # 获取最新版本号
    echo -e "${BLUE}▶ 正在检测最新版本...${NC}"
    LATEST_VERSION=$(curl -sL "${PROXY}https://github.com/zhboner/realm/releases" | grep -oE '/zhboner/realm/releases/tag/v[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d'/' -f6 | tr -d 'v')

    # 版本号验证
    if [[ -z "$LATEST_VERSION" || ! "$LATEST_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "版本检测失败，使用备用版本2.7.0"
        LATEST_VERSION="2.7.0"
        echo -e "${YELLOW}⚠ 无法获取最新版本，使用备用版本 v${LATEST_VERSION}${NC}"
    else
        echo -e "${GREEN}✓ 检测到最新版本 v${LATEST_VERSION}${NC}"
    fi

    # 检查是否需要更新
    local installed_version
    installed_version=$(get_installed_version)
    if [[ -n "$installed_version" ]]; then
        echo -e "${CYAN}  当前已安装版本: v${installed_version}${NC}"
        if [[ "$installed_version" == "$LATEST_VERSION" ]]; then
            read -rp "已是最新版本，是否重新安装？(y/N): " reinstall
            if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
                echo "已取消安装。"
                return 0
            fi
        fi
    fi

    # 下载最新版本
    DOWNLOAD_URL="${PROXY}https://github.com/zhboner/realm/releases/download/v${LATEST_VERSION}/realm-${arch_suffix}.tar.gz"
    echo -e "${BLUE}▶ 正在下载 Realm v${LATEST_VERSION}...${NC}"
    if ! wget --show-progress -qO realm.tar.gz "$DOWNLOAD_URL"; then
        log "安装失败：下载错误"
        echo -e "${RED}✖ 文件下载失败，请检查：${NC}"
        echo -e "1. 网络连接状态"
        echo -e "2. GitHub访问权限"
        echo -e "3. 手动验证下载地址: $DOWNLOAD_URL"
        return 1
    fi

    # 解压安装
    tar -xzf realm.tar.gz
    chmod +x realm
    rm realm.tar.gz

    # 初始化配置文件
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "[network]\nno_tcp = false\nuse_udp = true" > "$CONFIG_FILE"
    fi

    # 创建服务文件
    echo -e "${BLUE}▶ 创建系统服务...${NC}"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Realm Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=$REALM_DIR/realm -c $CONFIG_FILE
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log "安装成功"
    echo -e "${GREEN}✔ 安装完成！${NC}"
}

# 打印规则表头
print_rules_header() {
    echo -e "                   ${YELLOW}当前 Realm 转发规则${NC}                   "
    echo -e "${BLUE}---------------------------------------------------------------------------------------------------------${NC}${YELLOW}"
    printf "%-5s| %-30s| %-40s| %-20s\n" "序号" "   本地地址:端口 " "   目标地址:端口 " "备注"
    echo -e "${NC}${BLUE}---------------------------------------------------------------------------------------------------------${NC}"
}

# 查看转发规则
show_rules() {
    print_rules_header

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${YELLOW}配置文件不存在${NC}"
        return
    fi

    local IFS=$'\n'
    local lines=($(grep -n 'listen =' "$CONFIG_FILE" 2>/dev/null))

    if [ ${#lines[@]} -eq 0 ]; then
        echo -e "没有发现任何转发规则。"
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo "$line" | cut -d ':' -f 1)
        local listen_info=$(sed -n "${line_number}p" "$CONFIG_FILE" | cut -d '"' -f 2)
        local remote_info=$(sed -n "$((line_number + 1))p" "$CONFIG_FILE" | cut -d '"' -f 2)
        local remark=$(sed -n "$((line_number-1))p" "$CONFIG_FILE" | grep "^# 备注:" | cut -d ':' -f 2)

        printf "%-4s| %-24s| %-34s| %-20s\n" " $index" "$listen_info" "$remote_info" "$remark"
        echo -e "${BLUE}---------------------------------------------------------------------------------------------------------${NC}"
        ((index++))
    done
}

# 添加转发规则
add_rule() {
    log "添加转发规则"
    while : ; do
        echo -e "\n${BLUE}▶ 添加新规则（输入 q 退出）${NC}"
        
        # 获取输入
        read -rp "本地监听端口: " local_port
        [ "$local_port" = "q" ] && break
        read -rp "目标服务器IP: " remote_ip
        read -rp "目标端口: " remote_port
        read -rp "规则备注: " remark

        # 输入验证
        if ! [[ "$local_port" =~ ^[0-9]+$ ]] || ! [[ "$remote_port" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}✖ 端口必须为数字！${NC}"
            continue
        fi

        # 端口范围验证
        if (( local_port < 1 || local_port > 65535 )); then
            echo -e "${RED}✖ 本地端口必须在 1-65535 范围内！${NC}"
            continue
        fi
        if (( remote_port < 1 || remote_port > 65535 )); then
            echo -e "${RED}✖ 目标端口必须在 1-65535 范围内！${NC}"
            continue
        fi

        # 监听模式选择
        echo -e "\n${YELLOW}请选择监听模式：${NC}"
        echo "1) 双栈监听 [::]:${local_port} (默认)"
        echo "2) 仅IPv4监听 0.0.0.0:${local_port}"
        echo "3) 自定义监听地址"
        read -rp "请输入选项 [1-3] (默认1): " ip_choice
        ip_choice=${ip_choice:-1}

        case $ip_choice in
            1)
                listen_addr="[::]:$local_port"
                desc="双栈监听"
                ;;
            2)
                listen_addr="0.0.0.0:$local_port"
                desc="仅IPv4"
                ;;
            3)
                while : ; do
                    read -rp "请输入完整监听地址(格式如 0.0.0.0:80 或 [::]:443): " listen_addr
                    # 格式验证
                    if ! [[ "$listen_addr" =~ ^([0-9a-fA-F.:]+|\[.*\]):[0-9]+$ ]]; then
                        echo -e "${RED}✖ 格式错误！示例: 0.0.0.0:80 或 [::]:443${NC}"
                        continue
                    fi
                    break
                done
                desc="自定义监听"
                ;;
            *)
                echo -e "${RED}无效选择，使用默认值！${NC}"
                listen_addr="[::]:$local_port"
                desc="双栈监听"
                ;;
        esac

        # 写入配置文件
        cat >> "$CONFIG_FILE" <<EOF

[[endpoints]]
# 备注: $remark
listen = "$listen_addr"
remote = "$remote_ip:$remote_port"
EOF

        # 双栈提示
        if [ "$ip_choice" -eq 1 ]; then
            echo -e "\n${CYAN}ℹ 双栈监听需要确保：${NC}"
            echo -e "${CYAN}   - Realm 配置中 [network] 段的 ipv6_only = false${NC}"
            echo -e "${CYAN}   - 系统已启用 IPv6 双栈支持 (sysctl net.ipv6.bindv6only=0)${NC}"
        fi

        # 重启服务
        systemctl restart realm.service
        log "规则已添加: $listen_addr → $remote_ip:$remote_port"
        echo -e "${GREEN}✔ 添加成功！${NC}"
        
        read -rp "继续添加？(y/n): " cont
        [[ "$cont" != "y" ]] && break
    done
}

delete_rule() {
    print_rules_header

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${YELLOW}配置文件不存在${NC}"
        return
    fi

    local IFS=$'\n'
    local lines=($(grep -n '^\[\[endpoints\]\]' "$CONFIG_FILE" 2>/dev/null))

    if [ ${#lines[@]} -eq 0 ]; then
        echo "没有发现任何转发规则。"
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo "$line" | cut -d ':' -f 1)
        local remark_line=$((line_number + 1))
        local listen_line=$((line_number + 2))
        local remote_line=$((line_number + 3))

        local remark=$(sed -n "${remark_line}p" "$CONFIG_FILE" | grep "^# 备注:" | cut -d ':' -f 2)
        local listen_info=$(sed -n "${listen_line}p" "$CONFIG_FILE" | cut -d '"' -f 2)
        local remote_info=$(sed -n "${remote_line}p" "$CONFIG_FILE" | cut -d '"' -f 2)

        printf "%-4s| %-24s| %-34s| %-20s\n" " $index" "$listen_info" "$remote_info" "$remark"
        echo -e "${BLUE}---------------------------------------------------------------------------------------------------------${NC}"
        ((index++))
    done

    echo ""
    echo "请输入要删除的转发规则序号，直接按回车返回主菜单。"
    read -rp "选择: " choice
    if [ -z "$choice" ]; then
        echo "返回主菜单。"
        return
    fi

    if ! [[ $choice =~ ^[0-9]+$ ]]; then
        echo -e "${RED}无效输入，请输入数字。${NC}"
        return
    fi

    if [ "$choice" -lt 1 ] || [ "$choice" -gt ${#lines[@]} ]; then
        echo -e "${RED}选择超出范围，请输入有效序号。${NC}"
        return
    fi

    # 二次确认
    local chosen_line=${lines[$((choice-1))]}
    local start_line=$(echo "$chosen_line" | cut -d ':' -f 1)
    local listen_info=$(sed -n "$((start_line + 2))p" "$CONFIG_FILE" | cut -d '"' -f 2)
    local remote_info=$(sed -n "$((start_line + 3))p" "$CONFIG_FILE" | cut -d '"' -f 2)

    echo -e "${YELLOW}即将删除规则: ${listen_info} → ${remote_info}${NC}"
    read -rp "确认删除？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消删除。"
        return
    fi

    # 找到下一个 [[endpoints]] 行，确定删除范围的结束行
    local next_endpoints_line=$(grep -n '^\[\[endpoints\]\]' "$CONFIG_FILE" | grep -A 1 "^$start_line:" | tail -n 1 | cut -d ':' -f 1)

    if [ -z "$next_endpoints_line" ] || [ "$next_endpoints_line" -le "$start_line" ]; then
        end_line=$(wc -l < "$CONFIG_FILE")
    else
        end_line=$((next_endpoints_line - 1))
    fi

    # 使用 sed 删除指定行范围的内容
    sed -i "${start_line},${end_line}d" "$CONFIG_FILE"

    # 检查并删除可能多余的空行
    sed -i '/^\s*$/d' "$CONFIG_FILE"

    log "删除规则: $listen_info → $remote_info"
    echo -e "${GREEN}✔ 转发规则已删除。${NC}"

    # 重启服务
    systemctl restart realm.service
}

service_control() {
    case $1 in
        start)
            systemctl unmask realm.service
            systemctl daemon-reload
            systemctl restart realm.service
            systemctl enable realm.service
            log "启动服务"
            echo -e "${GREEN}✔ 服务已启动${NC}"
            ;;
        stop)
            systemctl stop realm
            log "停止服务"
            echo -e "${YELLOW}⚠ 服务已停止${NC}"
            ;;
        restart)
            systemctl unmask realm.service
            systemctl daemon-reload
            systemctl restart realm.service
            systemctl enable realm.service
            log "重启服务"
            echo -e "${GREEN}✔ 服务已重启${NC}"
            ;;
        status)
            if systemctl is-active --quiet realm; then
                echo -e "${GREEN}● 服务运行中${NC}"
            else
                echo -e "${RED}● 服务未运行${NC}"
            fi
            ;;
    esac
}

manage_cron() {
    echo -e "\n${YELLOW}定时任务管理：${NC}"
    echo "1. 添加每日重启任务"
    echo "2. 删除所有任务"
    echo "3. 查看当前任务"
    read -rp "请选择: " choice

    case $choice in
        1)
            read -rp "输入每日重启时间 (0-23): " hour
            if [[ "$hour" =~ ^[0-9]+$ ]] && (( hour >= 0 && hour <= 23 )); then
                echo "0 $hour * * * root /usr/bin/systemctl restart realm" >>/etc/crontab
                log "添加定时任务：每日 $hour 时重启"
                echo -e "${GREEN}✔ 定时任务已添加！${NC}"
            else
                echo -e "${RED}✖ 无效时间！${NC}"
            fi
            ;;
        2)
            sed -i "/realm/d" /etc/crontab
            log "清除定时任务"
            echo -e "${YELLOW}✔ 定时任务已清除！${NC}"
            ;;
        3)
            echo -e "\n${BLUE}当前定时任务：${NC}"
            cat /etc/crontab | grep --color=auto "realm"
            ;;
        *)
            echo -e "${RED}✖ 无效选择！${NC}"
            ;;
    esac
}

uninstall() {
    log "开始卸载"
    echo -e "${YELLOW}▶ 正在卸载...${NC}"
    
    systemctl stop realm
    systemctl disable realm
    rm -rf "$REALM_DIR"
    rm -f "$SERVICE_FILE"
    rm -rf /root/realm
    rm -rf "$(pwd)"/realm.sh
    sed -i "/realm/d" /etc/crontab
    systemctl daemon-reload
    
    log "卸载完成"
    echo -e "${GREEN}✔ 已完全卸载！${NC}"
}

# ========================================
# 安装状态检测
# ========================================
check_installed() {
    if [[ -f "$REALM_DIR/realm" && -f "$SERVICE_FILE" ]]; then
        local version
        version=$(get_installed_version)
        if [[ -n "$version" ]]; then
            echo -e "${GREEN}已安装${NC} (v${version})"
        else
            echo -e "${GREEN}已安装${NC}"
        fi
    else
        echo -e "${RED}未安装${NC}"
    fi
}

# ========================================
# 主界面
# ========================================
main_menu() {
    clear
    init_check

    # 处理跳过更新检查参数
    local skip_update=false
    local skip_proxy=false
    for arg in "$@"; do
        case "$arg" in
            --no-update) skip_update=true ;;
            --no-proxy) skip_proxy=true ;;
        esac
    done

    # 配置代理（首次运行）
    if ! $skip_proxy; then
        setup_proxy
    else
        init_urls
    fi

    sleep 1

    # 首次运行检查更新
    if ! $skip_update; then
        check_update && perform_update "$@"
    fi

    while true; do
        # 显示代理状态
        local proxy_status
        if [[ -n "$PROXY" ]]; then
            proxy_status="${GREEN}已启用${NC} (${CYAN}${PROXY}${NC})"
        else
            proxy_status="${YELLOW}未启用${NC}"
        fi

        echo -e "${YELLOW}▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂${NC}"
        echo -e "  "
        echo -e "                ${BLUE}Realm 高级管理脚本 v$CURRENT_VERSION"
        echo -e "        修改by：Ami    修改日期：2025/4/1"
        echo -e "        修改内容:1.基本重做了脚本"
        echo -e "                 2.新增了自动更新脚本"
        echo -e "                 3.realm支持检测最新版本"
        echo -e "                 4.新增中国IP检测与GitHub反代支持"
        echo -e "    (1)安装前请先更新系统软件包，缺少命令可能无法安装"
        echo -e "    (2)如果启动失败请检查 /root/realm/config.toml下有无多余配置或者卸载后重新配置"
        echo -e "    (3)该脚本只在debian系统下测试，未做其他系统适配，安装命令有别，可能无法启动。如若遇到问题，请自行解决"
        echo -e "    仓库：https://github.com/qqrrooty/EZrealm"
        echo -e "    2025/4/1 更新：有人反馈该新版本添加规则过多后无法启动，如果遇到问题，可以尝试回退老版本（大概率是备注问题）"
        echo -e "        删除该脚本 rm realm.sh"
        echo -e "        运行 wget -N ${PROXY}https://raw.githubusercontent.com/qqrrooty/EZrealm/main/realm-2024.sh && chmod +x realm.sh && ./realm.sh"
        echo -e "        或者 wget -N ${PROXY}https://raw.githubusercontent.com/qqrrooty/EZrealm/main/realm-2025.sh && chmod +x realm.sh && ./realm.sh${NC}"
        echo -e "${YELLOW}▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂${NC}"
        echo -e "  "
        echo -e "${YELLOW}服务状态：$(service_control status)${NC}"
        echo -e "${YELLOW}安装状态：$(check_installed)${NC}"
        echo -e "${YELLOW}代理状态：${proxy_status}${NC}"
        echo -e "  "
        echo -e "${YELLOW}------------------${NC}"
        echo "1. 安装/更新 Realm"
        echo -e "${YELLOW}------------------${NC}"
        echo "2. 添加转发规则"
        echo "3. 查看转发规则"
        echo "4. 删除转发规则"
        echo -e "${YELLOW}------------------${NC}"
        echo "5. 启动服务"
        echo "6. 停止服务"
        echo "7. 重启服务"
        echo -e "${YELLOW}------------------${NC}"
        echo "8. 定时任务管理"
        echo "9. 查看日志"
        echo -e "${YELLOW}------------------${NC}"
        echo "10. 完全卸载"
        echo "11. 代理设置"
        echo -e "${YELLOW}------------------${NC}"
        echo "0. 退出脚本"
        echo -e "${YELLOW}------------------${NC}"

        read -rp "请输入选项: " choice
        case $choice in
            1) deploy_realm ;;
            2) add_rule ;;
            3) show_rules ;;
            4) delete_rule ;;
            5) service_control start ;;
            6) service_control stop ;;
            7) service_control restart ;;
            8) manage_cron ;;
            9)
                echo -e "\n${BLUE}最近日志：${NC}"
                tail -n 10 "$LOG_FILE"
                ;;
            10)
                read -rp "确认完全卸载？(y/n): " confirm
                if [[ "$confirm" == "y" ]]; then
                    uninstall
                    read -rp "按回车键继续..."
                    clear
                    exit 0
                fi
                ;;
            11) manage_proxy ;;
            0) exit 0
            ;;
            *) echo -e "${RED}无效选项！${NC}" ;;
        esac
        read -rp "按回车键继续..."
        clear
    done
}

# ========================================
# 脚本入口
# ========================================
main_menu "$@"
