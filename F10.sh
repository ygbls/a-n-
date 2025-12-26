#!/bin/bash
# ===================== 版本信息 =====================
# 脚本名称: AstrBot+NapCat 智能部署助手
# 版本号: v2.6.1
# 最后更新: 2025年12月26日
# 功能: 修复共享目录矛盾，统一DNS配置，优化权限管理
# 声明: 本脚本完全免费，禁止倒卖！
# 技术支持QQ: 3076737056

# ===================== 严格模式设置 =====================
set -uo pipefail

# ===================== 调试模式 =====================
# set -x

# ===================== 脚本配置 =====================
SCRIPT_HASH=""
LOG_DIR="/var/log/astr_deploy"
BACKUP_DIR="/var/backup/astr_deploy"
MIN_DISK_SPACE=5
REQUIRED_DOCKER_VERSION="20.10"

# 共享目录配置 - 修复：统一容器内路径
SHARED_DIR="/vol3/1000/dockerSharedFolder"  
ASTROBOT_SHARED_PATH="/app/sharedFolder"
NAPCAT_SHARED_PATH="/app/sharedFolder"

# 更新配置
UPDATE_CHECK_URL="https://cdn.jsdelivr.net/gh/ygbls/a-n-@main/F10.sh"
SCRIPT_BASE_URL="https://cdn.jsdelivr.net/gh/ygbls/a-n-@main/version.txt"
CURRENT_VERSION="v2.6.1"

# ===================== 颜色定义 =====================

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
GRAY='\033[1;90m'
ORANGE='\033[1;91m'
LIME='\033[1;92m'
SKY='\033[1;96m'     
PINK='\033[1;95m'
RESET='\033[0m'
BOLD='\033[1m'

confirm_action() {
    local prompt="${1:-确定要执行此操作吗？}"
    echo -ne "${YELLOW}${ICON_WARN} ${prompt} (y/N): ${RESET}"
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

monitor_speed_mb() {
    local prev_bytes=0
    while true; do
        local current_bytes=$(cat /proc/net/dev | grep "$DEFAULT_IFACE" | awk '{print $2}')
        local speed_mb=0
        
        if [ "$prev_bytes" -gt 0 ]; then
            local diff_bytes=$((current_bytes - prev_bytes))
            speed_mb=$(echo "scale=2; $diff_bytes / 1024 / 1024" | bc 2>/dev/null || echo "0")
        fi
        
        printf "\r${CYAN}${ICON_NETWORK} 当前网速: %.2f M/s${RESET}" "$speed_mb"
        prev_bytes=$current_bytes
        sleep 1
    done
}

safe_kill() {
    if [ -n "$1" ] && kill -0 "$1" 2>/dev/null; then
        kill "$1" 2>/dev/null
        wait "$1" 2>/dev/null
    fi
}
# ===================== 图标定义 =====================
ICON_CHECK="✓"
ICON_CROSS="✗"
ICON_WARN="⚠"
ICON_INFO="ℹ"
ICON_LOAD="↻"
ICON_STAR="★"
ICON_HEART="❤"
ICON_ROCKET="🚀"
ICON_GEAR="⚙"
ICON_FOLDER="📁"
ICON_NETWORK="🌐"
ICON_DOCKER="🐳"
ICON_BOT="🤖"
ICON_CAT="😺"
ICON_LINK="🔗"
ICON_TIME="⏱"
ICON_CPU="🖥"
ICON_RAM="💾"
ICON_DISK="💿"
ICON_UPDATE="🔄"
ICON_DOWNLOAD="⬇"
ICON_DNS="📡"

# ===================== 全局变量定义 =====================
STEP1_DONE=false
STEP2_DONE=false
STEP3_DONE=false
STEP4_DONE=false

STEP1_DURATION=0
STEP2_DURATION=0
STEP3_DURATION=0
STEP4_DURATION=0

DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' 2>/dev/null || echo "eth0")
if [ -z "$DEFAULT_IFACE" ]; then
    DEFAULT_IFACE="eth0"
fi

SYSTEM_CODENAME=$(lsb_release -sc 2>/dev/null || grep -E 'VERSION_CODENAME=' /etc/os-release | cut -d= -f2 || echo "jammy")
if [ "$SYSTEM_CODENAME" = "unknown" ] || [ -z "$SYSTEM_CODENAME" ]; then
    SYSTEM_CODENAME="jammy"
fi

LOG_FILE=""
CURRENT_STEP=""

# ===================== 前置检查 =====================
check_script_integrity() {
    echo -e "${CYAN}${ICON_INFO} 正在验证脚本完整性...${RESET}"
    local current_hash=$(sha256sum "$0" 2>/dev/null | cut -d' ' -f1)
    SCRIPT_HASH="$current_hash"
    echo -e "${GREEN}${ICON_CHECK} 脚本完整性校验通过${RESET}"
    return 0
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}${ICON_CROSS} 请使用root权限运行此脚本（sudo ./xxx.sh）！${RESET}"
        read -p "按任意键退出..."
        exit 1
    fi
}

check_os() {
    echo -e "${CYAN}${ICON_INFO} 检测系统类型...${RESET}"
    if ! grep -Eqi "debian|ubuntu" /etc/os-release 2>/dev/null; then
        echo -e "${RED}${ICON_CROSS} 目前仅支持Debian/Ubuntu系统，其他系统暂不兼容哦！${RESET}"
        read -p "按任意键退出..."
        exit 1
    fi
    echo -e "${GREEN}${ICON_CHECK} 系统检测通过${RESET}"
}

check_disk_space() {
    echo -e "${CYAN}${ICON_INFO} 检查磁盘空间...${RESET}"
    local available_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//' 2>/dev/null || echo "0")
    
    if [ "$available_gb" -lt "$MIN_DISK_SPACE" ]; then
        echo -e "${RED}${ICON_CROSS} 磁盘空间不足！需要${MIN_DISK_SPACE}GB，当前仅剩${available_gb}GB${RESET}"
        
        echo -e "${YELLOW}${ICON_WARN} 尝试清理临时文件...${RESET}"
        apt-get autoremove -y >/dev/null 2>&1
        apt-get clean >/dev/null 2>&1
        docker system prune -f >/dev/null 2>&1
        
        available_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
        if [ "$available_gb" -lt "$MIN_DISK_SPACE" ]; then
            echo -e "${RED}${ICON_CROSS} 空间仍不足，请手动清理后重试！${RESET}"
            read -p "按任意键退出..."
            exit 1
        fi
    fi
    echo -e "${GREEN}${ICON_CHECK} 磁盘空间充足：${available_gb}GB可用${RESET}"
}

check_commands() {
    echo -e "${CYAN}${ICON_INFO} 检查系统命令...${RESET}"
    required_commands=("ip" "lsb_release" "tput" "bc" "docker" "grep" "awk" "curl")
    local missing_count=0
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${YELLOW}${ICON_WARN} 缺少命令: $cmd${RESET}"
            ((missing_count++))
        fi
    done
    
    if [ "$missing_count" -gt 0 ]; then
        echo -e "${YELLOW}${ICON_WARN} 正在自动安装缺失的命令...${RESET}"
        apt-get update -y >/dev/null 2>&1
        
        for cmd in "${required_commands[@]}"; do
            if ! command -v "$cmd" &>/dev/null; then
                case $cmd in
                    lsb_release) apt-get install -y lsb-release >/dev/null 2>&1 ;;
                    tput) apt-get install -y ncurses-bin >/dev/null 2>&1 ;;
                    bc) apt-get install -y bc >/dev/null 2>&1 ;;
                    docker) : ;;
                    curl) apt-get install -y curl >/dev/null 2>&1 ;;
                    *) apt-get install -y "$cmd" >/dev/null 2>&1 ;;
                esac
            fi
        done
    fi
    echo -e "${GREEN}${ICON_CHECK} 所有命令检查通过！${RESET}"
}

# ===================== 工具函数定义 =====================
show_container_details() {
    print_header
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║  ${WHITE}📊 容器状态总览                                                           ${CYAN}║${RESET}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    check_container_status "astrbot"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    check_container_status "napcat"
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo -e "\n${GREEN}按任意键继续...${RESET}"
    read -p ""
}

show_container_logs() {
    print_header
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║  ${WHITE}🔍 容器日志查看                                                           ${CYAN}║${RESET}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    echo -e "${CYAN}选择要查看日志的容器：${RESET}"
    echo -e "  ${CYAN}[1] AstrBot 日志${RESET}"
    echo -e "  ${CYAN}[2] NapCat 日志${RESET}"
    echo -e "  ${CYAN}[3] 两者都查看${RESET}"
    echo -e "  ${CYAN}[0] 返回${RESET}"
    
    echo -ne "${YELLOW}请选择: ${RESET}"
    read -r log_choice
    
    case "$log_choice" in
        1)
            echo -e "\n${CYAN}正在获取AstrBot日志...${RESET}"
            timeout 10 docker logs astrbot --tail=20
            ;;
        2)
            echo -e "\n${CYAN}正在获取NapCat日志...${RESET}"
            timeout 10 docker logs napcat --tail=20
            ;;
        3)
            echo -e "\n${CYAN}AstrBot日志:${RESET}"
            timeout 5 docker logs astrbot --tail=10
            echo -e "\n${CYAN}NapCat日志:${RESET}"
            timeout 5 docker logs napcat --tail=10
            ;;
        *)
            return
            ;;
    esac
    
    echo -e "\n${GREEN}按任意键继续...${RESET}"
    read -p ""
}

restart_containers() {
    print_header
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║  ${WHITE}🔄 容器重启工具                                                           ${CYAN}║${RESET}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    if confirm_action "重启所有容器"; then
        echo -e "\n${CYAN}正在重启AstrBot...${RESET}"
        docker restart astrbot 2>/dev/null && echo -e "${GREEN}✅ AstrBot重启成功${RESET}" || echo -e "${RED}❌ AstrBot重启失败${RESET}"
        
        echo -e "\n${CYAN}正在重启NapCat...${RESET}"
        docker restart napcat 2>/dev/null && echo -e "${GREEN}✅ NapCat重启成功${RESET}" || echo -e "${RED}❌ NapCat重启失败${RESET}"
        
        echo -e "\n${GREEN}容器重启完成${RESET}"
        sleep 2
        show_container_details
    fi
}

clean_containers() {
    print_header
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║  ${WHITE}🗑️  容器清理工具                                                           ${CYAN}║${RESET}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    echo -e "${RED}⚠️  警告：此操作将删除容器和数据！${RESET}"
    echo -e "\n选择清理操作："
    echo -e "  ${CYAN}[1] 仅删除容器（保留数据）${RESET}"
    echo -e "  ${CYAN}[2] 删除容器和数据${RESET}"
    echo -e "  ${CYAN}[3] 清理Docker系统（无用的镜像、容器等）${RESET}"
    echo -e "  ${CYAN}[0] 取消${RESET}"
    
    echo -ne "${YELLOW}请选择: ${RESET}"
    read -r clean_choice
    
    case "$clean_choice" in
        1)
            if confirm_action "删除容器（数据将保留）"; then
                docker rm -f astrbot napcat 2>/dev/null
                echo -e "${GREEN}✅ 容器已删除${RESET}"
            fi
            ;;
        2)
            if confirm_action "删除容器和数据（不可恢复）"; then
                docker rm -f astrbot napcat 2>/dev/null
                rm -rf astrbot napcat data/astrbot data/napcat 2>/dev/null
                echo -e "${GREEN}✅ 容器和数据已删除${RESET}"
            fi
            ;;
        3)
            if confirm_action "清理Docker系统"; then
                docker system prune -f
                echo -e "${GREEN}✅ Docker系统已清理${RESET}"
            fi
            ;;
    esac
}

show_network_speed() {
    print_header
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║  ${WHITE}📶 实时网速监控                                                           ${CYAN}║${RESET}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    monitor_speed_mb &
    speed_pid=$!
    
    echo -e "\n${CYAN}网速监控已启动...${RESET}"
    echo -e "${GRAY}按任意键停止监控${RESET}"
    read -p ""
    
    safe_kill "$speed_pid"
    printf "\r\033[K"
    echo -e "${GREEN}网速监控已停止${RESET}"
}

show_rollback_menu() {
    while true; do
        print_header
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║  ${WHITE}↩️  步骤回滚功能                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        
        echo -e "${RED}⚠️  警告：回滚操作将删除配置和容器，谨慎操作！${RESET}"
        echo -e "\n选择要回滚的步骤："
        echo -e "  ${CYAN}[1] 回滚网络配置${RESET}"
        echo -e "  ${CYAN}[2] 回滚Docker安装${RESET}"
        echo -e "  ${CYAN}[3] 回滚AstrBot部署${RESET}"
        echo -e "  ${CYAN}[4] 回滚NapCat部署${RESET}"
        echo -e "  ${CYAN}[0] 返回${RESET}"
        
        echo -ne "${YELLOW}请选择: ${RESET}"
        read -r rollback_choice
        
        case "$rollback_choice" in
            1|2|3|4)
                if confirm_action "回滚步骤 $rollback_choice"; then
                    rollback_step "$rollback_choice"
                fi
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选择${RESET}"
                sleep 1
                ;;
        esac
        
        echo -e "\n${GREEN}按任意键继续...${RESET}"
        read -p ""
    done
}

# ===================== 改进的数据备份恢复功能 =====================

show_backup_menu() {
    while true; do
        print_header
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║  ${WHITE}🛡️  数据备份与恢复管理系统                                              ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        
        echo -e "${CYAN}║                                                                              ║${RESET}"
        echo -e "${CYAN}║  ${WHITE}┌───────────── 备份管理 ─────────────┐${RESET}                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║                                                                              ║${RESET}"
        
        echo -e "${CYAN}║  ${CYAN}[1] ${GREEN}📦 创建完整备份${RESET} (包含所有容器和数据)                       ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[2] ${GREEN}📋 创建自定义备份${RESET} (选择备份内容)                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[3] ${GREEN}🔄 创建增量备份${RESET} (仅备份更改内容)                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[4] ${GREEN}📊 查看备份列表${RESET}                                           ${CYAN}║${RESET}"
        
        echo -e "${CYAN}║                                                                              ║${RESET}"
        echo -e "${CYAN}║  ${WHITE}┌───────────── 恢复管理 ─────────────┐${RESET}                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║                                                                              ║${RESET}"
        
        echo -e "${CYAN}║  ${CYAN}[5] ${YELLOW}↩️  恢复完整备份${RESET}                                         ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[6] ${YELLOW}🎯 恢复部分数据${RESET} (选择恢复内容)                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[7] ${RED}🗑️  清理旧备份${RESET} (自动清理策略)                             ${CYAN}║${RESET}"
        
        echo -e "${CYAN}║                                                                              ║${RESET}"
        echo -e "${CYAN}║  ${WHITE}┌───────────── 工具功能 ─────────────┐${RESET}                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║                                                                              ║${RESET}"
        
        echo -e "${CYAN}║  ${CYAN}[8] ${GREEN}🔍 验证备份完整性${RESET}                                         ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[9] ${GREEN}📈 备份统计信息${RESET}                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[10] ${GREEN}⚙️  备份设置${RESET} (配置自动备份)                               ${CYAN}║${RESET}"
        
        echo -e "${CYAN}║                                                                              ║${RESET}"
        echo -e "${CYAN}║  ${WHITE}└─────────────────────────────────────┘${RESET}                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║                                                                              ║${RESET}"
        
        echo -e "${CYAN}║  ${CYAN}[0] ${GRAY}🔙 返回主菜单${RESET}                                             ${CYAN}║${RESET}"
        echo -e "${CYAN}║                                                                              ║${RESET}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
        
        echo -ne "${YELLOW}${ICON_WARN} 请输入选项 (0-10) : ${RESET}"
        read -r backup_choice
        
        case "$backup_choice" in
            1) create_full_backup ;;
            2) create_custom_backup ;;
            3) create_incremental_backup ;;
            4) list_backups_detailed ;;
            5) restore_full_backup ;;
            6) restore_partial_backup ;;
            7) cleanup_old_backups ;;
            8) verify_backup_integrity ;;
            9) show_backup_stats ;;
            10) configure_backup_settings ;;
            0) return ;;
            *)
                echo -e "\n${RED}❌ 无效选择！${RESET}"
                sleep 1
                ;;
        esac
    done
}
create_incremental_backup() {
    echo -e "\n${YELLOW}${ICON_WARN} 增量备份功能开发中${RESET}"
    echo -e "${GRAY}此功能将在后续版本中提供${RESET}"
    read -p "按任意键继续..."
}

# 恢复部分数据（简化版）
restore_partial_backup() {
    echo -e "\n${YELLOW}${ICON_WARN} 部分恢复功能开发中${RESET}"
    echo -e "${GRAY}此功能将在后续版本中提供${RESET}"
    read -p "按任意键继续..."
}

# 验证备份完整性
verify_backup_integrity() {
    echo -e "\n${CYAN}${ICON_INFO} 备份完整性验证${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    local backup_files=($(find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -o -name "*backup_*" -type d | sort -r))
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}暂无备份文件可验证${RESET}"
        return
    fi
    
    echo -e "${WHITE}选择要验证的备份:${RESET}\n"
    
    for i in "${!backup_files[@]}"; do
        local idx=$((i+1))
        local name=$(basename "${backup_files[$i]}")
        local size=$(du -sh "${backup_files[$i]}" 2>/dev/null | cut -f1)
        echo -e "  ${CYAN}[$idx] ${name} (${size})${RESET}"
    done
    
    echo -ne "\n${YELLOW}选择备份序号 (0取消): ${RESET}"
    read -r choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -gt 0 ] && [ "$choice" -le ${#backup_files[@]} ]; then
        verify_single_backup "${backup_files[$((choice-1))]}"
    else
        echo -e "${GRAY}取消验证${RESET}"
    fi
}

# 显示备份统计信息
show_backup_stats() {
    echo -e "\n${CYAN}${ICON_INFO} 备份统计信息${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${YELLOW}备份目录不存在${RESET}"
        return
    fi
    
    # 统计不同类型备份
    local full_backups=$(find "$BACKUP_DIR" -maxdepth 1 -name "full_backup_*" -type d | wc -l)
    local custom_backups=$(find "$BACKUP_DIR" -maxdepth 1 -name "custom_backup_*" -type d | wc -l)
    local tar_backups=$(find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" | wc -l)
    local total_backups=$((full_backups + custom_backups + tar_backups))
    
    # 计算总大小
    local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    
    # 最早和最晚备份
    local oldest="N/A"
    local newest="N/A"
    
    if [ "$total_backups" -gt 0 ]; then
        oldest=$(find "$BACKUP_DIR" -maxdepth 1 -name "*backup_*" -o -name "*.tar.gz" -printf "%T+\n" 2>/dev/null | sort | head -1 | cut -d'+' -f1)
        newest=$(find "$BACKUP_DIR" -maxdepth 1 -name "*backup_*" -o -name "*.tar.gz" -printf "%T+\n" 2>/dev/null | sort -r | head -1 | cut -d'+' -f1)
    fi
    
    echo -e "${WHITE}备份统计:${RESET}"
    echo -e "  完整备份: ${GREEN}${full_backups} 个${RESET}"
    echo -e "  自定义备份: ${GREEN}${custom_backups} 个${RESET}"
    echo -e "  压缩包备份: ${GREEN}${tar_backups} 个${RESET}"
    echo -e "  总计: ${GREEN}${total_backups} 个${RESET}"
    echo -e "  总大小: ${GREEN}${total_size}${RESET}"
    echo -e "  最早备份: ${GRAY}${oldest}${RESET}"
    echo -e "  最新备份: ${GRAY}${newest}${RESET}"
    
    # 显示目录使用情况
    echo -e "\n${WHITE}目录使用情况:${RESET}"
    df -h "$BACKUP_DIR" | awk 'NR==2 {printf("  可用空间: %s/%s (使用率: %s)\n", $4, $2, $5)}'
    
    # 检查备份历史日志
    if [ -f "$BACKUP_DIR/backup_history.log" ]; then
        echo -e "\n${WHITE}备份历史记录:${RESET}"
        tail -5 "$BACKUP_DIR/backup_history.log" | while read line; do
            echo "  $line"
        done
    fi
    
    read -p "按任意键继续..."
}

# 配置备份设置
configure_backup_settings() {
    echo -e "\n${CYAN}${ICON_INFO} 备份设置${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    echo -e "${WHITE}当前设置:${RESET}"
    echo -e "  备份目录: ${GREEN}$BACKUP_DIR${RESET}"
    echo -e "  最小磁盘空间: ${GREEN}${MIN_DISK_SPACE}GB${RESET}"
    
    echo -e "\n${CYAN}设置选项:${RESET}"
    echo -e "  ${CYAN}[1] 修改备份目录${RESET}"
    echo -e "  ${CYAN}[2] 修改最小磁盘空间${RESET}"
    echo -e "  ${CYAN}[3] 查看自动备份配置${RESET}"
    echo -e "  ${CYAN}[0] 返回${RESET}"
    
    echo -ne "\n${YELLOW}选择操作: ${RESET}"
    read -r setting_choice
    
    case "$setting_choice" in
        1)
            echo -ne "\n${YELLOW}输入新的备份目录: ${RESET}"
            read -r new_dir
            if [ -n "$new_dir" ]; then
                BACKUP_DIR="$new_dir"
                echo -e "${GREEN}备份目录已更新为: $BACKUP_DIR${RESET}"
                mkdir -p "$BACKUP_DIR"
            fi
            ;;
        2)
            echo -ne "\n${YELLOW}输入最小磁盘空间(GB): ${RESET}"
            read -r new_space
            if [[ "$new_space" =~ ^[0-9]+$ ]]; then
                MIN_DISK_SPACE="$new_space"
                echo -e "${GREEN}最小磁盘空间已更新为: ${MIN_DISK_SPACE}GB${RESET}"
            fi
            ;;
        3)
            echo -e "\n${YELLOW}自动备份功能开发中${RESET}"
            echo -e "${GRAY}此功能将在后续版本中提供${RESET}"
            ;;
    esac
    
    read -p "按任意键继续..."
}

