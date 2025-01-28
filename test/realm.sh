#!/bin/bash

# ========================================
# 全局配置
# ========================================
CURRENT_VERSION="1.0.0"
UPDATE_URL="https://raw.githubusercontent.com/qqrrooty/EZrealm/main/test/realm.sh"
VERSION_CHECK_URL="https://raw.githubusercontent.com/qqrrooty/EZrealm/main/version.txt"
REALM_DIR="/root/realm"
CONFIG_FILE="$REALM_DIR/config.toml"
SERVICE_FILE="/etc/systemd/system/realm.service"
LOG_FILE="/var/log/realm_manager.log"

# ========================================
# 颜色定义
# ========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========================================
# 初始化检查
# ========================================
init_check() {
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}✖ 必须使用root权限运行本脚本${NC}"
        exit 1
    fi

    # 创建必要目录
    mkdir -p "$REALM_DIR"
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
# 自动更新模块
# ========================================
check_update() {
    echo -e "\n${BLUE}▶ 正在检查更新...${NC}"
    
    # 获取远程版本
    remote_version=$(curl -sL $VERSION_CHECK_URL 2>/dev/null | head -n1 | tr -d 'v')
    
    # 验证版本号格式
    if ! [[ "$remote_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "版本检查失败：无效的远程版本号"
        return 1
    fi

    # 比较版本
    if version_compare "$CURRENT_VERSION" "$remote_version"; then
        echo -e "${GREEN}✓ 当前已是最新版本 v${CURRENT_VERSION}${NC}"
        return 1
    else
        echo -e "${YELLOW}▶ 发现新版本 v${remote_version}${NC}"
        return 0
    fi
}

version_compare() {
    [[ "$1" == "$2" ]] && return 0
    local IFS=.
    local i ver1=($1) ver2=($2)
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do ver1[i]=0; done
    for ((i=0; i<${#ver1[@]}; i++)); do
        [[ -z ${ver2[i]} ]] && ver2[i]=0
        ((10#${ver1[i]} > 10#${ver2[i]})) && return 1
    done
    return 0
}

perform_update() {
    local tmp_file=$(mktemp /tmp/realm_update.XXXXXX)
    
    echo -e "${YELLOW}▶ 正在下载新版本...${NC}"
    if ! curl -sL $UPDATE_URL -o "$tmp_file"; then
        log "更新失败：下载错误"
        echo -e "${RED}✖ 下载失败，请检查网络连接${NC}"
        rm -f "$tmp_file"
        return 1
    fi

    # 基础验证
    if ! head -n1 "$tmp_file" | grep -q '^#!/bin/bash' || ! grep -q "CURRENT_VERSION" "$tmp_file"; then
        log "更新失败：文件校验错误"
        echo -e "${RED}✖ 文件校验失败，可能下载损坏${NC}"
        rm -f "$tmp_file"
        return 1
    fi

    # 获取新版本号
    new_version=$(grep -m1 "CURRENT_VERSION=" "$tmp_file" | cut -d'"' -f2)
    
    # 替换文件
    chmod +x "$tmp_file"
    if mv "$tmp_file" "$0"; then
        log "成功更新到 v$new_version"
        echo -e "\n${GREEN}✔ 更新成功！重启脚本...${NC}"
        exec "$0" "$@"
    else
        log "更新失败：文件替换错误"
        echo -e "${RED}✖ 文件替换失败，请检查权限${NC}"
        rm -f "$tmp_file"
        return 1
    fi
}

# ========================================
# 核心功能模块
# ========================================
deploy_realm() {
    log "开始安装Realm"
    echo -e "${BLUE}▶ 正在安装Realm...${NC}"
    
    mkdir -p "$REALM_DIR"
    cd "$REALM_DIR" || exit 1

    # 获取最新版本号
    echo -e "${BLUE}▶ 正在检测最新版本...${NC}"
    LATEST_VERSION=$(curl -sL https://github.com/zhboner/realm/releases | grep -oE '/zhboner/realm/releases/tag/v[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d'/' -f6 | tr -d 'v')
    
    # 版本号验证
    if [[ -z "$LATEST_VERSION" || ! "$LATEST_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "版本检测失败，使用备用版本2.7.0"
        LATEST_VERSION="2.7.0"
        echo -e "${YELLOW}⚠ 无法获取最新版本，使用备用版本 v${LATEST_VERSION}${NC}"
    else
        echo -e "${GREEN}✓ 检测到最新版本 v${LATEST_VERSION}${NC}"
    fi

    # 下载最新版本
    DOWNLOAD_URL="https://github.com/zhboner/realm/releases/download/v${LATEST_VERSION}/realm-x86_64-unknown-linux-gnu.tar.gz"
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

# 查看转发规则
show_rules() {
  echo -e "                   ${YELLOW}当前 Realm 转发规则${NC}                   "
  echo -e "${YELLOW}--------------------------------------------------------${NC}"
  printf "%-5s| %-15s| %-35s| %-20s\n" "序号" "本地地址:端口 " "    目的地地址:端口 " "备注"
  echo -e "${YELLOW}--------------------------------------------------------${NC}"
    local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
    # 搜索所有包含 listen 的行，表示转发规则的起始行
    local lines=($(grep -n 'listen =' /root/realm/config.toml))
    
    if [ ${#lines[@]} -eq 0 ]; then
  echo -e "没有发现任何转发规则。"
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo $line | cut -d ':' -f 1)
        local listen_info=$(sed -n "${line_number}p" /root/realm/config.toml | cut -d '"' -f 2)
        local remote_info=$(sed -n "$((line_number + 1))p" /root/realm/config.toml | cut -d '"' -f 2)
        local remark=$(sed -n "$((line_number-1))p" /root/realm/config.toml | grep "^# 备注:" | cut -d ':' -f 2)
        
        local listen_ip_port=$listen_info
        local remote_ip_port=$remote_info
        
    printf "%-4s| %-14s| %-28s| %-20s\n" " $index" "$listen_info" "$remote_info" "$remark"
    echo -e "${YELLOW}--------------------------------------------------------${NC}"
        let index+=1
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

        # 写入配置文件（关键修正点）
        sudo tee -a "$CONFIG_FILE" > /dev/null <<EOF

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
        sudo systemctl restart realm.service
        log "规则已添加: $listen_addr → $remote_ip:$remote_port"
        echo -e "${GREEN}✔ 添加成功！${NC}"
        
        read -rp "继续添加？(y/n): " cont
        [[ "$cont" != "y" ]] && break
    done
}

delete_rule() {
  echo -e "                   ${YELLOW}当前 Realm 转发规则${NC}                   "
  echo -e "${YELLOW}--------------------------------------------------------${NC}"
  printf "%-5s| %-15s| %-35s| %-20s\n" "序号" "本地地址:端口 " "    目的地地址:端口 " "备注"
  echo -e "${YELLOW}--------------------------------------------------------${NC}"
    local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
    # 搜索所有包含 [[endpoints]] 的行，表示转发规则的起始行
    local lines=($(grep -n '^\[\[endpoints\]\]' /root/realm/config.toml))
    
    if [ ${#lines[@]} -eq 0 ]; then
        echo "没有发现任何转发规则。"
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo $line | cut -d ':' -f 1)
        local remark_line=$((line_number + 1))
        local listen_line=$((line_number + 2))
        local remote_line=$((line_number + 3))

        local remark=$(sed -n "${remark_line}p" /root/realm/config.toml | grep "^# 备注:" | cut -d ':' -f 2)
        local listen_info=$(sed -n "${listen_line}p" /root/realm/config.toml | cut -d '"' -f 2)
        local remote_info=$(sed -n "${remote_line}p" /root/realm/config.toml | cut -d '"' -f 2)

        local listen_ip_port=$listen_info
        local remote_ip_port=$remote_info

    printf "%-4s| %-14s| %-28s| %-20s\n" " $index" "$listen_info" "$remote_info" "$remark"
    echo -e "${YELLOW}--------------------------------------------------------${NC}"
        let index+=1
    done


    echo "请输入要删除的转发规则序号，直接按回车返回主菜单。"
    read -p "选择: " choice
    if [ -z "$choice" ]; then
        echo "返回主菜单。"
        return
    fi

    if ! [[ $choice =~ ^[0-9]+$ ]]; then
        echo "无效输入，请输入数字。"
        return
    fi

    if [ $choice -lt 1 ] || [ $choice -gt ${#lines[@]} ]; then
        echo "选择超出范围，请输入有效序号。"
        return
  fi

  local chosen_line=${lines[$((choice-1))]}
  local start_line=$(echo $chosen_line | cut -d ':' -f 1)

  # 找到下一个 [[endpoints]] 行，确定删除范围的结束行
  local next_endpoints_line=$(grep -n '^\[\[endpoints\]\]' /root/realm/config.toml | grep -A 1 "^$start_line:" | tail -n 1 | cut -d ':' -f 1)

  if [ -z "$next_endpoints_line" ] || [ "$next_endpoints_line" -le "$start_line" ]; then
    # 如果没有找到下一个 [[endpoints]]，则删除到文件末尾
    end_line=$(wc -l < /root/realm/config.toml)
  else
    # 如果找到了下一个 [[endpoints]]，则删除到它的前一行
    end_line=$((next_endpoints_line - 1))
  fi

  # 使用 sed 删除指定行范围的内容
  sed -i "${start_line},${end_line}d" /root/realm/config.toml

  # 检查并删除可能多余的空行
  sed -i '/^\s*$/d' /root/realm/config.toml

  echo "转发规则及其备注已删除。"

  # 重启服务
  sudo systemctl restart realm.service
}

service_control() {
    case $1 in
        start)
            systemctl start realm
            log "启动服务"
            echo -e "${GREEN}✔ 服务已启动${NC}"
            ;;
        stop)
            systemctl stop realm
            log "停止服务"
            echo -e "${YELLOW}⚠ 服务已停止${NC}"
            ;;
        restart)
            systemctl restart realm
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
                (crontab -l 2>/dev/null; echo "0 $hour * * * systemctl restart realm") | crontab -
                log "添加定时任务：每日 $hour 时重启"
                echo -e "${GREEN}✔ 定时任务已添加！${NC}"
            else
                echo -e "${RED}✖ 无效时间！${NC}"
            fi
            ;;
        2)
            crontab -l | grep -v "realm" | crontab -
            log "清除定时任务"
            echo -e "${YELLOW}✔ 定时任务已清除！${NC}"
            ;;
        3)
            echo -e "\n${BLUE}当前定时任务：${NC}"
            crontab -l | grep --color=auto "realm"
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
    crontab -l | grep -v "realm" | crontab -
    systemctl daemon-reload
    
    log "卸载完成"
    echo -e "${GREEN}✔ 已完全卸载！${NC}"
}

# ========================================
# 安装状态检测
# ========================================
check_installed() {
    if [[ -f "$REALM_DIR/realm" && -f "$SERVICE_FILE" ]]; then
        echo -e "${GREEN}已安装${NC}"
    else
        echo -e "${RED}未安装${NC}"
    fi
}

# ========================================
# 主界面
# ========================================
main_menu() {
    init_check
    check_update && perform_update "$@"

    while true; do
        clear
        echo -e "${YELLOW}▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂"
        echo -e "  "
        echo -e "      Realm 高级管理脚本 v$CURRENT_VERSION"
        echo -e "  "
        echo -e "     修改by：Azimi    修改日期：2025/1/29"
        echo -e "     修改内容：1.基本重做了脚本"
        echo -e "              2.支持了自动更新脚本"
        echo -e "              3.realm支持检测最新版本"
        echo -e "     "
        echo -e "     (1)安装前请先更新系统软件包，缺少命令可能无法安装"
        echo -e "     (2)如果启动失败请检查 /root/realm/config.toml下有无多余配置或者卸载后重新配置"
        echo -e "     (3)该脚本只在debian系统下测试，未做其他系统适配，安装命令有别，可能无法启动。如若遇到问题，请自行解决"
        echo -e "     仓库：https://github.com/qqrrooty/EZrealm"
        echo -e "     "
        echo -e "▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂${NC}"
        echo -e "  "
        echo -e "${BLUE}服务状态：$(service_control status)"
        echo -e "安装状态：$(check_installed)${NC}"
        echo -e "  "
        echo -e "${YELLOW}---------------------------${NC}"
        echo "1. 安装/更新 Realm"
        echo -e "${YELLOW}---------------------------${NC}"
        echo "2. 添加转发规则"
        echo "3. 查看转发规则"
        echo "4. 删除转发规则"
        echo -e "${YELLOW}---------------------------${NC}"
        echo "5. 启动服务"
        echo "6. 停止服务"
        echo "7. 重启服务"
        echo -e "${YELLOW}---------------------------${NC}"
        echo "8. 定时任务管理"
        echo "9. 查看日志"
        echo -e "${YELLOW}---------------------------${NC}"
        echo "10. 完全卸载"
        echo -e "${YELLOW}---------------------------${NC}"
        echo "0. 退出脚本"
        echo -e "${YELLOW}---------------------------${NC}"

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
                [[ "$confirm" == "y" ]] && uninstall
                ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选项！${NC}" ;;
        esac
        read -rp "按回车键继续..."
    done
}

# ========================================
# 脚本入口
# ========================================
main_menu "$@"
