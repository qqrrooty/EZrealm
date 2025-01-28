#!/bin/bash

# ========================================
# 全局配置
# ========================================
CURRENT_VERSION="1.0.3"
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

show_rules() {
    log "查看转发规则"
    
    # 初始化列宽为0
    local max_listen=0 max_remote=0 max_remark=0 rule_count=0

    # 第一遍扫描计算列宽
    while IFS= read -r line; do
        if [[ "$line" == "[["* ]]; then
            local remark="" listen="" remote=""
            while IFS= read -r config_line && [[ "$config_line" != "[["* ]]; do
                case $config_line in
                    "# 备注:"*) remark="${config_line#*: }" ;;
                    "listen ="*) 
                        listen="${config_line#*\"}"
                        listen="${listen%\"*}"
                        # 计算实际长度（去除颜色代码）
                        raw_len=$(echo -e "$listen" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g' | wc -m)
                        (( raw_len > max_listen )) && max_listen=$raw_len
                        ;;
                    "remote ="*) 
                        remote="${config_line#*\"}"
                        remote="${remote%\"*}"
                        raw_len=$(echo -e "$remote" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g' | wc -m)
                        (( raw_len > max_remote )) && max_remote=$raw_len
                        ;;
                esac
            done
            
            # 计算备注列宽
            raw_remark=$(echo -e "$remark" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')
            (( ${#raw_remark} > max_remark )) && max_remark=${#raw_remark}
            ((rule_count++))
        fi
    done < <(cat "$CONFIG_FILE" && echo "[[endpoints]]")

    # 设置最小列宽
    (( max_listen < 10 )) && max_listen=10
    (( max_remote < 10 )) && max_remote=10
    (( max_remark < 6 )) && max_remark=6

    # 动态生成表格
    sep_line=$(printf "┌─%*s─┬─%*s─┬─%*s─┬─%*s─┐" \
        4 "" $((max_listen+2)) "" $((max_remote+2)) "" $((max_remark+2)) "" |
        sed 's/ /─/g')

    echo -e "\n${YELLOW}当前转发规则（共 ${rule_count} 条）：${NC}"
    echo -e "$sep_line"
    printf "│ %-4s │ %-*s │ %-*s │ %-*s │\n" \
        "序号" \
        $max_listen "本地地址" \
        $max_remote "目标地址" \
        $max_remark "备注"
    echo -e "$sep_line" | sed 's/┬/┼/g'

    # 第二遍扫描输出带颜色的内容
    awk -v max_listen="$max_listen" -v max_remote="$max_remote" -v max_remark="$max_remark" '
        BEGIN { 
            RS="\\[\\[endpoints\\]\\]"
            FS="\n"
            idx=1
        }
        NR > 1 {
            listen=""; remote=""; remark=""
            for (i=1; i<=NF; i++) {
                if ($i ~ /^# 备注:/) {
                    split($i, arr, ": ");
                    remark = arr[2]
                }
                if ($i ~ /listen[[:space:]]*=/) {
                    split($i, arr, "\"");
                    listen = arr[2]
                }
                if ($i ~ /remote[[:space:]]*=/) {
                    split($i, arr, "\"");
                    remote = arr[2]
                }
            }
            if (listen != "" && remote != "") {
                # 添加颜色代码并保持对齐
                printf "│ \033[33m%-4d\033[0m │ \033[36m%-*s\033[0m │ \033[32m%-*s\033[0m │ %-*s │\n", 
                    idx++,
                    max_listen, listen, 
                    max_remote, remote, 
                    max_remark, remark
            }
        }
    ' "$CONFIG_FILE"

    echo -e "$sep_line" | sed 's/┬/┴/g'
}

add_rule() {
    log "添加转发规则"
    while : ; do
        echo -e "\n${BLUE}▶ 添加新规则（输入q退出）${NC}"
        
        # 获取基础配置
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
                    if ! [[ "$listen_addr" =~ ^[^:]+:[0-9]+$ ]]; then
                        echo -e "${RED}✖ 格式错误！需包含端口号 (示例: 192.168.1.1:80)${NC}"
                        continue
                    fi
                    ip_part=$(cut -d: -f1 <<< "$listen_addr")
                    port_part=$(cut -d: -f2 <<< "$listen_addr")
                    # IPv6方括号检查
                    if [[ "$ip_part" =~ ^\[.*\]$ ]]; then
                        ipv6_real=$(tr -d '[]' <<< "$ip_part")
                        if ! [[ "$ipv6_real" =~ ^[0-9a-fA-F:]+$ ]]; then
                            echo -e "${RED}✖ IPv6地址格式错误！${NC}"
                            continue
                        fi
                    elif [[ "$ip_part" =~ ^[0-9.]+$ ]]; then # IPv4基础格式
                        if ! [[ "$ip_part" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                            echo -e "${RED}✖ IPv4地址格式错误！${NC}"
                            continue
                        fi
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
# 备注: $remark ($desc)
listen = "$listen_addr"
remote = "$remote_ip:$remote_port"
EOF

        # 双栈模式提示
        if [ "$ip_choice" -eq 1 ]; then
            echo -e "\n${CYAN}ℹ 双栈模式需要确保 Realm 主配置满足以下条件：${NC}"
            echo -e "${CYAN}   [network] 段中 ipv6_only = false (默认值)${NC}"
            echo -e "${CYAN}   系统已启用 IPv6 双栈支持 (sysctl net.ipv6.bindv6only=0)${NC}"
        fi

        systemctl restart realm
        log "添加规则：$listen_addr → $remote_ip:$remote_port"
        echo -e "${GREEN}✔ 规则已添加！${NC}"
        
        read -rp "继续添加？(y/n): " cont
        [[ "$cont" != "y" ]] && break
    done
}

delete_rule() {
    log "删除转发规则"
    
    # 获取有效规则总数（排除注释中的[[endpoints]]）
    local total=$(awk '
        /^\[\[endpoints\]\]/ && !/^#/ { count++ } 
        END { print count }
    ' "$CONFIG_FILE")
    
    if [ "$total" -eq 0 ]; then
        echo -e "${RED}✖ 没有可删除的规则${NC}"
        return
    fi

    show_rules  # 显示带序号的规则列表
    
    read -rp "输入要删除的规则序号 (1-$total): " num
    if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= total )); then
        # 使用更严格的awk处理规则块
        awk -v del_num="$num" '
            BEGIN { 
                RS="\n\\[\\[endpoints\\]\\]\n"; 
                FS="\n"
                ORS=""
                rule_index=0
            }
            {
                # 处理第一个非规则块内容
                if (NR == 1 && $0 !~ /^\[\[endpoints\]\]/) {
                    print $0
                    next
                }
                
                # 跳过注释块
                if ($0 ~ /^#/) { 
                    print $0 RS
                    next 
                }
                
                rule_index++
                if (rule_index != del_num) {
                    # 保留非删除规则的完整块
                    if (rule_index == 1) {
                        print "[[endpoints]]" $0
                    } else {
                        print RS "[[endpoints]]" $0
                    }
                }
            }
        ' "$CONFIG_FILE" > tmp_config && mv tmp_config "$CONFIG_FILE"
        
        systemctl restart realm
        log "删除规则：序号 $num"
        echo -e "${GREEN}✔ 规则已删除！${NC}"
    else
        echo -e "${RED}✖ 无效的输入！${NC}"
    fi
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
# 主界面
# ========================================
main_menu() {
    init_check
    check_update && perform_update "$@"

    while true; do
        clear
        echo -e "${YELLOW}▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂"
        echo -e "      Realm 高级管理脚本 v$CURRENT_VERSION"
        echo -e "▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂﹍▂${NC}"
        echo -e "${BLUE}服务状态：$(service_control status)${NC}"
        echo -e "${YELLOW}-----------------------------------------${NC}"
        echo "1. 安装/更新 Realm"
        echo "2. 添加转发规则"
        echo "3. 查看转发规则"
        echo "4. 删除转发规则"
        echo "5. 服务管理（启动/停止/重启）"
        echo "6. 定时任务管理"
        echo "7. 查看日志"
        echo "8. 完全卸载"
        echo "0. 退出脚本"
        echo -e "${YELLOW}-----------------------------------------${NC}"

        read -rp "请输入选项: " choice
        case $choice in
            1) deploy_realm ;;
            2) add_rule ;;
            3) show_rules ;;
            4) delete_rule ;;
            5) 
                echo -e "\n${BLUE}服务管理：${NC}"
                echo "1. 启动服务"
                echo "2. 停止服务"
                echo "3. 重启服务"
                read -rp "请选择: " sub_choice
                case $sub_choice in
                    1) service_control start ;;
                    2) service_control stop ;;
                    3) service_control restart ;;
                    *) echo -e "${RED}无效选择！${NC}" ;;
                esac
                ;;
            6) manage_cron ;;
            7) 
                echo -e "\n${BLUE}最近日志：${NC}"
                tail -n 10 "$LOG_FILE" 
                ;;
            8) 
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