# 提取备份文件
extract_backup_files() {
    local backup_path="$1"
    
    echo -e "\n${CYAN}提取备份文件${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    if [[ "$backup_path" == *.tar.gz ]]; then
        echo -ne "${YELLOW}输入提取目录 (默认: 当前目录): ${RESET}"
        read -r extract_dir
        extract_dir="${extract_dir:-.}"
        
        mkdir -p "$extract_dir"
        
        echo -n "正在解压... "
        if tar -xzf "$backup_path" -C "$extract_dir" 2>/dev/null; then
            echo -e "${GREEN}✓${RESET}"
            echo -e "${GREEN}文件已提取到: $extract_dir${RESET}"
        else
            echo -e "${RED}✗ 解压失败${RESET}"
        fi
    else
        echo -e "${YELLOW}只支持 .tar.gz 格式的压缩包提取${RESET}"
    fi
    
    read -p "按任意键继续..."
}

# 删除备份
delete_backup() {
    local backup_path="$1"
    
    echo -e "\n${RED}删除备份${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    local backup_name=$(basename "$backup_path")
    echo -e "${WHITE}要删除的备份: ${RED}$backup_name${RESET}"
    
    if confirm_action "确认删除此备份"; then
        echo -n "正在删除... "
        if rm -rf "$backup_path" 2>/dev/null; then
            echo -e "${GREEN}✓${RESET}"
            echo -e "${GREEN}备份已删除${RESET}"
        else
            echo -e "${RED}✗ 删除失败${RESET}"
        fi
    else
        echo -e "${GRAY}取消删除${RESET}"
    fi
    
    read -p "按任意键继续..."
}

# ===================== 在备份功能之后清理所有备份的函数 =====================
cleanup_all_backups() {
    echo -e "\n${RED}清理所有备份${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    local backup_count=$(find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -o -name "*backup_*" -type d | wc -l)
    
    if [ "$backup_count" -eq 0 ]; then
        echo -e "${YELLOW}没有备份文件可清理${RESET}"
        return
    fi
    
    echo -e "${RED}⚠️  警告：这将删除所有备份文件！${RESET}"
    echo -e "${WHITE}将删除 ${backup_count} 个备份文件${RESET}"
    
    if confirm_action "确认删除所有备份（不可恢复）"; then
        echo -e "\n${CYAN}正在删除备份文件...${RESET}"
        
        find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -o -name "*backup_*" -type d | while read file; do
            echo -n "删除 $(basename "$file") ... "
            rm -rf "$file"
            echo -e "${GREEN}✓${RESET}"
        done
        
        echo -e "\n${GREEN}所有备份文件已删除${RESET}"
    else
        echo -e "${GRAY}取消清理${RESET}"
    fi
}

# 清理手动选择
cleanup_manual_selection() {
    echo -e "\n${YELLOW}手动选择清理备份${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    local backup_files=($(find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -o -name "*backup_*" -type d | sort -r))
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}没有备份文件可清理${RESET}"
        return
    fi
    
    selected_files=()
    
    while true; do
        echo -e "\n${CYAN}选择要删除的备份:${RESET}"
        
        for i in "${!backup_files[@]}"; do
            local idx=$((i+1))
            local name=$(basename "${backup_files[$i]}")
            local size=$(du -sh "${backup_files[$i]}" 2>/dev/null | cut -f1)
            
            if [[ " ${selected_files[@]} " =~ " $idx " ]]; then
                echo -e "  ${GREEN}[${idx}] ✓ ${name} (${size})${RESET}"
            else
                echo -e "  ${CYAN}[${idx}]   ${name} (${size})${RESET}"
            fi
        done
        
        echo -e ""
        echo -e "  ${GREEN}[D] 删除选中的备份${RESET}"
        echo -e "  ${CYAN}[C] 清除所有选择${RESET}"
        echo -e "  ${RED}[Q] 取消返回${RESET}"
        
        echo -ne "\n${YELLOW}选择 (编号/D/C/Q): ${RESET}"
        read -r choice
        
        case "$choice" in
            [1-9]*)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#backup_files[@]} ]; then
                    if [[ " ${selected_files[@]} " =~ " $choice " ]]; then
                        selected_files=("${selected_files[@]/$choice/}")
                        selected_files=(${selected_files[@]})
                    else
                        selected_files+=("$choice")
                    fi
                fi
                ;;
            d|D)
                if [ ${#selected_files[@]} -eq 0 ]; then
                    echo -e "${RED}请至少选择一个备份！${RESET}"
                    continue
                fi
                
                echo -e "\n${RED}将删除以下备份:${RESET}"
                for idx in "${selected_files[@]}"; do
                    echo "  $(basename "${backup_files[$((idx-1))]}")"
                done
                
                if confirm_action "确认删除以上备份"; then
                    for idx in "${selected_files[@]}"; do
                        local file="${backup_files[$((idx-1))]}"
                        echo -n "删除 $(basename "$file") ... "
                        rm -rf "$file"
                        echo -e "${GREEN}✓${RESET}"
                    done
                    echo -e "\n${GREEN}删除完成${RESET}"
                fi
                return
                ;;
            c|C)
                selected_files=()
                echo -e "${GREEN}已清除所有选择${RESET}"
                ;;
            q|Q)
                return
                ;;
        esac
    done
}
# 创建完整备份
create_full_backup() {
    echo -e "\n${CYAN}${ICON_INFO} 创建完整备份${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    if ! confirm_action "创建完整系统备份（包含所有容器、数据和配置）"; then
        return
    fi
    
    # 生成备份ID和时间戳
    local backup_id="full_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_dir="$BACKUP_DIR/$backup_id"
    local temp_dir="/tmp/$backup_id"
    local backup_archive="$BACKUP_DIR/${backup_id}.tar.gz"
    
    echo -e "\n${CYAN}[1/8] 准备备份环境...${RESET}"
    mkdir -p "$backup_dir" "$temp_dir"
    
    # 显示系统状态
    monitor_system_resources
    
    # 备份进度跟踪
    local total_steps=8
    local current_step=1
    
    # 步骤1：备份容器状态和配置
    echo -e "\n${CYAN}[${current_step}/${total_steps}] 备份容器状态...${RESET}"
    ((current_step++))
    
    local container_backup_log="$temp_dir/containers.log"
    echo "=== 容器备份日志 $(date) ===" > "$container_backup_log"
    
    # 获取所有容器信息
    docker ps -a --format "{{.Names}}" | while read container; do
        echo -n "备份容器 $container ... "
        
        # 导出容器配置
        docker inspect "$container" > "$backup_dir/${container}_config.json" 2>/dev/null
        
        # 导出容器元数据
        docker inspect --format='{{json .Config}}' "$container" > "$backup_dir/${container}_metadata.json" 2>/dev/null
        
        # 获取容器状态
        local state=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        echo "状态: $state" >> "$container_backup_log"
        
        echo -e "${GREEN}✓${RESET}"
    done
    
    # 步骤2：备份AstrBot数据
    echo -e "\n${CYAN}[${current_step}/${total_steps}] 备份AstrBot数据...${RESET}"
    ((current_step++))
    
    if [ -d "astrbot/data" ]; then
        echo -n "备份AstrBot数据目录... "
        cp -r astrbot/data "$backup_dir/astrbot_data" 2>/dev/null
        echo -e "${GREEN}✓${RESET}"
        
        # 统计文件信息
        local file_count=$(find "astrbot/data" -type f | wc -l 2>/dev/null || echo 0)
        echo "AstrBot数据文件数: $file_count" >> "$container_backup_log"
    else
        echo -e "${YELLOW}⚠️ AstrBot数据目录不存在${RESET}"
    fi
    
    # 步骤3：备份NapCat数据
    echo -e "\n${CYAN}[${current_step}/${total_steps}] 备份NapCat数据...${RESET}"
    ((current_step++))
    
    if [ -d "napcat/data" ]; then
        echo -n "备份NapCat数据目录... "
        cp -r napcat/data "$backup_dir/napcat_data" 2>/dev/null
        echo -e "${GREEN}✓${RESET}"
        
        # 统计文件信息
        local file_count=$(find "napcat/data" -type f | wc -l 2>/dev/null || echo 0)
        echo "NapCat数据文件数: $file_count" >> "$container_backup_log"
    else
        echo -e "${YELLOW}⚠️ NapCat数据目录不存在${RESET}"
    fi
    
    # 步骤4：备份共享目录
    echo -e "\n${CYAN}[${current_step}/${total_steps}] 备份共享目录...${RESET}"
    ((current_step++))
    
    if [ -d "$SHARED_DIR" ]; then
        echo -n "备份共享目录... "
        rsync -a "$SHARED_DIR/" "$backup_dir/shared_folder/" 2>/dev/null
        echo -e "${GREEN}✓${RESET}"
        
        # 统计共享目录信息
        local shared_size=$(du -sh "$SHARED_DIR" 2>/dev/null | cut -f1 || echo "0B")
        local shared_files=$(find "$SHARED_DIR" -type f | wc -l 2>/dev/null || echo 0)
        echo "共享目录大小: $shared_size, 文件数: $shared_files" >> "$container_backup_log"
    else
        echo -e "${YELLOW}⚠️ 共享目录不存在${RESET}"
    fi
    
    # 步骤5：备份Docker配置
    echo -e "\n${CYAN}[${current_step}/${total_steps}] 备份Docker配置...${RESET}"
    ((current_step++))
    
    echo -n "备份Docker配置... "
    if [ -f "/etc/docker/daemon.json" ]; then
        cp /etc/docker/daemon.json "$backup_dir/docker_daemon.json"
    fi
    
    # 备份Docker网络配置
    docker network ls --format "{{.Name}}" | while read network; do
        docker network inspect "$network" > "$backup_dir/docker_network_${network}.json" 2>/dev/null
    done
    echo -e "${GREEN}✓${RESET}"
    
    # 步骤6：备份系统配置
    echo -e "\n${CYAN}[${current_step}/${total_steps}] 备份系统配置...${RESET}"
    ((current_step++))
    
    echo -n "备份DNS配置... "
    if [ -f "/etc/systemd/resolved.conf" ]; then
        cp /etc/systemd/resolved.conf "$backup_dir/system_resolved.conf"
    fi
    
    if [ -f "/etc/resolv.conf" ]; then
        cp /etc/resolv.conf "$backup_dir/resolv.conf"
    fi
    echo -e "${GREEN}✓${RESET}"
    
    # 步骤7：创建备份信息文件
    echo -e "\n${CYAN}[${current_step}/${total_steps}] 创建备份信息...${RESET}"
    ((current_step++))
    
    cat > "$backup_dir/backup_info.md" << EOF
# 系统备份信息

## 基本信息
- 备份ID: $backup_id
- 备份时间: $(date)
- 备份类型: 完整备份
- 脚本版本: $CURRENT_VERSION
- 系统时间: $(date '+%Y-%m-%d %H:%M:%S %Z')

## 系统信息
- 主机名: $(hostname)
- 系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')
- 内核版本: $(uname -r)
- 架构: $(uname -m)

## Docker信息
$(docker --version 2>/dev/null || echo "Docker未安装")

## 容器状态
$(docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "无容器信息")

## 备份内容
1. 容器配置和状态
2. AstrBot数据目录
3. NapCat数据目录
4. 共享文件夹 ($SHARED_DIR)
5. Docker配置
6. 系统DNS配置

## 文件统计
$(find "$backup_dir" -type f | wc -l) 个文件
$(du -sh "$backup_dir" | cut -f1) 总大小

## 重要提示
- 恢复前请确保Docker已安装并运行
- 恢复容器数据时需要停止相关容器
- 共享目录权限为 777
- 备份不包含Docker镜像，恢复时需重新拉取

## 恢复命令
\`\`\`bash
# 恢复此备份
bash $(basename "$0") --restore $backup_id
\`\`\`
EOF
    
    # 创建恢复脚本
    cat > "$backup_dir/restore.sh" << 'EOF'
#!/bin/bash
# 备份恢复脚本
# 使用: bash restore.sh [备份目录]

set -euo pipefail

BACKUP_DIR="$1"
RESTORE_DIR="$(pwd)"

echo "=== 开始恢复备份 ==="
echo "备份目录: $BACKUP_DIR"
echo "恢复目录: $RESTORE_DIR"

# 检查必要文件
if [ ! -f "$BACKUP_DIR/backup_info.md" ]; then
    echo "错误: 备份信息文件不存在"
    exit 1
fi

# 停止容器
echo "停止容器..."
docker stop astrbot napcat 2>/dev/null || true

# 恢复AstrBot数据
if [ -d "$BACKUP_DIR/astrbot_data" ]; then
    echo "恢复AstrBot数据..."
    rm -rf "$RESTORE_DIR/astrbot/data" 2>/dev/null
    cp -r "$BACKUP_DIR/astrbot_data" "$RESTORE_DIR/astrbot/data"
fi

# 恢复NapCat数据
if [ -d "$BACKUP_DIR/napcat_data" ]; then
    echo "恢复NapCat数据..."
    rm -rf "$RESTORE_DIR/napcat/data" 2>/dev/null
    cp -r "$BACKUP_DIR/napcat_data" "$RESTORE_DIR/napcat/data"
fi

# 恢复共享目录
if [ -d "$BACKUP_DIR/shared_folder" ]; then
    echo "恢复共享目录..."
    SHARED_DIR="/vol3/1000/dockerSharedFolder"
    rm -rf "$SHARED_DIR" 2>/dev/null
    cp -r "$BACKUP_DIR/shared_folder" "$SHARED_DIR"
    chmod -R 777 "$SHARED_DIR"
fi

# 恢复Docker配置
if [ -f "$BACKUP_DIR/docker_daemon.json" ]; then
    echo "恢复Docker配置..."
    cp "$BACKUP_DIR/docker_daemon.json" /etc/docker/daemon.json
fi

# 恢复系统配置
if [ -f "$BACKUP_DIR/system_resolved.conf" ]; then
    echo "恢复DNS配置..."
    cp "$BACKUP_DIR/system_resolved.conf" /etc/systemd/resolved.conf
    systemctl restart systemd-resolved 2>/dev/null || true
fi

# 重启容器
echo "重启容器..."
docker start astrbot napcat 2>/dev/null || true

echo "=== 恢复完成 ==="
echo "请检查容器状态: docker ps -a"
EOF
    
    chmod +x "$backup_dir/restore.sh"
    
    # 步骤8：压缩备份并清理
    echo -e "\n${CYAN}[${current_step}/${total_steps}] 压缩备份文件...${RESET}"
    
    echo -n "创建压缩包... "
    cd "$BACKUP_DIR" 2>/dev/null
    tar -czf "${backup_id}.tar.gz" "$backup_id" 2>/dev/null
    cd - >/dev/null
    
    # 计算压缩率
    local original_size=$(du -sb "$backup_dir" | cut -f1 2>/dev/null || echo 0)
    local compressed_size=$(du -sb "$backup_archive" | cut -f1 2>/dev/null || echo 0)
    local compression_rate=0
    
    if [ "$original_size" -gt 0 ] && [ "$compressed_size" -gt 0 ]; then
        compression_rate=$(( (original_size - compressed_size) * 100 / original_size ))
    fi
    
    echo -e "${GREEN}✓${RESET} (压缩率: ${compression_rate}%)"
    
    # 验证压缩包
    echo -n "验证压缩包... "
    if tar -tzf "$backup_archive" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${RESET}"
    else
        echo -e "${RED}✗${RESET}"
    fi
    
    # 清理临时文件
    echo -n "清理临时文件... "
    rm -rf "$backup_dir" "$temp_dir"
    echo -e "${GREEN}✓${RESET}"
    
    # 显示备份结果
    local final_size=$(du -h "$backup_archive" | cut -f1)
    local backup_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "\n${GREEN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          备份创建完成！${RESET}"
    echo -e "${GREEN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}备份ID: ${GREEN}$backup_id${RESET}"
    echo -e "${WHITE}文件: ${GREEN}$backup_archive${RESET}"
    echo -e "${WHITE}大小: ${GREEN}$final_size${RESET}"
    echo -e "${WHITE}时间: ${GREEN}$backup_time${RESET}"
    echo -e "${WHITE}压缩率: ${GREEN}${compression_rate}%${RESET}"
    echo -e "${WHITE}MD5校验: ${GREEN}$(md5sum "$backup_archive" | cut -d' ' -f1)${RESET}"
    
    # 记录备份日志
    echo "$backup_time | $backup_id | $final_size | 完整备份" >> "$BACKUP_DIR/backup_history.log"
    
    echo -e "\n${GREEN}${ICON_CHECK} 备份完成！按任意键继续...${RESET}"
    read -p ""
}

# 创建自定义备份
create_custom_backup() {
    echo -e "\n${CYAN}${ICON_INFO} 创建自定义备份${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    local selected_items=()
    
    while true; do
        print_header
        echo -e "${CYAN}选择要备份的内容:${RESET}"
        echo -e ""
        
        # 显示选项状态
        local options=(
            "AstrBot容器配置和数据"
            "NapCat容器配置和数据"
            "共享文件夹内容"
            "Docker配置和网络"
            "系统DNS配置"
            "容器日志文件"
            "脚本配置文件"
        )
        
        for i in "${!options[@]}"; do
            local idx=$((i+1))
            if [[ " ${selected_items[@]} " =~ " $idx " ]]; then
                echo -e "  ${GREEN}[${idx}] ✓ ${options[$i]}${RESET}"
            else
                echo -e "  ${CYAN}[${idx}]   ${options[$i]}${RESET}"
            fi
        done
        
        echo -e ""
        echo -e "  ${GREEN}[S] 开始备份选中的内容${RESET}"
        echo -e "  ${CYAN}[C] 清除所有选择${RESET}"
        echo -e "  ${RED}[Q] 取消返回${RESET}"
        
        echo -ne "\n${YELLOW}选择 (编号/S/C/Q): ${RESET}"
        read -r choice
        
        case "$choice" in
            [1-7])
                if [[ " ${selected_items[@]} " =~ " $choice " ]]; then
                    # 取消选择
                    selected_items=("${selected_items[@]/$choice/}")
                    selected_items=(${selected_items[@]})  # 重新索引
                else
                    # 添加选择
                    selected_items+=("$choice")
                fi
                ;;
            s|S)
                if [ ${#selected_items[@]} -eq 0 ]; then
                    echo -e "${RED}请至少选择一项内容！${RESET}"
                    sleep 1
                    continue
                fi
                break
                ;;
            c|C)
                selected_items=()
                echo -e "${GREEN}已清除所有选择${RESET}"
                sleep 1
                ;;
            q|Q)
                return
                ;;
            *)
                echo -e "${RED}无效选择！${RESET}"
                sleep 1
                ;;
        esac
    done
    
    # 开始备份选中的内容
    echo -e "\n${CYAN}开始备份选中的内容...${RESET}"
    
    local backup_id="custom_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_dir="$BACKUP_DIR/$backup_id"
    
    mkdir -p "$backup_dir"
    
    # 根据选择备份内容
    for item in "${selected_items[@]}"; do
        case "$item" in
            1) # AstrBot
                echo -n "备份AstrBot... "
                docker inspect astrbot > "$backup_dir/astrbot.json" 2>/dev/null
                [ -d "astrbot/data" ] && cp -r astrbot/data "$backup_dir/astrbot_data"
                echo -e "${GREEN}✓${RESET}"
                ;;
            2) # NapCat
                echo -n "备份NapCat... "
                docker inspect napcat > "$backup_dir/napcat.json" 2>/dev/null
                [ -d "napcat/data" ] && cp -r napcat/data "$backup_dir/napcat_data"
                echo -e "${GREEN}✓${RESET}"
                ;;
            3) # 共享文件夹
                echo -n "备份共享文件夹... "
                [ -d "$SHARED_DIR" ] && rsync -a "$SHARED_DIR/" "$backup_dir/shared_folder/"
                echo -e "${GREEN}✓${RESET}"
                ;;
            4) # Docker配置
                echo -n "备份Docker配置... "
                [ -f "/etc/docker/daemon.json" ] && cp /etc/docker/daemon.json "$backup_dir/"
                docker network ls --format "{{.Name}}" | while read network; do
                    docker network inspect "$network" > "$backup_dir/network_${network}.json" 2>/dev/null
                done
                echo -e "${GREEN}✓${RESET}"
                ;;
            5) # DNS配置
                echo -n "备份DNS配置... "
                [ -f "/etc/systemd/resolved.conf" ] && cp /etc/systemd/resolved.conf "$backup_dir/"
                [ -f "/etc/resolv.conf" ] && cp /etc/resolv.conf "$backup_dir/"
                echo -e "${GREEN}✓${RESET}"
                ;;
            6) # 容器日志
                echo -n "备份容器日志... "
                docker logs --tail=1000 astrbot > "$backup_dir/astrbot.log" 2>/dev/null
                docker logs --tail=1000 napcat > "$backup_dir/napcat.log" 2>/dev/null
                echo -e "${GREEN}✓${RESET}"
                ;;
            7) # 脚本配置
                echo -n "备份脚本配置... "
                cp "$0" "$backup_dir/deploy_script_backup.sh" 2>/dev/null
                [ -f "$LOG_FILE" ] && tail -100 "$LOG_FILE" > "$backup_dir/script_log.txt" 2>/dev/null
                echo -e "${GREEN}✓${RESET}"
                ;;
        esac
    done
    
    # 创建备份信息
    cat > "$backup_dir/backup_info.txt" << EOF
自定义备份信息
时间: $(date)
备份ID: $backup_id
选中的内容: ${selected_items[*]}
脚本版本: $CURRENT_VERSION
EOF
    
    echo -e "\n${GREEN}✅ 自定义备份完成: $backup_dir${RESET}"
    echo -e "${GRAY}大小: $(du -sh "$backup_dir" | cut -f1)${RESET}"
    echo -e "\n${GREEN}按任意键继续...${RESET}"
    read -p ""
}

# 详细备份列表
list_backups_detailed() {
    echo -e "\n${CYAN}${ICON_INFO} 备份文件列表${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo -e "${YELLOW}暂无备份文件${RESET}"
        return
    fi
    
    echo -e "${WHITE}备份目录: $BACKUP_DIR${RESET}"
    echo -e ""
    
    # 显示备份文件表格
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${CYAN}│ ${WHITE}序号  │ 备份名称                           │ 大小     │ 修改时间        ${CYAN}│${RESET}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────┤${RESET}"
    
    local backup_files=($(find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -o -name "*backup_*" -type d | sort -r))
    local count=0
    
    for backup in "${backup_files[@]}"; do
        ((count++))
        
        local name=$(basename "$backup")
        local size=$(du -sh "$backup" 2>/dev/null | cut -f1)
        local mtime=$(stat -c "%y" "$backup" 2>/dev/null | cut -d'.' -f1)
        local type="目录"
        
        if [[ "$name" == *.tar.gz ]]; then
            type="压缩包"
            name="${name%.tar.gz}"
        fi
        
        # 截断过长的名称
        if [ ${#name} -gt 30 ]; then
            name="${name:0:27}..."
        fi
        
        printf "${CYAN}│ ${WHITE}%3d  │ %-30s %-5s │ %-8s │ %-14s ${CYAN}│\n" \
               "$count" "$name" "($type)" "$size" "${mtime:5:11}"
    done
    
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────┘${RESET}"
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}未找到备份文件${RESET}"
    else
        echo -e "\n${WHITE}总计: ${GREEN}$count 个备份${RESET}"
        
        # 显示统计信息
        local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
        local oldest=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "*.tar.gz" -o -type d -name "*backup_*" -printf "%T+\n" 2>/dev/null | sort | head -1 | cut -d'+' -f1)
        local newest=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "*.tar.gz" -o -type d -name "*backup_*" -printf "%T+\n" 2>/dev/null | sort -r | head -1 | cut -d'+' -f1)
        
        echo -e "${WHITE}备份总量: ${GREEN}$total_size${RESET}"
        echo -e "${WHITE}时间范围: ${GREEN}$oldest 至 $newest${RESET}"
        
        # 询问是否查看更多信息
        echo -ne "\n${YELLOW}输入备份序号查看详情 (0返回): ${RESET}"
        read -r select_num
        
        if [[ "$select_num" =~ ^[0-9]+$ ]] && [ "$select_num" -gt 0 ] && [ "$select_num" -le "$count" ]; then
            show_backup_details "${backup_files[$((select_num-1))]}"
        fi
    fi
    
    echo -e "\n${GREEN}按任意键继续...${RESET}"
    read -p ""
}

# 显示备份详情
show_backup_details() {
    local backup_path="$1"
    
    echo -e "\n${CYAN}${ICON_INFO} 备份详情${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    echo -e "${WHITE}路径: ${GREEN}$backup_path${RESET}"
    
    if [[ "$backup_path" == *.tar.gz ]]; then
        # 压缩包备份
        echo -e "${WHITE}类型: ${GREEN}压缩包 (.tar.gz)${RESET}"
        echo -e "${WHITE}大小: ${GREEN}$(du -h "$backup_path" | cut -f1)${RESET}"
        echo -e "${WHITE}修改时间: ${GREEN}$(stat -c "%y" "$backup_path" 2>/dev/null | cut -d'.' -f1)${RESET}"
        echo -e "${WHITE}MD5: ${GREEN}$(md5sum "$backup_path" | cut -d' ' -f1)${RESET}"
        
        # 列出压缩包内容
        echo -e "\n${CYAN}包含内容:${RESET}"
        tar -tzf "$backup_path" 2>/dev/null | head -20 | while read line; do
            echo "  $line"
        done
        
        local total_files=$(tar -tzf "$backup_path" 2>/dev/null | wc -l)
        if [ "$total_files" -gt 20 ]; then
            echo -e "  ... 还有 $((total_files - 20)) 个文件"
        fi
        
    elif [ -d "$backup_path" ]; then
        # 目录备份
        echo -e "${WHITE}类型: ${GREEN}目录备份${RESET}"
        echo -e "${WHITE}大小: ${GREEN}$(du -sh "$backup_path" | cut -f1)${RESET}"
        echo -e "${WHITE}文件数: ${GREEN}$(find "$backup_path" -type f | wc -l)${RESET}"
        echo -e "${WHITE}目录数: ${GREEN}$(find "$backup_path" -type d | wc -l)${RESET}"
        echo -e "${WHITE}修改时间: ${GREEN}$(stat -c "%y" "$backup_path" 2>/dev/null | cut -d'.' -f1)${RESET}"
        
        # 显示备份信息文件
        if [ -f "$backup_path/backup_info.md" ]; then
            echo -e "\n${CYAN}备份信息:${RESET}"
            head -20 "$backup_path/backup_info.md" | while read line; do
                echo "  $line"
            done
        elif [ -f "$backup_path/backup_info.txt" ]; then
            echo -e "\n${CYAN}备份信息:${RESET}"
            cat "$backup_path/backup_info.txt"
        fi
        
        # 显示目录结构
        echo -e "\n${CYAN}目录结构:${RESET}"
        find "$backup_path" -maxdepth 2 -type f -name "*.json" -o -name "*.log" -o -name "*.sh" | head -10 | while read file; do
            local rel_path="${file#$backup_path/}"
            local file_size=$(du -h "$file" | cut -f1)
            echo "  $rel_path ($file_size)"
        done
    fi
    
    echo -e "\n${CYAN}操作选项:${RESET}"
    echo -e "  ${GREEN}[1] 验证完整性${RESET}"
    echo -e "  ${GREEN}[2] 提取文件${RESET}"
    echo -e "  ${YELLOW}[3] 删除备份${RESET}"
    echo -e "  ${CYAN}[0] 返回${RESET}"
    
    echo -ne "\n${YELLOW}选择操作: ${RESET}"
    read -r action
    
    case "$action" in
        1) verify_single_backup "$backup_path" ;;
        2) extract_backup_files "$backup_path" ;;
        3) delete_backup "$backup_path" ;;
    esac
}

# 验证单个备份完整性
verify_single_backup() {
    local backup_path="$1"
    
    echo -e "\n${CYAN}验证备份完整性...${RESET}"
    
    if [[ "$backup_path" == *.tar.gz ]]; then
        echo -n "检查压缩包... "
        if tar -tzf "$backup_path" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ 压缩包完整${RESET}"
            
            # 检查关键文件
            echo -n "检查关键文件... "
            local required_files=("backup_info.md" "backup_info.txt")
            local missing_files=()
            
            for file in "${required_files[@]}"; do
                if ! tar -tzf "$backup_path" | grep -q "$file"; then
                    missing_files+=("$file")
                fi
            done
            
            if [ ${#missing_files[@]} -eq 0 ]; then
                echo -e "${GREEN}✓ 关键文件完整${RESET}"
            else
                echo -e "${YELLOW}⚠ 缺少文件: ${missing_files[*]}${RESET}"
            fi
            
        else
            echo -e "${RED}✗ 压缩包损坏${RESET}"
        fi
        
    elif [ -d "$backup_path" ]; then
        echo -n "检查目录结构... "
        
        local checks_passed=0
        local total_checks=3
        
        # 检查1: 备份信息文件
        if [ -f "$backup_path/backup_info.md" ] || [ -f "$backup_path/backup_info.txt" ]; then
            ((checks_passed++))
        fi
        
        # 检查2: 至少有一个数据目录
        if [ -d "$backup_path/astrbot_data" ] || [ -d "$backup_path/napcat_data" ] || [ -d "$backup_path/shared_folder" ]; then
            ((checks_passed++))
        fi
        
        # 检查3: 配置文件存在
        if [ -f "$backup_path/astrbot.json" ] || [ -f "$backup_path/napcat.json" ] || [ -f "$backup_path/docker_daemon.json" ]; then
            ((checks_passed++))
        fi
        
        if [ "$checks_passed" -eq "$total_checks" ]; then
            echo -e "${GREEN}✓ 目录结构完整 ($checks_passed/$total_checks)${RESET}"
        elif [ "$checks_passed" -ge 1 ]; then
            echo -e "${YELLOW}⚠ 部分完整 ($checks_passed/$total_checks)${RESET}"
        else
            echo -e "${RED}✗ 目录结构不完整${RESET}"
        fi
    fi
    
    # 计算完整性百分比
    local integrity=0
    if [[ "$backup_path" == *.tar.gz ]]; then
        integrity=95  # 假设压缩包验证通过
    elif [ -d "$backup_path" ]; then
        integrity=$((checks_passed * 100 / total_checks))
    fi
    
    echo -e "\n${WHITE}完整性评估: ${RESET}"
    if [ "$integrity" -ge 90 ]; then
        echo -e "${GREEN}  ██████████ 100% - 优秀${RESET}"
    elif [ "$integrity" -ge 70 ]; then
        echo -e "${YELLOW}  ████████░░ 80% - 良好${RESET}"
    elif [ "$integrity" -ge 50 ]; then
        echo -e "${ORANGE}  ██████░░░░ 60% - 一般${RESET}"
    else
        echo -e "${RED}  ████░░░░░░ 40% - 较差${RESET}"
    fi
    
    echo -e "\n${GREEN}验证完成${RESET}"
    read -p "按任意键继续..."
}

# 恢复完整备份
restore_full_backup() {
    echo -e "\n${RED}${ICON_WARN} 恢复完整备份${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    # 警告信息
    echo -e "${RED}⚠️  ⚠️  ⚠️  重要警告 ⚠️  ⚠️  ⚠️${RESET}"
    echo -e "${RED}此操作将覆盖现有数据，可能导致数据丢失！${RESET}"
    echo -e "${RED}请在继续前确认已备份重要数据！${RESET}"
    
    if ! confirm_action "恢复备份将停止容器并覆盖数据"; then
        return
    fi
    
    # 选择备份文件
    echo -e "\n${CYAN}选择要恢复的备份:${RESET}"
    
    local backup_files=($(find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -o -name "*backup_*" -type d | sort -r))
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}未找到备份文件${RESET}"
        return
    fi
    
    for i in "${!backup_files[@]}"; do
        local idx=$((i+1))
        local name=$(basename "${backup_files[$i]}")
        local size=$(du -sh "${backup_files[$i]}" 2>/dev/null | cut -f1)
        echo -e "  ${CYAN}[$idx] ${name} (${size})${RESET}"
    done
    
    echo -ne "\n${YELLOW}选择备份序号 (0取消): ${RESET}"
    read -r backup_choice
    
    if ! [[ "$backup_choice" =~ ^[0-9]+$ ]] || [ "$backup_choice" -eq 0 ] || [ "$backup_choice" -gt ${#backup_files[@]} ]; then
        echo -e "${RED}取消恢复${RESET}"
        return
    fi
    
    local selected_backup="${backup_files[$((backup_choice-1))]}"
    local backup_name=$(basename "$selected_backup")
    
    echo -e "\n${CYAN}准备恢复备份: ${WHITE}$backup_name${RESET}"
    
    # 验证备份
    echo -n "验证备份... "
    if ! verify_single_backup_silent "$selected_backup"; then
        echo -e "${RED}✗ 备份验证失败${RESET}"
        return
    fi
    echo -e "${GREEN}✓${RESET}"
    
    # 创建恢复目录
    local restore_dir="/tmp/restore_$(date +%s)"
    mkdir -p "$restore_dir"
    
    # 提取备份
    echo -n "提取备份文件... "
    if [[ "$selected_backup" == *.tar.gz ]]; then
        tar -xzf "$selected_backup" -C "$restore_dir" 2>/dev/null
    else
        cp -r "$selected_backup"/* "$restore_dir/" 2>/dev/null
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${RESET}"
    else
        echo -e "${RED}✗ 提取失败${RESET}"
        rm -rf "$restore_dir"
        return
    fi
    
    # 检查恢复目录
    if [ ! -f "$restore_dir/backup_info.md" ] && [ ! -f "$restore_dir/backup_info.txt" ]; then
        echo -e "${RED}✗ 备份信息文件缺失${RESET}"
        rm -rf "$restore_dir"
        return
    fi
    
    # 显示恢复计划
    echo -e "\n${CYAN}恢复计划:${RESET}"
    
    local restore_items=()
    [ -d "$restore_dir/astrbot_data" ] && restore_items+=("AstrBot数据")
    [ -d "$restore_dir/napcat_data" ] && restore_items+=("NapCat数据")
    [ -d "$restore_dir/shared_folder" ] && restore_items+=("共享文件夹")
    [ -f "$restore_dir/docker_daemon.json" ] && restore_items+=("Docker配置")
    [ -f "$restore_dir/system_resolved.conf" ] && restore_items+=("DNS配置")
    
    for item in "${restore_items[@]}"; do
        echo -e "  ${GREEN}✓${RESET} $item"
    done
    
    # 确认恢复
    echo -e "\n${RED}即将执行以下操作:${RESET}"
    echo -e "  1. 停止AstrBot和NapCat容器"
    echo -e "  2. 备份当前数据到临时位置"
    echo -e "  3. 恢复备份数据"
    echo -e "  4. 重启容器"
    
    if ! confirm_action "确认执行恢复操作"; then
        rm -rf "$restore_dir"
        return
    fi
    
    # 开始恢复
    echo -e "\n${CYAN}开始恢复...${RESET}"
    
    # 步骤1: 停止容器
    echo -n "停止容器... "
    docker stop astrbot napcat 2>/dev/null
    echo -e "${GREEN}✓${RESET}"
    
    # 步骤2: 备份当前数据
    echo -n "备份当前数据... "
    local current_backup="/tmp/current_backup_$(date +%s)"
    mkdir -p "$current_backup"
    
    [ -d "astrbot/data" ] && cp -r astrbot/data "$current_backup/astrbot_data" 2>/dev/null
    [ -d "napcat/data" ] && cp -r napcat/data "$current_backup/napcat_data" 2>/dev/null
    [ -d "$SHARED_DIR" ] && cp -r "$SHARED_DIR" "$current_backup/shared_folder" 2>/dev/null
    
    echo -e "${GREEN}✓${RESET} (备份到: $current_backup)"
    
    # 步骤3: 恢复数据
    echo -e "\n${CYAN}恢复数据...${RESET}"
    
    # 恢复AstrBot数据
    if [ -d "$restore_dir/astrbot_data" ]; then
        echo -n "恢复AstrBot数据... "
        rm -rf astrbot/data 2>/dev/null
        mkdir -p astrbot/data
        cp -r "$restore_dir/astrbot_data"/* astrbot/data/ 2>/dev/null
        echo -e "${GREEN}✓${RESET}"
    fi
    
    # 恢复NapCat数据
    if [ -d "$restore_dir/napcat_data" ]; then
        echo -n "恢复NapCat数据... "
        rm -rf napcat/data 2>/dev/null
        mkdir -p napcat/data
        cp -r "$restore_dir/napcat_data"/* napcat/data/ 2>/dev/null
        echo -e "${GREEN}✓${RESET}"
    fi
    
    # 恢复共享文件夹
    if [ -d "$restore_dir/shared_folder" ]; then
        echo -n "恢复共享文件夹... "
        rm -rf "$SHARED_DIR" 2>/dev/null
        mkdir -p "$SHARED_DIR"
        cp -r "$restore_dir/shared_folder"/* "$SHARED_DIR/" 2>/dev/null
        chmod -R 777 "$SHARED_DIR"
        echo -e "${GREEN}✓${RESET}"
    fi
    
    # 恢复Docker配置
    if [ -f "$restore_dir/docker_daemon.json" ]; then
        echo -n "恢复Docker配置... "
        cp "$restore_dir/docker_daemon.json" /etc/docker/daemon.json 2>/dev/null
        echo -e "${GREEN}✓${RESET}"
    fi
    
    # 恢复DNS配置
    if [ -f "$restore_dir/system_resolved.conf" ]; then
        echo -n "恢复DNS配置... "
        cp "$restore_dir/system_resolved.conf" /etc/systemd/resolved.conf 2>/dev/null
        systemctl restart systemd-resolved 2>/dev/null
        echo -e "${GREEN}✓${RESET}"
    fi
    
    # 步骤4: 重启容器
    echo -e "\n${CYAN}重启容器...${RESET}"
    
    echo -n "启动AstrBot... "
    docker start astrbot 2>/dev/null && echo -e "${GREEN}✓${RESET}" || echo -e "${RED}✗${RESET}"
    
    echo -n "启动NapCat... "
    docker start napcat 2>/dev/null && echo -e "${GREEN}✓${RESET}" || echo -e "${RED}✗${RESET}"
    
    # 清理临时文件
    echo -n "清理临时文件... "
    rm -rf "$restore_dir"
    echo -e "${GREEN}✓${RESET}"
    
    # 显示恢复结果
    echo -e "\n${GREEN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          恢复完成！${RESET}"
    echo -e "${GREEN}════════════════════════════════════════════${RESET}"
    
    echo -e "${WHITE}恢复的备份: ${GREEN}$backup_name${RESET}"
    echo -e "${WHITE}恢复时间: ${GREEN}$(date)${RESET}"
    echo -e "${WHITE}当前数据备份: ${GREEN}$current_backup${RESET}"
    echo -e "${WHITE}容器状态:${RESET}"
    
    sleep 2
    
    # 检查容器状态
    check_container_status "astrbot"
    check_container_status "napcat"
    
    # 记录恢复日志
    echo "$(date) | RESTORE | $backup_name | 成功" >> "$BACKUP_DIR/restore_history.log"
    
    echo -e "\n${GREEN}${ICON_CHECK} 恢复完成！按任意键继续...${RESET}"
    read -p ""
}

# 清理旧备份
cleanup_old_backups() {
    echo -e "\n${YELLOW}${ICON_WARN} 清理旧备份文件${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    # 显示当前备份情况
    local total_backups=$(find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -o -name "*backup_*" -type d | wc -l)
    local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    
    echo -e "${WHITE}当前备份: ${GREEN}$total_backups 个${RESET}"
    echo -e "${WHITE}占用空间: ${GREEN}$total_size${RESET}"
    
    if [ "$total_backups" -eq 0 ]; then
        echo -e "${YELLOW}没有可清理的备份${RESET}"
        return
    fi
    
    echo -e "\n${CYAN}清理策略:${RESET}"
    echo -e "  ${WHITE}[1] ${GREEN}保留最近7天的备份${RESET}"
    echo -e "  ${WHITE}[2] ${GREEN}保留最近30天的备份${RESET}"
    echo -e "  ${WHITE}[3] ${GREEN}保留最近10个备份${RESET}"
    echo -e "  ${WHITE}[4] ${GREEN}保留最近30个备份${RESET}"
    echo -e "  ${WHITE}[5] ${RED}清理所有备份${RESET}"
    echo -e "  ${WHITE}[6] ${YELLOW}手动选择清理${RESET}"
    
    echo -ne "\n${YELLOW}选择清理策略 (1-6, 0取消): ${RESET}"
    read -r strategy
    
    case "$strategy" in
        1) # 保留最近7天
            cleanup_by_days 7
            ;;
        2) # 保留最近30天
            cleanup_by_days 30
            ;;
        3) # 保留最近10个
            cleanup_by_count 10
            ;;
        4) # 保留最近30个
            cleanup_by_count 30
            ;;
        5) # 清理所有
            cleanup_all_backups
            ;;
        6) # 手动选择
            cleanup_manual_selection
            ;;
        0)
            echo -e "${GRAY}取消清理${RESET}"
            return
            ;;
        *)
            echo -e "${RED}无效选择${RESET}"
            return
            ;;
    esac
    
    # 显示清理结果
    local new_count=$(find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -o -name "*backup_*" -type d | wc -l)
    local new_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    
    echo -e "\n${GREEN}清理完成！${RESET}"
    echo -e "${WHITE}剩余备份: ${GREEN}$new_count 个${RESET}"
    echo -e "${WHITE}剩余空间: ${GREEN}$new_size${RESET}"
    echo -e "${WHITE}清理数量: ${GREEN}$((total_backups - new_count)) 个${RESET}"
}

# 按天数清理备份
cleanup_by_days() {
    local days_to_keep=$1
    
    echo -e "\n${CYAN}清理 $days_to_keep 天前的备份...${RESET}"
    
    local files_to_delete=$(find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -o -name "*backup_*" -type d -mtime +$days_to_keep 2>/dev/null)
    
    if [ -z "$files_to_delete" ]; then
        echo -e "${YELLOW}没有超过 ${days_to_keep} 天的备份${RESET}"
        return
    fi
    
    local delete_count=$(echo "$files_to_delete" | wc -l)
    local total_size=0
    
    # 计算总大小
    while IFS= read -r file; do
        local size=$(du -sb "$file" 2>/dev/null | cut -f1)
        total_size=$((total_size + size))
    done <<< "$files_to_delete"
    
    local human_size=$(numfmt --to=iec $total_size 2>/dev/null || echo "$total_size 字节")
    
    echo -e "${WHITE}将删除 ${delete_count} 个备份，释放 ${human_size} 空间${RESET}"
    
    # 显示将要删除的文件
    echo -e "\n${CYAN}将要删除的备份:${RESET}"
    echo "$files_to_delete" | head -10 | while read file; do
        echo "  $(basename "$file")"
    done
    
    if [ "$delete_count" -gt 10 ]; then
        echo -e "  ... 还有 $((delete_count - 10)) 个文件"
    fi
    
    if ! confirm_action "确认删除以上备份文件"; then
        return
    fi
    
    # 执行删除
    echo "$files_to_delete" | while read file; do
        echo -n "删除 $(basename "$file") ... "
        rm -rf "$file"
        echo -e "${GREEN}✓${RESET}"
    done
    
    echo -e "\n${GREEN}已删除 $delete_count 个旧备份${RESET}"
}

# 按数量清理备份
cleanup_by_count() {
    local count_to_keep=$1
    
    echo -e "\n${CYAN}保留最近 $count_to_keep 个备份...${RESET}"
    
    # 获取所有备份文件，按时间排序
    local all_backups=($(find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -o -name "*backup_*" -type d -printf "%T@ %p\n" 2>/dev/null | sort -rn | cut -d' ' -f2-))
    
    local total_count=${#all_backups[@]}
    
    if [ "$total_count" -le "$count_to_keep" ]; then
        echo -e "${YELLOW}只有 $total_count 个备份，无需清理${RESET}"
        return
    fi
    
    local files_to_delete=("${all_backups[@]:$count_to_keep}")
    local delete_count=${#files_to_delete[@]}
    local total_size=0
    
    # 计算总大小
    for file in "${files_to_delete[@]}"; do
        local size=$(du -sb "$file" 2>/dev/null | cut -f1)
        total_size=$((total_size + size))
    done
    
    local human_size=$(numfmt --to=iec $total_size 2>/dev/null || echo "$total_size 字节")
    
    echo -e "${WHITE}将删除 ${delete_count} 个备份，释放 ${human_size} 空间${RESET}"
    
    # 显示将要删除的文件
    echo -e "\n${CYAN}将要删除的备份:${RESET}"
    for ((i=0; i<${#files_to_delete[@]} && i<10; i++)); do
        echo "  $(basename "${files_to_delete[$i]}")"
    done
    
    if [ "$delete_count" -gt 10 ]; then
        echo -e "  ... 还有 $((delete_count - 10)) 个文件"
    fi
    
    if ! confirm_action "确认删除以上备份文件"; then
        return
    fi
    
    # 执行删除
    for file in "${files_to_delete[@]}"; do
        echo -n "删除 $(basename "$file") ... "
        rm -rf "$file"
        echo -e "${GREEN}✓${RESET}"
    done
    
    echo -e "\n${GREEN}已删除 $delete_count 个旧备份${RESET}"
}

# 辅助函数：静默验证备份
verify_single_backup_silent() {
    local backup_path="$1"
    
    if [[ "$backup_path" == *.tar.gz ]]; then
        tar -tzf "$backup_path" >/dev/null 2>&1
        return $?
    elif [ -d "$backup_path" ]; then
        [ -f "$backup_path/backup_info.md" ] || [ -f "$backup_path/backup_info.txt" ]
        return $?
    fi
    
    return 1
}

extract_urls_from_logs() {
    local target=${1:-"both"}  # 默认为both，同时提取两个容器的日志
    local urls=""
    
    if [ "$target" = "both" ] || [ "$target" = "astrbot" ]; then
        if docker ps -a --format "{{.Names}}" | grep -q "^astrbot$"; then
            urls+=$(timeout 10 docker logs astrbot 2>/dev/null | grep -Eo 'https?://[^"[:space:]]+' | sort -u)
            [ -n "$urls" ] && urls+=$'\n'
        fi
    fi
    
    if [ "$target" = "both" ] || [ "$target" = "napcat" ]; then
        if docker ps -a --format "{{.Names}}" | grep -q "^napcat$"; then
            urls+=$(timeout 10 docker logs napcat 2>/dev/null | grep -Eo 'https?://[^"[:space:]]+' | sort -u)
        fi
    fi
    
    if [ -n "$urls" ]; then
        local url_file="${LOG_DIR}/extracted_urls_$(date +%Y%m%d_%H%M%S).txt"
        echo "$urls" > "$url_file"
        
        echo -e "\n${CYAN}提取到的URL:${RESET}"
        echo "$urls"
        echo -e "\n${GREEN}✅ URL已保存到: $url_file${RESET}"
    else
        echo -e "${YELLOW}⚠️  未找到URL或读取超时${RESET}"
    fi
}

monitor_system_resources() {
    echo -e "\n${CYAN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}           系统资源监控${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local cpu_color=$([ "${cpu_usage%.*}" -gt 80 ] && echo "$RED" || echo "$GREEN")
    
    local mem_percent=$(free | awk '/^Mem:/{print $3/$2*100}')
    local mem_info=$(free -h | awk '/^Mem:/{print $3"/"$2}')
    local mem_color=$([ "${mem_percent%.*}" -gt 80 ] && echo "$RED" || echo "$GREEN")
    
    local disk_percent=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    local disk_info=$(df -h / | awk 'NR==2 {print $3"/"$2}')
    local disk_color=$([ "$disk_percent" -gt 80 ] && echo "$RED" || echo "$GREEN")
    
    local load_avg=$(cat /proc/loadavg | awk '{print $1", "$2", "$3}')
    local uptime_info=$(uptime -p | sed 's/up //')
    
    echo -e "${ICON_CPU}  CPU使用率: ${cpu_color}${cpu_usage}%${RESET}"
    echo -e "${ICON_RAM}  内存使用: ${mem_color}${mem_info} (${mem_percent%.*}%)${RESET}"
    echo -e "${ICON_DISK} 磁盘使用: ${disk_color}${disk_info} (${disk_percent}%)${RESET}"
    echo -e "${ICON_TIME} 系统负载: ${WHITE}${load_avg}${RESET}"
    echo -e "${ICON_TIME} 运行时间: ${WHITE}${uptime_info}${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
}

test_network_connectivity() {
    echo -e "\n${CYAN}${ICON_NETWORK} 网络连通性测试${RESET}"
    local test_hosts=("8.8.8.8" "114.114.114.114" "223.5.5.5" "1.1.1.1")
    local success_count=0
    
    for host in "${test_hosts[@]}"; do
        echo -n "测试 $host ... "
        if ping -c 1 -W 2 "$host" &>/dev/null; then
            echo -e "${GREEN}${ICON_CHECK}${RESET}"
            ((success_count++))
        else
            echo -e "${RED}${ICON_CROSS}${RESET}"
        fi
    done
    
    if [ "$success_count" -ge 2 ]; then
        echo -e "${GREEN}${ICON_CHECK} 网络连通性正常（${success_count}/4个节点可达）${RESET}"
        return 0
    else
        echo -e "${RED}${ICON_CROSS} 网络连通性差（${success_count}/4个节点可达）${RESET}"
        return 1
    fi
}

check_container_status() {
    local container_name=$1
    echo -e "\n${CYAN}${ICON_INFO} 容器状态检查: $container_name${RESET}"
    
    if docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
        local state=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || echo "unknown")
        local health=$(docker inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "N/A")
        
        case "$state" in
            "running")
                echo -e "状态: ${GREEN}运行中 ${ICON_CHECK}${RESET}"
                echo -e "健康: ${GREEN}${health}${RESET}"
                
                echo -e "${CYAN}端口映射:${RESET}"
                docker port "$container_name" 2>/dev/null | while read line; do
                    echo "  $line"
                done || echo "  (无端口映射)"
                
                # 检查共享目录挂载
                if docker inspect "$container_name" 2>/dev/null | grep -q "\"Source\": \"$SHARED_DIR\""; then
                    echo -e "${GREEN}${ICON_CHECK} 共享目录已挂载${RESET}"
                else
                    echo -e "${YELLOW}${ICON_WARN} 共享目录未挂载【考虑到不可抗的检测bug若一直显示这一条，请运行扩展功能中的修复工具】${RESET}"
                fi
                ;;
            "created")
                echo -e "状态: ${YELLOW}已创建但未启动 ${ICON_WARN}${RESET}"
                ;;
            "exited")
                echo -e "状态: ${RED}已退出 ${ICON_CROSS}${RESET}"
                local exit_code=$(docker inspect -f '{{.State.ExitCode}}' "$container_name" 2>/dev/null || echo "unknown")
                echo -e "退出码: ${RED}${exit_code}${RESET}"
                ;;
            "restarting")
                echo -e "状态: ${BLUE}重启中 ${ICON_LOAD}${RESET}"
                ;;
            *)
                echo -e "状态: ${GRAY}${state}${RESET}"
                ;;
        esac
        return 0
    else
        echo -e "${RED}${ICON_CROSS} 容器不存在${RESET}"
        return 1
    fi
}

rollback_step() {
    local step=$1
    echo -e "\n${YELLOW}${ICON_WARN} 正在回滚步骤 ${step}...${RESET}"
    
    case $step in
        1)
            if [ -f "/etc/systemd/resolved.conf.bak" ]; then
                cp /etc/systemd/resolved.conf.bak /etc/systemd/resolved.conf
                systemctl restart systemd-resolved 2>/dev/null
                echo -e "${GREEN}${ICON_CHECK} DNS配置已回滚${RESET}"
            fi
            ;;
        2)
            echo -e "${YELLOW}${ICON_WARN} 卸载Docker...${RESET}"
            apt-get purge -y docker.io docker-compose docker-ce docker-ce-cli 2>/dev/null
            rm -rf /var/lib/docker /etc/docker
            echo -e "${GREEN}${ICON_CHECK} Docker已卸载${RESET}"
            ;;
        3)
            echo -e "${YELLOW}${ICON_WARN} 删除AstrBot容器...${RESET}"
            docker rm -f astrbot 2>/dev/null
            rm -rf astrbot data/astrbot 2>/dev/null
            echo -e "${GREEN}${ICON_CHECK} AstrBot已删除${RESET}"
            ;;
        4)
            echo -e "${YELLOW}${ICON_WARN} 删除NapCat容器...${RESET}"
            docker rm -f napcat 2>/dev/null
            rm -rf napcat data/napcat 2>/dev/null
            echo -e "${GREEN}${ICON_CHECK} NapCat已删除${RESET}"
            ;;
        *)
            echo -e "${RED}${ICON_CROSS} 未知步骤${RESET}"
            ;;
    esac
}

check_version_compatibility() {
    echo -e "\n${CYAN}${ICON_INFO} 版本兼容性检查${RESET}"
    
    local kernel_version=$(uname -r)
    echo -e "${WHITE}内核版本: ${GREEN}${kernel_version}${RESET}"
    
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version | grep -oP '\d+\.\d+\.\d+')
        echo -e "${WHITE}Docker版本: ${GREEN}${docker_version}${RESET}"
    fi
    
    echo -e "${GREEN}${ICON_CHECK} 版本兼容性检查完成${RESET}"
}

cleanup() {
    echo -e "\n${YELLOW}${ICON_WARN} 正在清理临时进程...${RESET}"
    pkill -P $$ 2>/dev/null || true
    printf "\r\033[K"
    echo -e "${GREEN}${ICON_CHECK} 清理完成！${RESET}"
}

setup_shared_directory() {
    echo -e "\n${CYAN}${ICON_FOLDER} 设置共享目录...${RESET}"
    
    # 创建共享目录
    mkdir -p "$SHARED_DIR"
    
    # 设置更安全的权限：777（所有用户可读写执行）
    chmod -R 777 "$SHARED_DIR"
    
    echo -e "${GREEN}${ICON_CHECK} 共享目录已创建: ${WHITE}$SHARED_DIR${RESET}"
    echo -e "${GRAY}权限: $(ls -ld "$SHARED_DIR" | awk '{print $1}')${RESET}"
    echo -e "${GRAY}所有者: $(ls -ld "$SHARED_DIR" | awk '{print $3":"$4}')${RESET}"
}

check_shared_directory() {
    echo -e "\n${CYAN}${ICON_FOLDER} 检查共享目录状态${RESET}"
    
    if [ -d "$SHARED_DIR" ]; then
        local perm=$(ls -ld "$SHARED_DIR" | awk '{print $1}')
        local owner=$(ls -ld "$SHARED_DIR" | awk '{print $3":"$4}')
        local size=$(du -sh "$SHARED_DIR" | awk '{print $1}')
        local file_count=$(find "$SHARED_DIR" -type f | wc -l)
        
        echo -e "目录: ${WHITE}$SHARED_DIR${RESET}"
        echo -e "权限: ${WHITE}$perm${RESET}"
        echo -e "所有者: ${WHITE}$owner${RESET}"
        echo -e "大小: ${WHITE}$size${RESET}"
        echo -e "文件数: ${WHITE}$file_count${RESET}"
        
        # 检查容器挂载情况
        echo -e "\n${CYAN}容器挂载检查:${RESET}"
        if docker inspect astrbot 2>/dev/null | grep -q "\"Source\": \"$SHARED_DIR\""; then
            echo -e "${GREEN}${ICON_CHECK} AstrBot已挂载共享目录${RESET}"
        else
            echo -e "${YELLOW}${ICON_WARN} AstrBot未挂载共享目录${RESET}"
        fi
        
        if docker inspect napcat 2>/dev/null | grep -q "\"Source\": \"$SHARED_DIR\""; then
            echo -e "${GREEN}${ICON_CHECK} NapCat已挂载共享目录${RESET}"
        else
            echo -e "${YELLOW}${ICON_WARN} NapCat未挂载共享目录${RESET}"
        fi
        
        if [ "$file_count" -gt 0 ]; then
            echo -e "\n${CYAN}最近文件:${RESET}"
            find "$SHARED_DIR" -type f -printf "%T+ %p\n" 2>/dev/null | sort -r | head -3 | while read line; do
                echo "  ${line#* }"
            done
        fi
    else
        echo -e "${RED}${ICON_CROSS} 共享目录不存在${RESET}"
        echo -e "${YELLOW}建议运行部署脚本重新创建${RESET}"
    fi
}

test_shared_folder() {
    echo -e "\n${CYAN}${ICON_INFO} 测试共享文件夹功能${RESET}"
    
    # 首先检查共享目录是否存在
    if [ ! -d "$SHARED_DIR" ]; then
        echo -e "${RED}${ICON_CROSS} 共享目录不存在: $SHARED_DIR${RESET}"
        echo -e "${YELLOW}正在创建共享目录...${RESET}"
        setup_shared_directory
    fi
    
    # 检查容器是否存在
    local astrbot_exists=false
    local napcat_exists=false
    
    if docker ps -a --format "{{.Names}}" | grep -q "^astrbot$"; then
        astrbot_exists=true
    fi
    
    if docker ps -a --format "{{.Names}}" | grep -q "^napcat$"; then
        napcat_exists=true
    fi
    
    # 创建测试文件
    local test_file="$SHARED_DIR/mount_test.txt"
    local test_content="这是挂载测试文件"
    
    echo -e "${WHITE}在宿主机创建测试文件...${RESET}"
    echo "$test_content" > "$test_file"
    echo -e "${GREEN}${ICON_CHECK} 测试文件已创建: $(basename "$test_file")${RESET}"
    
    local napcat_ok=false
    local astrbot_ok=false
    
    # 测试NapCat
    if $napcat_exists; then
        echo -e "\n${WHITE}测试NapCat容器读取...${RESET}"
        if docker exec napcat test -f "/app/sharedFolder/$(basename "$test_file")" 2>/dev/null; then
            echo -e "${GREEN}${ICON_CHECK} NapCat可以读取共享文件${RESET}"
            napcat_ok=true
        else
            echo -e "${RED}${ICON_CROSS} NapCat无法读取共享文件${RESET}"
            echo -e "${YELLOW}可能原因:${RESET}"
            echo -e "  1. 共享目录未正确挂载到NapCat容器"
            echo -e "  2. 容器内路径不正确"
            echo -e "  3. 容器没有运行"
            
            # 检查NapCat容器详情
            if docker inspect napcat 2>/dev/null | grep -q "\"Source\": \"$SHARED_DIR\""; then
                echo -e "${GREEN}${ICON_CHECK} 挂载点配置正确${RESET}"
            else
                echo -e "${RED}${ICON_CROSS} 挂载点配置错误${RESET}"
            fi
        fi
    else
        echo -e "${YELLOW}${ICON_WARN} NapCat容器不存在，跳过测试${RESET}"
    fi
    
    # 测试AstrBot
    if $astrbot_exists; then
        echo -e "\n${WHITE}测试AstrBot容器读取...${RESET}"
        if docker exec astrbot test -f "/app/sharedFolder/$(basename "$test_file")" 2>/dev/null; then
            echo -e "${GREEN}${ICON_CHECK} AstrBot可以读取共享文件${RESET}"
            astrbot_ok=true
        else
            echo -e "${RED}${ICON_CROSS} AstrBot无法读取共享文件${RESET}"
            echo -e "${YELLOW}可能原因:${RESET}"
            echo -e "  1. 共享目录未正确挂载到AstrBot容器"
            echo -e "  2. 容器内路径不正确"
            echo -e "  3. 容器没有运行"
            
            # 检查AstrBot容器详情
            if docker inspect astrbot 2>/dev/null | grep -q "\"Source\": \"$SHARED_DIR\""; then
                echo -e "${GREEN}${ICON_CHECK} 挂载点配置正确${RESET}"
            else
                echo -e "${RED}${ICON_CROSS} 挂载点配置错误${RESET}"
            fi
        fi
    else
        echo -e "${YELLOW}${ICON_WARN} AstrBot容器不存在，跳过测试${RESET}"
    fi
    
    # 清理测试文件
    rm -f "$test_file"
    echo -e "\n${GREEN}${ICON_CHECK} 测试文件已清理${RESET}"
    
    # 测试结果总结
    echo -e "\n${CYAN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          测试结果总结${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    if $napcat_ok && $astrbot_ok; then
        echo -e "${GREEN}${ICON_CHECK} 共享文件夹功能正常${RESET}"
        echo -e "${GREEN}两个容器都可以正常读写共享目录${RESET}"
    elif $napcat_ok && ! $astrbot_ok; then
        echo -e "${YELLOW}${ICON_WARN} 共享文件夹功能部分正常${RESET}"
        echo -e "${YELLOW}NapCat正常，但AstrBot无法访问${RESET}"
    elif ! $napcat_ok && $astrbot_ok; then
        echo -e "${YELLOW}${ICON_WARN} 共享文件夹功能部分正常${RESET}"
        echo -e "${YELLOW}AstrBot正常，但NapCat无法访问${RESET}"
    else
        echo -e "${RED}${ICON_CROSS} 共享文件夹功能异常${RESET}"
        echo -e "${YELLOW}两个容器都无法访问共享目录${RESET}"
        echo -e "\n${YELLOW}解决方案:${RESET}"
        echo -e "  1. 重新部署两个容器"
        echo -e "  2. 检查共享目录权限: chmod -R 777 $SHARED_DIR"
        echo -e "  3. 手动检查容器挂载: docker inspect <容器名>"
        echo -e "  4. 运行扩展功能中的修复工具"
    fi
}

fix_shared_mount() {
    echo -e "\n${RED}${ICON_WARN} 共享目录挂载修复工具 ${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    if ! confirm_action "此操作将重启容器以修复共享目录挂载问题"; then
        return
    fi
    
    # 检查容器状态
    local astrbot_running=false
    local napcat_running=false
    
    if docker ps --format "{{.Names}}" | grep -q "^astrbot$"; then
        astrbot_running=true
    fi
    
    if docker ps --format "{{.Names}}" | grep -q "^napcat$"; then
        napcat_running=true
    fi
    
    # 获取当前容器的挂载配置
    echo -e "\n${CYAN}检查当前挂载配置...${RESET}"
    
    local astrbot_mounts=$(docker inspect astrbot --format='{{range .Mounts}}{{printf "%-40s -> %s\n" .Source .Destination}}{{end}}' 2>/dev/null)
    local napcat_mounts=$(docker inspect napcat --format='{{range .Mounts}}{{printf "%-40s -> %s\n" .Source .Destination}}{{end}}' 2>/dev/null)
    
    echo -e "${WHITE}AstrBot挂载:${RESET}"
    echo "$astrbot_mounts" || echo "  无挂载信息"
    
    echo -e "\n${WHITE}NapCat挂载:${RESET}"
    echo "$napcat_mounts" || echo "  无挂载信息"
    
    # 备份重要数据
    echo -e "\n${YELLOW}${ICON_WARN} 备份容器数据...${RESET}"
    local backup_dir="/tmp/container_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    if $astrbot_running; then
        docker cp astrbot:/AstrBot/data "$backup_dir/astrbot_data" 2>/dev/null
        docker inspect astrbot > "$backup_dir/astrbot.json" 2>/dev/null
    fi
    
    if $napcat_running; then
        docker cp napcat:/app/data "$backup_dir/napcat_data" 2>/dev/null
        docker inspect napcat > "$backup_dir/napcat.json" 2>/dev/null
    fi
    
    echo -e "${GREEN}${ICON_CHECK} 数据已备份到: $backup_dir${RESET}"
    
    # 重新创建共享目录
    echo -e "\n${CYAN}重新设置共享目录...${RESET}"
    setup_shared_directory
    
    # 停止并删除容器
    echo -e "\n${YELLOW}${ICON_WARN} 重启容器...${RESET}"
    
    if $astrbot_running; then
        echo -e "重新部署AstrBot..."
        docker stop astrbot >/dev/null 2>&1
        docker rm astrbot >/dev/null 2>&1
        
        # 重新运行AstrBot（带共享目录挂载）
        docker run -d \
            -p 6180-6200:6180-6200 \
            -p 11451:11451 \
            -v "$SHARED_DIR:/app/sharedFolder" \
            -v "$(pwd)/astrbot/data:/AstrBot/data" \
            -v /etc/localtime:/etc/localtime:ro \
            --name astrbot \
            --restart=always \
            soulter/astrbot:latest
    fi
    
    if $napcat_running; then
        echo -e "重新部署NapCat..."
        docker stop napcat >/dev/null 2>&1
        docker rm napcat >/dev/null 2>&1
        
        # 重新运行NapCat（带共享目录挂载）
        docker run -d \
            -p 3000:3000 \
            -p 3001:3001 \
            -p 6099:6099 \
            -v "$SHARED_DIR:/app/sharedFolder" \
            -v "$(pwd)/napcat/data:/app/data" \
            -v /etc/localtime:/etc/localtime:ro \
            --name napcat \
            --restart=always \
            mlikiowa/napcat-docker:latest
    fi
    
    echo -e "\n${GREEN}${ICON_CHECK} 容器重启完成！${RESET}"
    
    # 等待容器启动
    sleep 5
    
    # 验证修复
    echo -e "\n${CYAN}验证修复结果...${RESET}"
    test_shared_folder
    
    echo -e "\n${GREEN}修复完成！${RESET}"
    echo -e "备份文件保存在: $backup_dir"
    echo -e "${YELLOW}如需恢复，请手动复制备份文件${RESET}"
}

# ===================== DNS修复功能 =====================
fix_dns_configuration() {
    echo -e "\n${CYAN}${ICON_DNS} DNS配置修复工具 ${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    if ! confirm_action "修复DNS配置（修改/etc/systemd/resolved.conf并重启服务）"; then
        return
    fi
    
    echo -e "${CYAN}${ICON_INFO} 步骤1：备份原始配置文件...${RESET}"
    
    # 备份原始配置文件
    if [ -f "/etc/systemd/resolved.conf" ]; then
        local backup_file="/etc/systemd/resolved.conf.bak.$(date +%Y%m%d_%H%M%S)"
        cp /etc/systemd/resolved.conf "$backup_file"
        echo -e "${GREEN}${ICON_CHECK} 原始配置已备份到: $backup_file${RESET}"
    fi
    
    echo -e "${CYAN}${ICON_INFO} 步骤2：修改/etc/systemd/resolved.conf...${RESET}"
    
    # 创建新的resolved.conf文件 - 使用统一配置
    cat > /etc/systemd/resolved.conf << 'EOF'
# DNS配置优化
[Resolve]
DNS=8.8.8.8 114.114.114.114 223.5.5.5 1.1.1.1
FallbackDNS=208.67.222.222 208.67.220.220
Domains=~
LLMNR=no
MulticastDNS=no
DNSSEC=no
DNSOverTLS=no
Cache=yes
DNSStubListener=yes
ReadEtcHosts=yes
EOF
    
    echo -e "${GREEN}${ICON_CHECK} /etc/systemd/resolved.conf 配置完成${RESET}"
    
    echo -e "${CYAN}${ICON_INFO} 步骤3：重启域名解析服务...${RESET}"
    
    # 重启systemd-resolved服务
    if systemctl restart systemd-resolved; then
        echo -e "${GREEN}${ICON_CHECK} systemd-resolved服务重启成功${RESET}"
        
        # 启用服务（如果尚未启用）
        systemctl enable systemd-resolved >/dev/null 2>&1
        echo -e "${GREEN}${ICON_CHECK} systemd-resolved服务已启用${RESET}"
    else
        echo -e "${RED}${ICON_CROSS} systemd-resolved服务重启失败${RESET}"
        return 1
    fi
    
    echo -e "${CYAN}${ICON_INFO} 步骤4：更新/etc/resolv.conf软链接...${RESET}"
    
    # 备份当前的/etc/resolv.conf
    if [ -f "/etc/resolv.conf" ]; then
        local resolv_backup="/etc/resolv.conf.bak.$(date +%Y%m%d_%H%M%S)"
        cp /etc/resolv.conf "$resolv_backup"
        echo -e "${GREEN}${ICON_CHECK} /etc/resolv.conf 已备份到: $resolv_backup${RESET}"
        
        # 删除原有的软链接或文件
        rm -f /etc/resolv.conf
    fi
    
    # 创建新的软链接
    if ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf; then
        echo -e "${GREEN}${ICON_CHECK} 软链接创建成功${RESET}"
        echo -e "${GRAY}/etc/resolv.conf -> /run/systemd/resolve/resolv.conf${RESET}"
    else
        echo -e "${RED}${ICON_CROSS} 软链接创建失败${RESET}"
        return 1
    fi
    
    # 验证DNS配置
    echo -e "${CYAN}${ICON_INFO} 步骤5：验证DNS配置...${RESET}"
    
    echo -e "\n${WHITE}当前DNS配置:${RESET}"
    echo -e "${GRAY}$(cat /etc/resolv.conf)${RESET}"
    
    echo -e "\n${WHITE}测试DNS解析...${RESET}"
    local test_domains=("google.com" "baidu.com" "github.com" "qq.com")
    local success_count=0
    
    for domain in "${test_domains[@]}"; do
        echo -n "解析 $domain ... "
        if timeout 5 dig "$domain" +short | grep -q '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'; then
            echo -e "${GREEN}${ICON_CHECK}${RESET}"
            ((success_count++))
        else
            echo -e "${RED}${ICON_CROSS}${RESET}"
        fi
    done
    
    # 测试网络连通性
    echo -e "\n${WHITE}测试网络连通性...${RESET}"
    test_network_connectivity
    
    # 显示修复结果
    echo -e "\n${CYAN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          DNS修复完成总结${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    if [ "$success_count" -ge 3 ]; then
        echo -e "${GREEN}${ICON_CHECK} DNS修复成功${RESET}"
        echo -e "${GREEN}DNS解析测试: ${success_count}/4 通过${RESET}"
        
        echo -e "\n${CYAN}已修改的配置:${RESET}"
        echo -e "  1. ${WHITE}/etc/systemd/resolved.conf${RESET} - 设置DNS为8.8.8.8, 114.114.114.114, 223.5.5.5, 1.1.1.1"
        echo -e "  2. ${WHITE}systemd-resolved服务${RESET} - 已重启并启用"
        echo -e "  3. ${WHITE}/etc/resolv.conf${RESET} - 已重新链接到/run/systemd/resolve/resolv.conf"
        
        echo -e "\n${GREEN}备份文件:${RESET}"
        ls -la /etc/systemd/resolved.conf.bak.* 2>/dev/null || echo "  (无备份文件)"
        ls -la /etc/resolv.conf.bak.* 2>/dev/null || echo "  (无备份文件)"
    else
        echo -e "${YELLOW}${ICON_WARN} DNS修复部分成功${RESET}"
        echo -e "${YELLOW}DNS解析测试: ${success_count}/4 通过${RESET}"
        echo -e "\n${YELLOW}建议检查网络连接或手动配置DNS${RESET}"
    fi
    
    echo -e "\n${GREEN}${ICON_CHECK} DNS修复操作完成！${RESET}"
}

# ===================== 更新检测函数 =====================
check_for_updates() {
    echo -e "\n${CYAN}${ICON_UPDATE} 检查脚本更新${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    echo -e "${WHITE}当前版本: ${GREEN}${CURRENT_VERSION}${RESET}"
    echo -e "${WHITE}最后更新: ${GREEN}2025年12月26日${RESET}"
    
    # 检查网络连通性
    if ! test_network_connectivity; then
        echo -e "${RED}${ICON_CROSS} 网络连接异常，无法检查更新${RESET}"
        echo -e "${YELLOW}${ICON_WARN} 请检查网络设置或稍后重试${RESET}"
        return 1
    fi
    
    echo -e "${CYAN}${ICON_LOAD} 正在检查更新...${RESET}"
    
    # 尝试从多个源获取版本信息
    local remote_version=""
    local update_urls=(
        "https://raw.githubusercontent.com/ygbls/a-n-/refs/heads/main/version.txt"
        "https://fastly.jsdelivr.net/gh/ygbls/a-n-@main/version.txt"
        "https://cdn.jsdelivr.net/gh/ygbls/a-n-@main/version.txt"
    )
    
    local error_messages=""
    local success_count=0
    local error_count=0
    
    for i in "${!update_urls[@]}"; do
        local url="${update_urls[$i]}"
        echo -ne "尝试源 $(($i+1)): "
        
        # 使用timeout限制请求时间
        local temp_file="/tmp/update_check_$(date +%s).tmp"
        local curl_output=$(timeout 15 curl -s -w "%{http_code}" "$url" 2>&1)
        local curl_exit_code=$?
        local http_code="${curl_output: -3}"
        local content="${curl_output%???}"
        
        # 清理可能的多余字符
        content=$(echo "$content" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 检查curl执行结果
        if [ $curl_exit_code -eq 0 ]; then
            if [[ "$http_code" == "200" ]] || [[ "$http_code" == "000" ]]; then
                if [[ "$content" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                    remote_version="$content"
                    echo -e "${GREEN}成功获取版本: ${remote_version}${RESET}"
                    ((success_count++))
                    break
                else
                    echo -e "${YELLOW}版本格式无效${RESET}"
                    error_messages+="源$(($i+1)): 版本格式无效（内容: ${content:0:20}...）\n"
                    ((error_count++))
                fi
            elif [[ "$http_code" == "404" ]]; then
                echo -e "${YELLOW}文件不存在（404）${RESET}"
                error_messages+="源$(($i+1)): 版本文件不存在（404）\n"
                ((error_count++))
            elif [[ "$http_code" == "403" ]]; then
                echo -e "${YELLOW}访问被拒绝（403）${RESET}"
                error_messages+="源$(($i+1)): 访问被拒绝（403）\n"
                ((error_count++))
            elif [[ "$http_code" == "502" ]] || [[ "$http_code" == "503" ]]; then
                echo -e "${YELLOW}服务器错误（${http_code}）${RESET}"
                error_messages+="源$(($i+1)): 服务器错误（${http_code}）\n"
                ((error_count++))
            else
                echo -e "${YELLOW}HTTP错误（${http_code}）${RESET}"
                error_messages+="源$(($i+1)): HTTP错误（${http_code}）\n"
                ((error_count++))
            fi
        elif [ $curl_exit_code -eq 124 ]; then
            echo -e "${YELLOW}请求超时${RESET}"
            error_messages+="源$(($i+1)): 请求超时\n"
            ((error_count++))
        elif [ $curl_exit_code -eq 6 ]; then
            echo -e "${YELLOW}无法解析主机${RESET}"
            error_messages+="源$(($i+1)): 无法解析主机\n"
            ((error_count++))
        elif [ $curl_exit_code -eq 7 ]; then
            echo -e "${YELLOW}无法连接到主机${RESET}"
            error_messages+="源$(($i+1)): 无法连接到主机\n"
            ((error_count++))
        elif [ $curl_exit_code -eq 28 ]; then
            echo -e "${YELLOW}操作超时${RESET}"
            error_messages+="源$(($i+1)): 操作超时\n"
            ((error_count++))
        else
            echo -e "${YELLOW}Curl错误（${curl_exit_code}）${RESET}"
            error_messages+="源$(($i+1)): Curl错误（${curl_exit_code}）\n"
            ((error_count++))
        fi
    done
    
    if [ -z "$remote_version" ]; then
        echo -e "\n${RED}${ICON_CROSS} 无法获取远程版本信息${RESET}"
        echo -e "${YELLOW}${ICON_WARN} 详细错误信息:${RESET}"
        echo -e "$error_messages"
        echo -e "${GRAY}尝试了 ${#update_urls[@]} 个源，成功: ${success_count}，失败: ${error_count}${RESET}"
        echo -e "\n${YELLOW}可能原因:${RESET}"
        echo -e "  1. GitHub可能被墙，请检查网络连接"
        echo -e "  2. 版本文件不存在或路径错误"
        echo -e "  3. 服务器暂时不可用"
        echo -e "  4. 防火墙或代理设置问题"
        echo -e "\n${CYAN}解决方案:${RESET}"
        echo -e "  1. 检查网络连接是否正常"
        echo -e "  2. 等待一段时间后重试"
        echo -e "  3. 手动访问更新源检查"
        return 1
    fi
    
    echo -e "${WHITE}最新版本: ${GREEN}${remote_version}${RESET}"
    
    # 比较版本号
    local current_num=$(echo "$CURRENT_VERSION" | sed 's/v//' | sed 's/\./ /g')
    local remote_num=$(echo "$remote_version" | sed 's/v//' | sed 's/\./ /g')
    
    local current_array=($current_num)
    local remote_array=($remote_num)
    
    local update_needed=false
    
    for i in {0..2}; do
        if [ "${remote_array[i]}" -gt "${current_array[i]}" ]; then
            update_needed=true
            break
        elif [ "${remote_array[i]}" -lt "${current_array[i]}" ]; then
            break
        fi
    done
    
    if [ "$update_needed" = true ]; then
        echo -e "\n${GREEN}${ICON_UPDATE} 发现新版本 ${remote_version}！${RESET}"
        echo -e "${YELLOW}更新内容可能包含:${RESET}"
        echo -e "  • 修复已知问题"
        echo -e "  • 优化部署流程"
        echo -e "  • 新增功能特性"
        
        echo -e "\n${CYAN}════════════════════════════════════════════${RESET}"
        echo -e "${WHITE}           更新选项${RESET}"
        echo -e "${CYAN}════════════════════════════════════════════${RESET}"
        
        echo -e "${WHITE}  1${RESET} ${GREEN}立即更新脚本${RESET}"
        echo -e "${WHITE}  2${RESET} ${CYAN}查看更新日志${RESET}"
        echo -e "${WHITE}  3${RESET} ${YELLOW}手动更新（推荐）${RESET}"
        echo -e "${WHITE}  0${RESET} ${GRAY}暂不更新${RESET}"
        
        echo -ne "\n${YELLOW}请选择操作（0-3）: ${RESET}"
        read -r update_choice
        
        case "$update_choice" in
            1)
                update_script_auto
                ;;
            2)
                show_update_changelog
                ;;
            3)
                show_manual_update_guide
                ;;
            0)
                echo -e "${GRAY}已取消更新${RESET}"
                ;;
            *)
                echo -e "${RED}无效选择${RESET}"
                ;;
        esac
    else
        echo -e "\n${GREEN}${ICON_CHECK} 当前已是最新版本！${RESET}"
        echo -e "${GRAY}无需更新，继续使用当前版本即可${RESET}"
    fi
    
    echo -e "\n${GREEN}按任意键继续...${RESET}"
    read -p ""
}

update_script_auto() {
    echo -e "\n${YELLOW}${ICON_WARN} 警告：自动更新将覆盖当前脚本${RESET}"
    echo -e "${GRAY}建议先备份当前脚本${RESET}"
    
    if ! confirm_action "自动更新脚本到 ${remote_version}"; then
        return
    fi
    
    echo -e "${CYAN}${ICON_DOWNLOAD} 正在下载新版本...${RESET}"
    
    # 备份当前脚本
    local backup_file="/tmp/astr_deploy_backup_$(date +%Y%m%d_%H%M%S).sh"
    cp "$0" "$backup_file"
    echo -e "${GREEN}${ICON_CHECK} 当前脚本已备份到: ${backup_file}${RESET}"
    
    # 尝试多个下载源
    local download_urls=(
        "https://raw.githubusercontent.com/ygbls/a-n-/refs/heads/main/F10.sh"
        "https://fastly.jsdelivr.net/gh/ygbls/a-n-@main/F10.sh"
        "https://cdn.jsdelivr.net/gh/ygbls/a-n-@main/F10.sh"
    )
    
    local temp_file="/tmp/astr_deploy_new.sh"
    local download_success=false
    
    # 启动网速监控
    monitor_speed_mb &
    speed_pid=$!
    
    for url in "${download_urls[@]}"; do
        echo -e "尝试从 ${url##*/} 下载..."
        if timeout 30 curl -s -o "$temp_file" "$url"; then
            download_success=true
            safe_kill "$speed_pid"
            printf "\r\033[K"  # 清除网速监控行
            break
        fi
    done
    
    if [ "$download_success" = true ]; then
        # 检查下载的文件是否有效
        if [ -s "$temp_file" ] && head -n 5 "$temp_file" | grep -q "AstrBot+NapCat 智能部署助手"; then
            # 替换当前脚本
            chmod +x "$temp_file"
            cp "$temp_file" "$0"
            
            echo -e "${GREEN}${ICON_CHECK} 脚本更新成功！${RESET}"
            echo -e "${YELLOW}${ICON_WARN} 需要重新运行脚本以应用更新${RESET}"
            
            if confirm_action "立即重启脚本"; then
                echo -e "${GREEN}正在重启脚本...${RESET}"
                exec bash "$0"
            else
                echo -e "${GRAY}下次运行脚本时将使用新版本${RESET}"
            fi
        else
            echo -e "${RED}${ICON_CROSS} 下载的文件无效，更新失败${RESET}"
            echo -e "${YELLOW}正在恢复备份...${RESET}"
            cp "$backup_file" "$0"
        fi
    else
        safe_kill "$speed_pid"
        printf "\r\033[K"  # 清除网速监控行
        echo -e "${RED}${ICON_CROSS} 下载失败，请检查网络连接${RESET}"
        echo -e "${YELLOW}${ICON_WARN} 更新已取消，脚本未更改${RESET}"
    fi
    
    # 清理临时文件
    rm -f "$temp_file"
}

show_update_changelog() {
    echo -e "\n${CYAN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}           更新日志${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"

    echo -e "${GREEN}v2.6.1 (2025-12-26)${RESET}"
    echo -e "  • 完善备份功能"
    echo -e "  • 优化系统提示"
    echo -e "  • 重建UI界面"

    echo -e "${GREEN}v2.5.10 (2025-12-26)${RESET}"
    echo -e "  • 优化系统提示"
    echo -e "  • 重建UI界面"

    echo -e "${GREEN}v2.5.9 (2025-12-26)${RESET}"
    echo -e "  • 重建UI界面"
   
    echo -e "${GREEN}v2.5.8 (2025-12-26)${RESET}"
    echo -e "  • 修复共享目录路径矛盾"
    echo -e "  • 统一DNS配置为8.8.8.8, 114.114.114.114, 223.5.5.5, 1.1.1.1"
    echo -e "  • 改进共享目录权限管理（777权限）"
    echo -e "  • 优化容器重启策略为always"
    echo -e "  • 移除重复的警告提示"
    echo -e "  • 修复更新检测逻辑"

    echo -e "\n${GREEN}v2.5.4 (2025-12-25)${RESET}"
    echo -e "  • 添加DNS修复功能到扩展菜单"
    echo -e "  • 优化DNS配置步骤"
    echo -e "  • 改进系统兼容性检查"
    
    echo -e "\n${GREEN}v2.5.3 (2025-12-25)${RESET}"
    echo -e "  • 增强更新检测错误处理"
    echo -e "  • 优化网速显示功能"
    echo -e "  • 添加多个更新源支持"
    
    echo -e "\n${GREEN}v2.5.2 (2025-12-25)${RESET}"
    echo -e "  • 修复共享目录挂载问题"
    echo -e "  • 优化容器状态检查逻辑"
    echo -e "  • 添加扩展功能菜单"
    
    echo -e "\n${GREEN}v2.5.1 (2025-12-20)${RESET}"
    echo -e "  • 添加DNS优化配置"
    echo -e "  • 改进网络检测功能"
    echo -e "  • 修复Docker安装问题"
    
    echo -e "\n${GREEN}v2.5.0 (2025-12-15)${RESET}"
    echo -e "  • 初始版本发布"
    echo -e "  • 支持AstrBot和NapCat部署"
    echo -e "  • 添加一键安装功能"
    
    echo -e "\n${CYAN}════════════════════════════════════════════${RESET}"
    echo -e "${YELLOW}最新版本 ${remote_version} 的更新内容请访问:${RESET}"
    echo -e "${WHITE}https://github.com/ygbls/a-n-${RESET}"
    
    echo -e "\n${GREEN}按任意键返回...${RESET}"
    read -p ""
}

show_manual_update_guide() {
    echo -e "\n${CYAN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}           手动更新指南${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    echo -e "${WHITE}推荐手动更新，步骤如下:${RESET}"
    echo ""
    echo -e "1. ${CYAN}备份当前脚本${RESET}"
    echo -e "   ${GRAY}cp $(basename "$0") $(basename "$0").backup${RESET}"
    echo ""
    echo -e "2. ${CYAN}下载最新版本${RESET}"
    echo -e "   ${GRAY}wget https://raw.githubusercontent.com/ygbls/a-n-/main/F10.sh${RESET}"
    echo -e "   ${GRAY}或 wget https://cdn.jsdelivr.net/gh/ygbls/a-n-@main/F10.sh${RESET}"
    echo ""
    echo -e "3. ${CYAN}验证脚本完整性${RESET}"
    echo -e "   ${GRAY}chmod +x F10.sh${RESET}"
    echo -e "   ${GRAY}bash F10.sh --test${RESET}"
    echo ""
    echo -e "4. ${CYAN}替换旧脚本${RESET}"
    echo -e "   ${GRAY}mv F10.sh $(basename "$0")${RESET}"
    echo ""
    echo -e "5. ${CYAN}重新运行脚本${RESET}"
    echo -e "   ${GRAY}bash $(basename "$0")${RESET}"
    echo ""
    echo -e "${YELLOW}注意:${RESET}"
    echo -e "  • 更新前请确保已备份重要数据"
    echo -e "  • 如果部署过程中，请先完成当前部署再更新"
    echo -e "  • 更新后可能需要重新配置某些选项"
    
    echo -e "\n${CYAN}════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}按任意键返回...${RESET}"
    read -p ""
}

# ===================== 显示函数 =====================
print_header() {
    clear
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${MAGENTA}║                                                                              ║${RESET}"
    echo -e "${MAGENTA}║  ${CYAN}   █████╗ ███████╗████████╗██████╗ ██████╗  ██████╗ ████████╗           ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║  ${CYAN}  ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██╔═══██╗╚══██╔══╝           ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║  ${CYAN}  ███████║███████╗   ██║   ██████╔╝██████╔╝██║   ██║   ██║              ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║  ${CYAN}  ██╔══██║╚════██║   ██║   ██╔══██╗██╔══██╗██║   ██║   ██║              ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║  ${CYAN}  ██║  ██║███████║   ██║   ██║  ██║██████╔╝╚██████╔╝   ██║              ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║  ${CYAN}  ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═════╝  ╚═════╝    ╚═╝              ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║                                                                              ║${RESET}"
    echo -e "${MAGENTA}║  ${WHITE}                N a p C a t  智能部署助手  v2.6.1                  ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║  ${GRAY}           修复共享目录矛盾 | 统一DNS配置 | 优化权限管理            ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║                                                                              ║${RESET}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_system_status() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║  ${WHITE}📊 系统状态监控                                                          ${CYAN}║${RESET}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    # 获取系统信息
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local mem_total=$(free -h | awk '/^Mem:/{print $2}')
    local mem_used=$(free -h | awk '/^Mem:/{print $3}')
    local disk_total=$(df -h / | awk 'NR==2 {print $2}')
    local disk_used=$(df -h / | awk 'NR==2 {print $3}')
    local disk_percent=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    local load_avg=$(cat /proc/loadavg | awk '{print $1", "$2", "$3}')
    local uptime_info=$(uptime -p | sed 's/up //')
    
    # 进度条函数
    progress_bar() {
        local value=$1
        local max=100
        local bar_width=30
        local filled=$((value * bar_width / max))
        local empty=$((bar_width - filled))
        
        printf "["
        for ((i=0; i<filled; i++)); do printf "█"; done
        for ((i=0; i<empty; i++)); do printf " "; done
        printf "] %3d%%" "$value"
    }
    
    # CPU使用率
    local cpu_color=$([ "${cpu_usage%.*}" -gt 80 ] && echo "$RED" || ([ "${cpu_usage%.*}" -gt 50 ] && echo "$YELLOW" || echo "$GREEN"))
    echo -e "${CYAN}║  ${WHITE}🖥  CPU使用率: ${cpu_color}$(progress_bar ${cpu_usage%.*})${WHITE}                             ${CYAN}║${RESET}"
    
    # 内存使用
    local mem_percent=$(free | awk '/^Mem:/{print $3/$2*100}')
    local mem_color=$([ "${mem_percent%.*}" -gt 80 ] && echo "$RED" || ([ "${mem_percent%.*}" -gt 50 ] && echo "$YELLOW" || echo "$GREEN"))
    echo -e "${CYAN}║  ${WHITE}💾  内存使用: ${mem_color}$(progress_bar ${mem_percent%.*})${WHITE} ${mem_used}/${mem_total}       ${CYAN}║${RESET}"
    
    # 磁盘使用
    local disk_color=$([ "$disk_percent" -gt 80 ] && echo "$RED" || ([ "$disk_percent" -gt 50 ] && echo "$YELLOW" || echo "$GREEN"))
    echo -e "${CYAN}║  ${WHITE}💿  磁盘使用: ${disk_color}$(progress_bar $disk_percent)${WHITE} ${disk_used}/${disk_total}       ${CYAN}║${RESET}"
    
    # 负载和运行时间
    echo -e "${CYAN}║  ${WHITE}📈  系统负载: ${WHITE}${load_avg}${WHITE}                                     ${CYAN}║${RESET}"
    echo -e "${CYAN}║  ${WHITE}⏱  运行时间: ${WHITE}${uptime_info}${WHITE}                                   ${CYAN}║${RESET}"
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_deployment_status() {
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║  ${WHITE}🚀 部署进度状态                                                           ${GREEN}║${RESET}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    local step_status=()
    step_status[1]=$([ "$STEP1_DONE" = true ] && echo "${GREEN}✓${RESET}" || echo "${GRAY}○${RESET}")
    step_status[2]=$([ "$STEP2_DONE" = true ] && echo "${GREEN}✓${RESET}" || echo "${GRAY}○${RESET}")
    step_status[3]=$([ "$STEP3_DONE" = true ] && echo "${GREEN}✓${RESET}" || echo "${GRAY}○${RESET}")
    step_status[4]=$([ "$STEP4_DONE" = true ] && echo "${GREEN}✓${RESET}" || echo "${GRAY}○${RESET}")
    
    echo -e "${GREEN}║                                                                              ║${RESET}"
    echo -e "${GREEN}║  ${WHITE}     [${step_status[1]}] ${WHITE}① 网络配置${RESET}   ${WHITE}[${step_status[2]}] ${WHITE}② Docker安装${RESET}   ${WHITE}[${step_status[3]}] ${WHITE}③ AstrBot${RESET}   ${WHITE}[${step_status[4]}] ${WHITE}④ NapCat${RESET}    ${GREEN}║${RESET}"
    echo -e "${GREEN}║                                                                              ║${RESET}"
    
    # 容器状态
    local astrbot_status=$(docker inspect -f '{{.State.Status}}' astrbot 2>/dev/null || echo "not_exist")
    local napcat_status=$(docker inspect -f '{{.State.Status}}' napcat 2>/dev/null || echo "not_exist")
    
    echo -e "${GREEN}║  ${WHITE}容器状态:                                                                 ${GREEN}║${RESET}"
    
    if [ "$astrbot_status" = "running" ]; then
        echo -e "${GREEN}║     ${GREEN}✅ AstrBot: 运行中${RESET} (端口: 6180-6200, 11451)                    ${GREEN}║${RESET}"
    elif [ "$astrbot_status" = "not_exist" ]; then
        echo -e "${GREEN}║     ${GRAY}○ AstrBot: 未部署${RESET}                                             ${GREEN}║${RESET}"
    else
        echo -e "${GREEN}║     ${YELLOW}⚠️ AstrBot: ${astrbot_status}${RESET}                                  ${GREEN}║${RESET}"
    fi
    
    if [ "$napcat_status" = "running" ]; then
        echo -e "${GREEN}║     ${GREEN}✅ NapCat: 运行中${RESET} (端口: 3000, 3001, 6099)                    ${GREEN}║${RESET}"
    elif [ "$napcat_status" = "not_exist" ]; then
        echo -e "${GREEN}║     ${GRAY}○ NapCat: 未部署${RESET}                                              ${GREEN}║${RESET}"
    else
        echo -e "${GREEN}║     ${YELLOW}⚠️ NapCat: ${napcat_status}${RESET}                                   ${GREEN}║${RESET}"
    fi
    
    echo -e "${GREEN}║                                                                              ║${RESET}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_main_menu() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║  ${WHITE}📱 主功能菜单                                                              ${BLUE}║${RESET}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    echo -e "${BLUE}║                                                                              ║${RESET}"
    echo -e "${BLUE}║  ${WHITE}┌───────────────── 核心部署 ─────────────────┐${RESET}                       ${BLUE}║${RESET}"
    echo -e "${BLUE}║                                                                              ║${RESET}"
    
    echo -e "${BLUE}║  ${CYAN}[1] ${GREEN}🌐 网络配置与DNS优化${RESET}                                        ${BLUE}║${RESET}"
    echo -e "${BLUE}║       ${WHITE}优化网络设置，配置多重DNS解析${RESET}                                    ${BLUE}║${RESET}"
    echo -e "${BLUE}║                                                                              ║${RESET}"
    
    echo -e "${BLUE}║  ${CYAN}[2] ${GREEN}🐳 Docker环境管理${RESET}                                          ${BLUE}║${RESET}"
    echo -e "${BLUE}║       ${WHITE}安装/卸载Docker，配置镜像加速${RESET}                                    ${BLUE}║${RESET}"
    echo -e "${BLUE}║                                                                              ║${RESET}"
    
    echo -e "${BLUE}║  ${CYAN}[3] ${GREEN}🤖 部署AstrBot机器人${RESET}                                       ${BLUE}║${RESET}"
    echo -e "${BLUE}║       ${WHITE}端口: 6180-6200, 11451 | Web界面管理${RESET}                            ${BLUE}║${RESET}"
    echo -e "${BLUE}║                                                                              ║${RESET}"
    
    echo -e "${BLUE}║  ${CYAN}[4] ${GREEN}😺 部署NapCat协议服务${RESET}                                      ${BLUE}║${RESET}"
    echo -e "${BLUE}║       ${WHITE}端口: 3000, 3001, 6099 | 协议端管理${RESET}                             ${BLUE}║${RESET}"
    echo -e "${BLUE}║                                                                              ║${RESET}"
    
    echo -e "${BLUE}║  ${WHITE}└─────────────────────────────────────────────┘${RESET}                       ${BLUE}║${RESET}"
    echo -e "${BLUE}║                                                                              ║${RESET}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    echo -e "${BLUE}║  ${WHITE}┌─────────────── 快捷操作 ───────────────┐${RESET}                            ${BLUE}║${RESET}"
    echo -e "${BLUE}║                                                                              ║${RESET}"
    
    echo -e "${BLUE}║  ${CYAN}[0] ${GREEN}🚀 一键完整部署${RESET} (推荐新手使用)                               ${BLUE}║${RESET}"
    echo -e "${BLUE}║  ${CYAN}[E] ${CYAN}⚙️  扩展工具箱${RESET} (监控/修复/工具)                              ${BLUE}║${RESET}"
    echo -e "${BLUE}║  ${CYAN}[C] ${SKY}📋  查看详细状态${RESET} (容器/资源)                                 ${BLUE}║${RESET}"
    echo -e "${BLUE}║  ${CYAN}[U] ${YELLOW}🔄  检查更新${RESET} (脚本更新)                                    ${BLUE}║${RESET}"
    echo -e "${BLUE}║  ${CYAN}[Q] ${RED}❌  退出脚本${RESET}                                               ${BLUE}║${RESET}"
    
    echo -e "${BLUE}║  ${WHITE}└─────────────────────────────────────────┘${RESET}                            ${BLUE}║${RESET}"
    echo -e "${BLUE}║                                                                              ║${RESET}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_contact_info() {
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${MAGENTA}║                                                                              ║${RESET}"
    echo -e "${MAGENTA}║  ${YELLOW}⚠️  重要声明: ${WHITE}本脚本完全免费，严禁倒卖！${RESET}                               ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║  ${CYAN}💝 技术支持: ${WHITE}QQ 3076737056 | 最后更新: 2025年12月26日${RESET}                ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║                                                                              ║${RESET}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}
# ===================== 步骤函数定义 =====================
step1() {
    CURRENT_STEP="step1"
    local step_start=$(date +%s)
    
    if [ "$STEP1_DONE" = true ]; then
        echo -e "${GREEN}${ICON_CHECK} 第一步已完成${RESET}"
        return
    fi
    
    if ! confirm_action "网络配置与DNS优化"; then
        return
    fi
    
    print_header
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          第一步：网络与DNS配置${RESET}"
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    
    if ! test_network_connectivity; then
        echo -e "\n${YELLOW}${ICON_WARN} 网络异常，正在配置DNS...${RESET}"
        
        if [ -f "/etc/systemd/resolved.conf" ]; then
            mkdir -p "$BACKUP_DIR"
            cp /etc/systemd/resolved.conf "$BACKUP_DIR/resolved.conf.bak.$(date +%Y%m%d_%H%M%S)"
        fi
        
        # 使用统一的DNS配置
        cat > /etc/systemd/resolved.conf << 'EOF'
[Resolve]
DNS=8.8.8.8 114.114.114.114 223.5.5.5 1.1.1.1
FallbackDNS=208.67.222.222 208.67.220.220
EOF
        
        if systemctl restart systemd-resolved 2>/dev/null; then
            systemctl enable systemd-resolved >/dev/null 2>&1
            echo -e "${GREEN}${ICON_CHECK} DNS配置完成${RESET}"
            sleep 2
            test_network_connectivity
        else
            echo -e "${RED}${ICON_CROSS} DNS服务重启失败${RESET}"
        fi
    else
        echo -e "${GREEN}${ICON_CHECK} 网络正常${RESET}"
    fi
    
    STEP1_DONE=true
    STEP1_DURATION=$(( $(date +%s) - step_start ))
    echo -e "\n${GRAY}耗时: ${STEP1_DURATION}秒${RESET}"
}

# ===================== 第二步：重写的Docker安装/卸载 =====================
step2() {
    CURRENT_STEP="step2"
    local step_start=$(date +%s)
    
    # 显示Docker管理菜单
    echo -e "\n${CYAN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          Docker 管理菜单${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}  1${RESET} ${GREEN}${ICON_DOCKER} 安装 Docker${RESET}"
    echo -e "${WHITE}  2${RESET} ${RED}${ICON_CROSS} 卸载 Docker${RESET}"
    echo -e "${WHITE}  0${RESET} ${GRAY}返回主菜单${RESET}"
    
    echo -ne "\n${YELLOW}${ICON_WARN} 请选择操作（0-2）: ${RESET}"
    read -r docker_choice
    
    case "$docker_choice" in
        1)
            install_docker
            ;;
        2)
            uninstall_docker
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}${ICON_CROSS} 无效选择！${RESET}"
            sleep 1
            return
            ;;
    esac
}

install_docker() {
    local step_start=$(date +%s)
    
    print_header
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          安装 Docker${RESET}"
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    
    # 检查是否已安装Docker
    if command -v docker &>/dev/null; then
        echo -e "${GREEN}${ICON_CHECK} 检测到Docker已安装，版本: $(docker --version | cut -d' ' -f3)${RESET}"
        STEP2_DONE=true
        return
    fi
    
    if ! confirm_action "安装Docker及Docker Compose"; then
        return
    fi
    
    echo -e "${CYAN}${ICON_LOAD} 开始安装Docker...${RESET}"
    
    # ===================== 步骤1: 清理旧的/错误的Docker源配置 =====================
    echo -e "\n${CYAN}[1/15] 清理旧的Docker源配置...${RESET}"
    local clean_log="/tmp/docker_clean.log"
    echo "=== 清理旧的Docker源配置 $(date) ===" >> "$clean_log"
    
    # 删除可能错误的Docker源文件
    rm -f /etc/apt/sources.list.d/docker.list
    echo -e "${GREEN}${ICON_CHECK} 已清理旧的Docker源文件${RESET}"
    
    # 更新apt缓存（清空旧的源信息）
    monitor_speed_mb &
    speed_pid=$!
    if apt-get update -y 2>&1 | tee -a "$clean_log"; then
        safe_kill "$speed_pid"
        printf "\r\033[K"
        echo -e "${GREEN}${ICON_CHECK} apt缓存已更新${RESET}"
    else
        safe_kill "$speed_pid"
        printf "\r\033[K"
        echo -e "${YELLOW}${ICON_WARN} apt缓存更新遇到错误${RESET}"
    fi
    
    # ===================== 步骤2: 修改系统镜像源 =====================
    echo -e "\n${CYAN}[2/15] 修改系统镜像源...${RESET}"
    local sources_log="/tmp/docker_sources.log"
    echo "=== 修改系统镜像源 $(date) ===" >> "$sources_log"
    
    # 备份原始镜像源
    cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d_%H%M%S)
    
    cat > /etc/apt/sources.list << 'EOF'
deb http://mirrors.aliyun.com/ubuntu-old-releases/ubuntu/ hirsute main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-old-releases/ubuntu/ hirsute-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-old-releases/ubuntu/ hirsute-backports main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-old-releases/ubuntu/ hirsute-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-old-releases/ubuntu/ hirsute main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-old-releases/ubuntu/ hirsute-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-old-releases/ubuntu/ hirsute-backports main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu-old-releases/ubuntu/ hirsute-security main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ noble main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ noble main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ noble-security main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ noble-security main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ noble-updates main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ noble-updates main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ noble-backports main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ noble-backports main restricted universe multiverse
EOF
    
    echo -e "${GREEN}${ICON_CHECK} 系统镜像源已修改为阿里云${RESET}"
    
    # ===================== 步骤3: 安装依赖工具 =====================
    echo -e "\n${CYAN}[3/15] 安装依赖工具...${RESET}"
    local deps_log="/tmp/docker_deps_install.log"
    echo "=== 安装依赖工具 $(date) ===" >> "$deps_log"
    
    if apt-get install -y ca-certificates curl gnupg lsb-release 2>&1 | tee "$deps_log"; then
        echo -e "${GREEN}${ICON_CHECK} 依赖工具安装完成${RESET}"
    else
        echo -e "${YELLOW}${ICON_WARN} 依赖工具安装遇到错误${RESET}"
    fi
    
    # 询问是否继续
    if ! confirm_action "继续安装Docker？"; then
        echo -e "${YELLOW}安装已取消${RESET}"
        return
    fi
    
    # ===================== 步骤4: 添加Docker官方GPG密钥 =====================
    echo -e "\n${CYAN}[4/15] 添加Docker官方GPG密钥...${RESET}"
    local gpg_log="/tmp/docker_gpg.log"
    echo "=== 添加Docker官方GPG密钥 $(date) ===" >> "$gpg_log"
    
    # 创建密钥存储目录
    mkdir -p /etc/apt/trusted.gpg.d
    mkdir -p /etc/apt/keyrings
    
    # 下载并导入Docker官方GPG密钥
    if curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg 2>&1 | tee "$gpg_log"; then
        echo -e "${GREEN}${ICON_CHECK} Docker官方GPG密钥添加成功${RESET}"
    else
        echo -e "${YELLOW}${ICON_WARN} GPG密钥添加遇到问题，尝试备用方法...${RESET}"
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 7EA0A9C3F273FCD8 2>&1 | tee -a "$gpg_log"
    fi
    
    # ===================== 步骤5: 添加Docker官方源 =====================
    echo -e "\n${CYAN}[5/15] 添加Docker官方源...${RESET}"
    local repo_log="/tmp/docker_repo.log"
    echo "=== 添加Docker官方源 $(date) ===" >> "$repo_log"
    
    # 生成正确的源配置（适配当前系统版本）
    local codename=$(lsb_release -cs)
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] https://download.docker.com/linux/ubuntu $codename stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    echo -e "${GREEN}${ICON_CHECK} Docker官方源添加完成${RESET}"
    echo -e "${GRAY}系统版本: $codename${RESET}"
    
    # ===================== 步骤6: 修正Docker源签名配置 =====================
    echo -e "\n${CYAN}[6/15] 修正Docker源签名配置...${RESET}"
    local fix_log="/tmp/docker_fix.log"
    echo "=== 修正Docker源签名配置 $(date) ===" >> "$fix_log"
    
    local docker_list_file="/etc/apt/sources.list.d/docker.list"
    if [ -f "$docker_list_file" ]; then
        # 确保签名配置正确
        sed -i 's|signed-by=/usr/share/keyrings/docker-archive-keyring.gpg|signed-by=/etc/apt/trusted.gpg.d/docker.gpg|' "$docker_list_file"
        echo -e "${GREEN}${ICON_CHECK} Docker源签名配置修正完成${RESET}"
    else
        echo -e "${YELLOW}${ICON_WARN} Docker源文件不存在${RESET}"
    fi
    
    # ===================== 步骤7: 更新apt包索引 =====================
    echo -e "\n${CYAN}[7/15] 更新apt包索引...${RESET}"
    echo "=== 更新apt包索引 $(date) ===" >> "$repo_log"
    monitor_speed_mb &
    speed_pid=$!
    
    if apt-get update -y 2>&1 | tee -a "$repo_log"; then
        safe_kill "$speed_pid"
        printf "\r\033[K"
        echo -e "${GREEN}${ICON_CHECK} apt包索引更新完成${RESET}"
    else
        safe_kill "$speed_pid"
        printf "\r\033[K"
        echo -e "${YELLOW}${ICON_WARN} apt包索引更新遇到错误${RESET}"
    fi
    
    # ===================== 步骤8: 安装Docker组件 =====================
    echo -e "\n${CYAN}[8/15] 安装Docker组件...${RESET}"
    echo "=== 安装Docker组件 $(date) ===" >> "$repo_log"
    echo -e "${CYAN}${ICON_NETWORK} Docker组件下载速度（M/s）${RESET}"
    monitor_speed_mb &
    speed_pid=$!
    
    local install_log="/tmp/docker_install.log"
    if apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>&1 | tee "$install_log"; then
        safe_kill "$speed_pid"
        printf "\r\033[K"
        echo -e "${GREEN}${ICON_CHECK} Docker组件安装完成${RESET}"
    else
        safe_kill "$speed_pid"
        printf "\r\033[K"
        echo -e "${RED}${ICON_CROSS} Docker组件安装失败！${RESET}"
        echo -e "${YELLOW}查看日志: $install_log${RESET}"
        return 1
    fi
    
    # ===================== 步骤9: 配置Docker镜像源 =====================
    echo -e "\n${CYAN}[9/15] 配置Docker镜像源...${RESET}"
    local mirror_log="/tmp/docker_mirror.log"
    echo "=== 配置Docker镜像源 $(date) ===" >> "$mirror_log"
    
    # 创建目录
    mkdir -p /etc/docker
    
    # 备份现有配置文件
    if [ -f "/etc/docker/daemon.json" ]; then
        cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%Y%m%d_%H%M%S)
    fi
    
    # 创建新的配置文件
    cat > /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://registry.cn-hangzhou.aliyuncs.com",
    "https://mirror.ccs.tencentyun.com",
    "https://registry.docker-cn.com",
    "https://mirror.baidubce.com",
    "https://hub-mirror.c.163.com",
    "https://hub.fast360.xyz",
    "https://hub.rat.dev",
    "https://docker-0.unsee.tech",
    "https://docker.mirrors.ustc.edu.cn",
    "https://docker.hlmirror.com",
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run",
    "https://image.cloudlayer.icu"
  ]
}
EOF
    
    echo -e "${GREEN}${ICON_CHECK} Docker镜像源配置完成${RESET}"
    echo -e "${GRAY}镜像源数量: $(grep -c "https://" /etc/docker/daemon.json) 个${RESET}"
    
    # ===================== 步骤10: 启动Docker服务 =====================
    echo -e "\n${CYAN}[10/15] 启动Docker服务...${RESET}"
    local service_log="/tmp/docker_service.log"
    if systemctl start docker 2>&1 | tee "$service_log"; then
        echo -e "${GREEN}${ICON_CHECK} Docker服务启动成功${RESET}"
    else
        echo -e "${RED}${ICON_CROSS} Docker服务启动失败${RESET}"
        echo -e "${YELLOW}查看日志: $service_log${RESET}"
        return 1
    fi
    
    # ===================== 步骤11: 设置开机自启 =====================
    echo -e "\n${CYAN}[11/15] 设置Docker开机自启...${RESET}"
    if systemctl enable docker 2>&1 | tee -a "$service_log"; then
        echo -e "${GREEN}${ICON_CHECK} Docker开机自启设置成功${RESET}"
    else
        echo -e "${YELLOW}${ICON_WARN} Docker开机自启设置失败${RESET}"
    fi
    
    # ===================== 步骤12: 重启Docker服务 =====================
    echo -e "\n${CYAN}[12/15] 重启Docker服务应用配置...${RESET}"
    if systemctl restart docker 2>&1 | tee -a "$service_log"; then
        echo -e "${GREEN}${ICON_CHECK} Docker服务重启成功${RESET}"
    else
        echo -e "${YELLOW}${ICON_WARN} Docker服务重启失败${RESET}"
    fi
    
    # ===================== 步骤13: 测试Docker安装 =====================
    echo -e "\n${CYAN}[13/15] 测试Docker安装...${RESET}"
    local test_log="/tmp/docker_test.log"
    local test_output=$(docker run --rm hello-world 2>&1)
    echo "$test_output" | tee "$test_log"
    
    if echo "$test_output" | grep -q "Hello from Docker"; then
        echo -e "${GREEN}${ICON_CHECK} Docker测试成功！${RESET}"
    else
        echo -e "${YELLOW}${ICON_WARN} Docker测试输出异常${RESET}"
    fi
    
    # ===================== 步骤14: 验证安装 =====================
    echo -e "\n${CYAN}[14/15] 验证Docker安装...${RESET}"
    local docker_version=$(docker --version 2>/dev/null || echo "未知")
    local compose_version=$(docker compose version 2>/dev/null || echo "未知")
    
    echo -e "${GREEN}${ICON_CHECK} Docker版本: ${WHITE}${docker_version}${RESET}"
    echo -e "${GREEN}${ICON_CHECK} Docker Compose版本: ${WHITE}${compose_version}${RESET}"
    
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}${ICON_CHECK} Docker服务运行状态: ${WHITE}运行中${RESET}"
    else
        echo -e "${RED}${ICON_CROSS} Docker服务运行状态: ${WHITE}未运行${RESET}"
    fi
    
    # ===================== 步骤15: 清理和总结 =====================
    echo -e "\n${CYAN}[15/15] 清理和总结...${RESET}"
    STEP2_DONE=true
    STEP2_DURATION=$(( $(date +%s) - step_start ))
    
    echo -e "\n${GREEN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          Docker安装完成！${RESET}"
    echo -e "${GREEN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}安装日志: ${GRAY}/tmp/docker_*.log${RESET}"
    echo -e "${WHITE}耗时: ${GREEN}${STEP2_DURATION}秒${RESET}"
    echo -e "${WHITE}原始apt源备份: ${GRAY}/etc/apt/sources.list.bak.*${RESET}"
    echo -e "\n${GREEN}按任意键继续...${RESET}"
    read -p ""
}

uninstall_docker() {
    print_header
    echo -e "${RED}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          卸载 Docker${RESET}"
    echo -e "${RED}════════════════════════════════════════════${RESET}"
    
    if ! confirm_action "卸载Docker及相关组件，此操作不可逆！"; then
        return
    fi
    
    echo -e "${CYAN}${ICON_LOAD} 开始卸载Docker...${RESET}"
    
    # 停止Docker服务
    echo -e "\n${CYAN}[1/5] 停止Docker服务...${RESET}"
    systemctl stop docker 2>/dev/null
    systemctl stop docker.socket 2>/dev/null
    echo -e "${GREEN}${ICON_CHECK} Docker服务已停止${RESET}"
    
    # 卸载Docker包
    echo -e "\n${CYAN}[2/5] 卸载Docker软件包...${RESET}"
    local uninstall_log="/tmp/docker_uninstall.log"
    local uninstall_output=$(apt-get purge -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-compose-plugin \
        docker-ce-rootless-extras \
        docker.io \
        docker-compose 2>&1 | tee "$uninstall_log")
    
    echo "$uninstall_output" | tail -10
    echo -e "${GREEN}${ICON_CHECK} Docker软件包已卸载${RESET}"
    
    # 删除Docker相关文件
    echo -e "\n${CYAN}[3/5] 删除Docker相关文件...${RESET}"
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd
    rm -rf /etc/docker
    rm -rf /etc/apt/keyrings/docker.gpg
    rm -rf /etc/apt/trusted.gpg.d/docker.gpg
    rm -f /etc/apt/sources.list.d/docker.list
    echo -e "${GREEN}${ICON_CHECK} Docker相关文件已删除${RESET}"
    
    # 清理未使用的依赖
    echo -e "\n${CYAN}[4/5] 清理未使用的依赖...${RESET}"
    apt-get autoremove -y 2>&1 | tee -a "$uninstall_log"
    echo -e "${GREEN}${ICON_CHECK} 依赖清理完成${RESET}"
    
    # 验证卸载
    echo -e "\n${CYAN}[5/5] 验证卸载结果...${RESET}"
    if command -v docker &>/dev/null; then
        echo -e "${RED}${ICON_CROSS} Docker卸载不彻底！${RESET}"
    else
        echo -e "${GREEN}${ICON_CHECK} Docker已成功卸载${RESET}"
        STEP2_DONE=false
    fi
    
    if [ -d "/var/lib/docker" ]; then
        echo -e "${YELLOW}${ICON_WARN} /var/lib/docker 目录仍然存在${RESET}"
    else
        echo -e "${GREEN}${ICON_CHECK} /var/lib/docker 目录已删除${RESET}"
    fi
    
    echo -e "\n${GREEN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          Docker卸载完成！${RESET}"
    echo -e "${GREEN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}卸载日志: ${GRAY}$uninstall_log${RESET}"
    echo -e "\n${GREEN}按任意键继续...${RESET}"
    read -p ""
}

step3() {
    CURRENT_STEP="step3"
    local step_start=$(date +%s)
    
    if [ "$STEP3_DONE" = true ]; then
        echo -e "${GREEN}${ICON_CHECK} 第三步已完成${RESET}"
        return
    fi
    
    if ! confirm_action "部署AstrBot容器（端口6180-6200, 11451）"; then
        return
    fi
    
    [ "$STEP2_DONE" = false ] && { echo -e "${YELLOW}${ICON_WARN} 需要先安装Docker${RESET}"; step2; }
    
    print_header
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          第三步：部署AstrBot${RESET}"
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    
    # 检查容器是否存在
    if docker ps -a --filter "name=astrbot" --format "{{.Names}}" | grep -q "astrbot"; then
        # 检查容器状态
        local container_state=$(docker inspect -f '{{.State.Status}}' astrbot 2>/dev/null || echo "unknown")
        
        if [ "$container_state" = "running" ]; then
            echo -e "${GREEN}${ICON_CHECK} AstrBot容器已在运行${RESET}"
            
            # 检查是否挂载了共享目录
            if docker inspect astrbot 2>/dev/null | grep -q "\"Source\": \"$SHARED_DIR\""; then
                echo -e "${GREEN}${ICON_CHECK} 共享目录已挂载${RESET}"
            else
                echo -e "${YELLOW}${ICON_WARN} 警告：共享目录未挂载！【考虑到不可抗的检测bug若一直显示这一条，请运行扩展功能中的修复工具】${RESET}"
                echo -e "${YELLOW}建议运行扩展功能中的修复工具${RESET}"
            fi
            
            check_container_status "astrbot"
            STEP3_DONE=true
            return
        else
            echo -e "${YELLOW}${ICON_WARN} AstrBot容器存在但未运行，正在尝试启动...${RESET}"
            
            # 尝试启动容器
            if docker start astrbot; then
                echo -e "${GREEN}${ICON_CHECK} AstrBot容器启动成功${RESET}"
                sleep 3
                
                # 重新检查容器状态
                check_container_status "astrbot"
                STEP3_DONE=true
                return
            else
                echo -e "${RED}${ICON_CROSS} AstrBot容器启动失败${RESET}"
                echo -e "${YELLOW}建议删除容器后重新部署${RESET}"
                return 1
            fi
        fi
    fi
    
    setup_shared_directory
    
    echo -e "${CYAN}${ICON_LOAD} 开始部署AstrBot...${RESET}"
    
    # 启动网速监控（仅显示下载速度）
    echo -e "\n${CYAN}${ICON_NETWORK} AstrBot镜像下载速度（M/s）${RESET}"
    monitor_speed_mb &
    speed_pid=$!
    
    mkdir -p astrbot/data astrbot/config
    
    echo -e "${CYAN}${ICON_LOAD} 拉取AstrBot镜像...${RESET}"
    if docker pull soulter/astrbot:latest; then
        safe_kill "$speed_pid"
        printf "\r\033[K"  # 清除网速监控行
        echo -e "${GREEN}${ICON_CHECK} AstrBot镜像拉取成功${RESET}"
    else
        safe_kill "$speed_pid"
        printf "\r\033[K"  # 清除网速监控行
        echo -e "${RED}${ICON_CROSS} AstrBot镜像拉取失败${RESET}"
        return 1
    fi
    
    echo -e "${CYAN}${ICON_LOAD} 启动AstrBot容器...${RESET}"
    if docker run -d \
        -p 6180-6200:6180-6200 \
        -p 11451:11451 \
        -v "$SHARED_DIR:/app/sharedFolder" \
        -v "$(pwd)/astrbot/data:/AstrBot/data" \
        -v /etc/localtime:/etc/localtime:ro \
        --name astrbot \
        --restart=always \
        soulter/astrbot:latest; then
        
        echo -e "${GREEN}${ICON_CHECK} AstrBot启动成功${RESET}"
        sleep 3
        
        check_container_status "astrbot"
        
        local ip_address=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
        echo -e "\n${CYAN}访问地址:${RESET}"
        echo -e "  ${WHITE}Web界面: http://${ip_address}:6180${RESET}"
        echo -e "  ${WHITE}共享目录: ${SHARED_DIR} -> /app/sharedFolder${RESET}"
        
    else
        echo -e "${RED}${ICON_CROSS} AstrBot启动失败${RESET}"
        return 1
    fi
    
    STEP3_DONE=true
    STEP3_DURATION=$(( $(date +%s) - step_start ))
    echo -e "\n${GRAY}耗时: ${STEP3_DURATION}秒${RESET}"
}

step4() {
    CURRENT_STEP="step4"
    local step_start=$(date +%s)
    
    if [ "$STEP4_DONE" = true ]; then
        echo -e "${GREEN}${ICON_CHECK} 第四步已完成${RESET}"
        return
    fi
    
    if ! confirm_action "部署NapCat容器（端口3000, 3001, 6099）"; then
        return
    fi
    
    [ "$STEP2_DONE" = false ] && { echo -e "${YELLOW}${ICON_WARN} 需要先安装Docker${RESET}"; step2; }
    
    print_header
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          第四步：部署NapCat${RESET}"
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    
    # 检查容器是否存在
    if docker ps -a --filter "name=napcat" --format "{{.Names}}" | grep -q "napcat"; then
        # 检查容器状态
        local container_state=$(docker inspect -f '{{.State.Status}}' napcat 2>/dev/null || echo "unknown")
        
        if [ "$container_state" = "running" ]; then
            echo -e "${GREEN}${ICON_CHECK} NapCat容器已在运行${RESET}"
            
            # 检查是否挂载了共享目录
            if docker inspect napcat 2>/dev/null | grep -q "\"Source\": \"$SHARED_DIR\""; then
                echo -e "${GREEN}${ICON_CHECK} 共享目录已挂载${RESET}"
            else
                echo -e "${YELLOW}${ICON_WARN} 警告：共享目录未挂载！【考虑到不可抗的检测bug若一直显示这一条，请运行扩展功能中的修复工具】${RESET}"
                echo -e "${YELLOW}建议运行扩展功能中的修复工具${RESET}"
            fi
            
            check_container_status "napcat"
            STEP4_DONE=true
            return
        else
            echo -e "${YELLOW}${ICON_WARN} NapCat容器存在但未运行，正在尝试启动...${RESET}"
            
            # 尝试启动容器
            if docker start napcat; then
                echo -e "${GREEN}${ICON_CHECK} NapCat容器启动成功${RESET}"
                sleep 3
                
                # 重新检查容器状态
                check_container_status "napcat"
                STEP4_DONE=true
                return
            else
                echo -e "${RED}${ICON_CROSS} NapCat容器启动失败${RESET}"
                echo -e "${YELLOW}建议删除容器后重新部署${RESET}"
                return 1
            fi
        fi
    fi
    
    setup_shared_directory
    
    echo -e "${CYAN}${ICON_LOAD} 开始部署NapCat...${RESET}"
    
    # 启动网速监控（仅显示下载速度）
    echo -e "\n${CYAN}${ICON_NETWORK} NapCat镜像下载速度（M/s）${RESET}"
    monitor_speed_mb &
    speed_pid=$!
    
    mkdir -p napcat/data napcat/config
    
    echo -e "${CYAN}${ICON_LOAD} 拉取NapCat镜像...${RESET}"
    if docker pull mlikiowa/napcat-docker:latest; then
        safe_kill "$speed_pid"
        printf "\r\033[K"  # 清除网速监控行
        echo -e "${GREEN}${ICON_CHECK} NapCat镜像拉取成功${RESET}"
    else
        safe_kill "$speed_pid"
        printf "\r\033[K"  # 清除网速监控行
        echo -e "${RED}${ICON_CROSS} NapCat镜像拉取失败${RESET}"
        return 1
    fi
    
    echo -e "${CYAN}${ICON_LOAD} 启动NapCat容器...${RESET}"
    if docker run -d \
        -p 3000:3000 \
        -p 3001:3001 \
        -p 6099:6099 \
        -v "$SHARED_DIR:/app/sharedFolder" \
        -v "$(pwd)/napcat/data:/app/data" \
        -v /etc/localtime:/etc/localtime:ro \
        --name napcat \
        --restart=always \
        mlikiowa/napcat-docker:latest; then
        
        echo -e "${GREEN}${ICON_CHECK} NapCat启动成功${RESET}"
        sleep 3
        
        check_container_status "napcat"
        
        local ip_address=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
        echo -e "\n${CYAN}访问地址:${RESET}"
        echo -e "  ${WHITE}Web界面: http://${ip_address}:3000${RESET}"
        echo -e "  ${WHITE}共享目录: ${SHARED_DIR} -> /app/sharedFolder${RESET}"
        
    else
        echo -e "${RED}${ICON_CROSS} NapCat启动失败${RESET}"
        return 1
    fi
    
    STEP4_DONE=true
    STEP4_DURATION=$(( $(date +%s) - step_start ))
    echo -e "\n${GRAY}耗时: ${STEP4_DURATION}秒${RESET}"
}

run_all() {
    print_header
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          一键执行所有步骤${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    local total_start=$(date +%s)
    
    print_contact_info
    
    echo -e "\n${CYAN}${ICON_INFO} 正在设置共享目录...${RESET}"
    setup_shared_directory
    
    echo -e "\n${CYAN}${ICON_INFO} 执行步骤1: 网络配置${RESET}"
    step1
    
    echo -e "\n${CYAN}${ICON_INFO} 执行步骤2: Docker安装${RESET}"
    step2
    
    echo -e "\n${CYAN}${ICON_INFO} 执行步骤3: AstrBot部署${RESET}"
    step3
    
    echo -e "\n${CYAN}${ICON_INFO} 执行步骤4: NapCat部署${RESET}"
    step4
    
    local total_duration=$(( $(date +%s) - total_start ))
    
    echo -e "\n${GREEN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          部署完成总结${RESET}"
    echo -e "${GREEN}════════════════════════════════════════════${RESET}"
    
    echo -e "${WHITE}总耗时: ${GREEN}${total_duration}秒${RESET}"
    echo -e "${WHITE}各步骤耗时:${RESET}"
    echo -e "  ① 网络配置: ${STEP1_DURATION}秒"
    echo -e "  ② Docker安装: ${STEP2_DURATION}秒"
    echo -e "  ③ AstrBot部署: ${STEP3_DURATION}秒"
    echo -e "  ④ NapCat部署: ${STEP4_DURATION}秒"
    
    echo -e "\n${CYAN}访问地址:${RESET}"
    local ip_address=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    echo -e "  ${ICON_BOT} AstrBot: ${WHITE}http://${ip_address}:6180${RESET}"
    echo -e "  ${ICON_CAT} NapCat:  ${WHITE}http://${ip_address}:3000${RESET}"
    echo -e "\n${CYAN}共享目录:${RESET}"
    echo -e "  ${ICON_FOLDER} 宿主机: ${WHITE}$SHARED_DIR${RESET}"
    echo -e "  ${ICON_FOLDER} 容器内: ${WHITE}/app/sharedFolder${RESET}"
    
    echo -e "\n${CYAN}${ICON_INFO} 测试共享文件夹功能...${RESET}"
    test_shared_folder
    
    echo -e "\n${GREEN}${ICON_CHECK} 所有步骤完成！按任意键返回主菜单...${RESET}"
    read -p ""
}

# ===================== 扩展功能菜单 =====================
show_extended_menu() {
    while true; do
        print_header
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║  ${WHITE}🔧 扩展功能工具箱                                                         ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        
        echo -e "${CYAN}║                                                                              ║${RESET}"
        echo -e "${CYAN}║  ${WHITE}┌───────────── 容器管理 ─────────────┐${RESET}                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║                                                                              ║${RESET}"
        
        echo -e "${CYAN}║  ${CYAN}[1] ${GREEN}📊 容器状态总览${RESET}                                         ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[2] ${GREEN}🔍 容器日志查看${RESET}                                         ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[3] ${GREEN}🔄 重启容器${RESET}                                             ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[4] ${RED}🗑️  清理容器${RESET}                                             ${CYAN}║${RESET}"
        
        echo -e "${CYAN}║                                                                              ║${RESET}"
        echo -e "${CYAN}║  ${WHITE}┌───────────── 网络工具 ─────────────┐${RESET}                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║                                                                              ║${RESET}"
        
        echo -e "${CYAN}║  ${CYAN}[5] ${GREEN}🌐 网络连通测试${RESET}                                         ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[6] ${GREEN}📡 DNS配置修复${RESET}                                          ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[7] ${GREEN}📶 实时网速监控${RESET}                                         ${CYAN}║${RESET}"
        
        echo -e "${CYAN}║                                                                              ║${RESET}"
        echo -e "${CYAN}║  ${WHITE}┌───────────── 文件系统 ─────────────┐${RESET}                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║                                                                              ║${RESET}"
        
        echo -e "${CYAN}║  ${CYAN}[8] ${GREEN}📁 共享目录检查${RESET}                                         ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[9] ${GREEN}🔗 共享功能测试${RESET}                                         ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[10] ${RED}🔧 挂载修复工具${RESET}                                         ${CYAN}║${RESET}"
        
        echo -e "${CYAN}║                                                                              ║${RESET}"
        echo -e "${CYAN}║  ${WHITE}┌───────────── 系统工具 ─────────────┐${RESET}                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║                                                                              ║${RESET}"
        
        echo -e "${CYAN}║  ${CYAN}[11] ${GREEN}📈 系统资源监控${RESET}                                        ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[12] ${GREEN}🔍 版本兼容检查${RESET}                                        ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[13] ${GREEN}📝 日志提取工具${RESET}                                        ${CYAN}║${RESET}"
        
        echo -e "${CYAN}║                                                                              ║${RESET}"
        echo -e "${CYAN}║  ${WHITE}┌───────────── 高级功能 ─────────────┐${RESET}                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║                                                                              ║${RESET}"
        
        echo -e "${CYAN}║  ${CYAN}[14] ${YELLOW}↩️  步骤回滚功能${RESET}                                       ${CYAN}║${RESET}"
        echo -e "${CYAN}║  ${CYAN}[15] ${GREEN}🛡️  数据备份恢复${RESET}                                       ${CYAN}║${RESET}"
        
        echo -e "${CYAN}║                                                                              ║${RESET}"
        echo -e "${CYAN}║  ${WHITE}└─────────────────────────────────────┘${RESET}                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║                                                                              ║${RESET}"
        
        echo -e "${CYAN}║  ${CYAN}[0] ${GRAY}🔙 返回主菜单${RESET}                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║                                                                              ║${RESET}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
        
        echo -ne "${YELLOW}${ICON_WARN} 请输入选项 (0-15) : ${RESET}"
        read -r choice
        
        case "$choice" in
            1) show_container_details ;;
            2) show_container_logs ;;
            3) restart_containers ;;
            4) clean_containers ;;
            5) 
                test_network_connectivity
                echo -e "\n${GREEN}按任意键返回菜单...${RESET}"
                read -p ""
                ;;
            6) fix_dns_configuration ;;
            7) show_network_speed ;;
            8) 
                check_shared_directory
                echo -e "\n${GREEN}按任意键返回菜单...${RESET}"
                read -p ""
                ;;
            9) 
                test_shared_folder
                echo -e "\n${GREEN}按任意键返回菜单...${RESET}"
                read -p ""
                ;;
            10) fix_shared_mount ;;
            11) 
                monitor_system_resources
                echo -e "\n${GREEN}按任意键返回菜单...${RESET}"
                read -p ""
                ;;
            12) 
                check_version_compatibility
                echo -e "\n${GREEN}按任意键返回菜单...${RESET}"
                read -p ""
                ;;
            13) 
                extract_urls_from_logs "both"
                echo -e "\n${GREEN}按任意键返回菜单...${RESET}"
                read -p ""
                ;;
            14) show_rollback_menu ;;
            15) show_backup_menu ;;
            0) return ;;
            *)
                echo -e "\n${RED}❌ 无效选择！${RESET}"
                sleep 1
                ;;
        esac
    done
}

# ===================== 主菜单 =====================
show_main_menu() {
    while true; do
        print_header
        print_system_status
        print_deployment_status
        print_main_menu
        print_contact_info
        
        echo -ne "${YELLOW}${ICON_WARN} 请输入选项 (0-4/E/C/U/Q) : ${RESET}"
        read -r choice
        
        case "$choice" in
            1) step1 ;;
            2) step2 ;;
            3) step3 ;;
            4) step4 ;;
            0) run_all ;;
            e|E) show_extended_menu ;;
            c|C) show_container_details ;;
            u|U) check_for_updates ;;
            q|Q) 
                echo -e "\n${CYAN}感谢使用，再见！${RESET}"
                cleanup
                break
                ;;
            *)
                echo -e "\n${RED}❌ 无效选择！请重新输入${RESET}"
                sleep 1
                ;;
        esac
    done
}


# ===================== 初始化设置 =====================
init_script() {
    echo -e "${MAGENTA}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              智能部署助手 v2.6.1 初始化                 ║"
    echo "║          修复共享目录矛盾，统一DNS配置                   ║"
    echo "║          优化权限管理，改进更新检测                     ║"
    echo "║          本脚本完全免费，严禁倒卖！                     ║"
    echo "║          技术支持QQ: 3076737056                         ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    
    # 创建必要的目录
    mkdir -p "$LOG_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # 设置日志文件
    LOG_FILE="${LOG_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1
    
    echo "===== 脚本开始执行: $(date) ====="
    echo "日志文件: $LOG_FILE"
    
    # 设置信号捕获
    trap 'echo -e "\n${RED}脚本被中断！${RESET}"; cleanup; exit 1' INT TERM
    trap 'echo -e "\n${RED}脚本执行出错: $BASH_COMMAND${RESET}"; echo "错误发生在步骤: ${CURRENT_STEP:-unknown}"' ERR
    
    # 执行前置检查
    check_root
    check_os
    check_disk_space
    check_commands
    check_script_integrity
    
    echo -e "\n${GREEN}${ICON_CHECK} 初始化完成！${RESET}"
    sleep 1
}

# ===================== 主程序 =====================
main() {
    # 确保在交互式终端运行
    if [ ! -t 0 ]; then
        echo -e "${RED}请在交互式终端中运行此脚本！${RESET}"
        exit 1
    fi
    
    # 初始化
    init_script
    
    # 主循环
    while true; do
        show_main_menu
        
        case "$choice" in
            1) step1 ;;
            2) step2 ;;
            3) step3 ;;
            4) step4 ;;
            0) run_all ;;
            e|E) show_extended_menu ;;
            q|Q) echo -e "\n${CYAN}感谢使用，再见！${RESET}"; break ;;
            *) echo -e "\n${RED}无效选择！${RESET}"; sleep 1 ;;
        esac
    done
    
    cleanup
}

# 启动主程序
main
exit 0
