#!/bin/bash
# ===================== 版本信息 =====================
# 脚本名称: AstrBot+NapCat 智能部署助手
# 版本号: v2.8.0
# 最后更新: 2025年12月27日
# 功能: 修复UI布局问题，优化状态检测逻辑，改进菜单体验
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
CURRENT_VERSION="v2.8.0"

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
ICON_PLUGIN="🔌"
ICON_SCREEN="📺"
ICON_LAYOUT="📐"
ICON_STATUS="📊"
ICON_MENU="📱"

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

# ===================== UI配置 =====================
# 屏幕尺寸检测
TERM_COLS=$(tput cols 2>/dev/null || echo 80)
TERM_LINES=$(tput lines 2>/dev/null || echo 24)

# UI模式：wide（宽屏）或narrow（窄屏）
UI_MODE="auto"
if [ "$TERM_COLS" -ge 120 ]; then
    UI_MODE="wide"
elif [ "$TERM_COLS" -lt 80 ]; then
    UI_MODE="narrow"
else
    UI_MODE="normal"
fi

# UI宽度设置
if [ "$UI_MODE" = "wide" ]; then
    UI_WIDTH=120
    MENU_COLS=2
elif [ "$UI_MODE" = "normal" ]; then
    UI_WIDTH=100
    MENU_COLS=1
else
    UI_WIDTH=80
    MENU_COLS=1
fi

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
            timeout 10 docker logs astrbot --tail=20 2>/dev/null || echo -e "${YELLOW}无法获取AstrBot日志${RESET}"
            ;;
        2)
            echo -e "\n${CYAN}正在获取NapCat日志...${RESET}"
            timeout 10 docker logs napcat --tail=20 2>/dev/null || echo -e "${YELLOW}无法获取NapCat日志${RESET}"
            ;;
        3)
            echo -e "\n${CYAN}AstrBot日志:${RESET}"
            timeout 5 docker logs astrbot --tail=10 2>/dev/null || echo -e "${YELLOW}无法获取AstrBot日志${RESET}"
            echo -e "\n${CYAN}NapCat日志:${RESET}"
            timeout 5 docker logs napcat --tail=10 2>/dev/null || echo -e "${YELLOW}无法获取NapCat日志${RESET}"
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

show_backup_menu() {
    while true; do
        print_header
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║  ${WHITE}🛡️  数据备份恢复                                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
        
        echo -e "\n选择操作："
        echo -e "  ${CYAN}[1] 创建备份${RESET}"
        echo -e "  ${CYAN}[2] 恢复备份${RESET}"
        echo -e "  ${CYAN}[3] 查看备份列表${RESET}"
        echo -e "  ${CYAN}[4] 备份插件配置${RESET}"
        echo -e "  ${CYAN}[0] 返回${RESET}"
        
        echo -ne "${YELLOW}请选择: ${RESET}"
        read -r backup_choice
        
        case "$backup_choice" in
            1)
                create_backup
                ;;
            2)
                restore_backup
                ;;
            3)
                list_backups
                ;;
            4)
                backup_plugins
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选择${RESET}"
                ;;
        esac
        
        echo -e "\n${GREEN}按任意键继续...${RESET}"
        read -p ""
    done
}

create_backup() {
    local backup_dir="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    echo -e "\n${CYAN}正在创建完整备份...${RESET}"
    
    # 备份容器配置
    docker inspect astrbot > "$backup_dir/astrbot.json" 2>/dev/null
    docker inspect napcat > "$backup_dir/napcat.json" 2>/dev/null
    
    # 备份数据目录
    if [ -d "astrbot/data" ]; then
        cp -r astrbot/data "$backup_dir/astrbot_data"
    fi
    
    if [ -d "napcat/data" ]; then
        cp -r napcat/data "$backup_dir/napcat_data"
    fi
    
    # 备份插件和配置文件
    echo -e "${CYAN}备份插件配置...${RESET}"
    
    # AstrBot插件备份
    if docker ps --filter "name=astrbot" --format "{{.Names}}" | grep -q "astrbot"; then
        echo -e "${CYAN}备份AstrBot插件...${RESET}"
        docker exec astrbot bash -c "cp -r /AstrBot/plugins $backup_dir/astrbot_plugins" 2>/dev/null || true
        docker exec astrbot bash -c "cp -r /AstrBot/config $backup_dir/astrbot_config" 2>/dev/null || true
    fi
    
    # NapCat插件备份
    if docker ps --filter "name=napcat" --format "{{.Names}}" | grep -q "napcat"; then
        echo -e "${CYAN}备份NapCat插件...${RESET}"
        docker exec napcat bash -c "cp -r /app/plugins $backup_dir/napcat_plugins" 2>/dev/null || true
        docker exec napcat bash -c "cp -r /app/config $backup_dir/napcat_config" 2>/dev/null || true
    fi
    
    # 备份共享目录中的关键文件
    if [ -d "$SHARED_DIR" ]; then
        find "$SHARED_DIR" -type f \( -name "*.json" -o -name "*.yml" -o -name "*.yaml" -o -name "*.txt" -o -name "*.conf" \) | \
            head -50 | xargs -I {} cp --parents {} "$backup_dir/" 2>/dev/null || true
    fi
    
    # 创建备份信息文件
    cat > "$backup_dir/backup_info.txt" << EOF
备份时间: $(date)
脚本版本: $CURRENT_VERSION
系统信息: $(uname -a)
包含内容:
  - AstrBot容器配置
  - NapCat容器配置
  - AstrBot数据目录
  - NapCat数据目录
  - AstrBot插件目录
  - NapCat插件目录
  - 共享目录配置文件
备份命令: $(basename "$0") --restore $backup_dir
EOF
    
    echo -e "${GREEN}✅ 备份创建完成: $backup_dir${RESET}"
    local size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "未知")
    echo -e "${GRAY}备份大小: ${size}${RESET}"
    
    # 显示备份内容
    echo -e "\n${CYAN}备份内容:${RESET}"
    find "$backup_dir" -type f | sed "s|$backup_dir/|  📄 |" | head -20
    local file_count=$(find "$backup_dir" -type f | wc -l)
    echo -e "${GRAY}总文件数: ${file_count}个${RESET}"
}

restore_backup() {
    echo -e "\n${CYAN}选择要恢复的备份:${RESET}"
    
    # 获取备份列表
    local backups=()
    local i=1
    
    if [ -d "$BACKUP_DIR" ]; then
        for dir in "$BACKUP_DIR"/backup_*; do
            if [ -d "$dir" ]; then
                backups[$i]="$dir"
                local date_str=$(basename "$dir" | sed 's/backup_//')
                local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "未知")
                echo -e "  ${CYAN}[$i] ${dir}${RESET} (${size})"
                ((i++))
            fi
        done
    fi
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${YELLOW}暂无备份${RESET}"
        return
    fi
    
    echo -e "  ${CYAN}[0] 取消${RESET}"
    
    echo -ne "\n${YELLOW}请选择备份编号: ${RESET}"
    read -r backup_num
    
    if [ "$backup_num" = "0" ] || [ -z "${backups[$backup_num]}" ]; then
        echo -e "${GRAY}已取消${RESET}"
        return
    fi
    
    local backup_path="${backups[$backup_num]}"
    
    if ! confirm_action "恢复备份 $(basename "$backup_path")"; then
        return
    fi
    
    echo -e "\n${CYAN}正在恢复备份...${RESET}"
    
    # 恢复AstrBot数据
    if [ -d "$backup_path/astrbot_data" ]; then
        echo -e "${CYAN}恢复AstrBot数据...${RESET}"
        mkdir -p "astrbot/data"
        cp -r "$backup_path/astrbot_data"/* "astrbot/data/" 2>/dev/null || true
    fi
    
    # 恢复NapCat数据
    if [ -d "$backup_path/napcat_data" ]; then
        echo -e "${CYAN}恢复NapCat数据...${RESET}"
        mkdir -p "napcat/data"
        cp -r "$backup_path/napcat_data"/* "napcat/data/" 2>/dev/null || true
    fi
    
    # 恢复插件
    if [ -d "$backup_path/astrbot_plugins" ]; then
        echo -e "${CYAN}恢复AstrBot插件...${RESET}"
        if docker ps --filter "name=astrbot" --format "{{.Names}}" | grep -q "astrbot"; then
            docker exec astrbot bash -c "cp -r $backup_path/astrbot_plugins/* /AstrBot/plugins/" 2>/dev/null || true
        fi
    fi
    
    if [ -d "$backup_path/napcat_plugins" ]; then
        echo -e "${CYAN}恢复NapCat插件...${RESET}"
        if docker ps --filter "name=napcat" --format "{{.Names}}" | grep -q "napcat"; then
            docker exec napcat bash -c "cp -r $backup_path/napcat_plugins/* /app/plugins/" 2>/dev/null || true
        fi
    fi
    
    echo -e "${GREEN}✅ 备份恢复完成${RESET}"
    echo -e "${YELLOW}注意：需要重启容器以使配置生效${RESET}"
}

list_backups() {
    echo -e "\n${CYAN}备份列表:${RESET}"
    if [ -d "$BACKUP_DIR" ]; then
        local count=0
        find "$BACKUP_DIR" -name "backup_*" -type d | sort -r | while read dir; do
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "未知")
            local date_str=$(basename "$dir" | sed 's/backup_//')
            local file_count=$(find "$dir" -type f 2>/dev/null | wc -l || echo "0")
            ((count++))
            echo -e "  ${CYAN}📁 ${dir}${RESET}"
            echo -e "     ${GRAY}大小: ${size} | 文件: ${file_count}个 | 日期: ${date_str}${RESET}"
        done
        
        if [ "$count" -eq 0 ]; then
            echo -e "${YELLOW}暂无备份${RESET}"
        fi
    else
        echo -e "${YELLOW}暂无备份${RESET}"
    fi
}

backup_plugins() {
    echo -e "\n${CYAN}${ICON_PLUGIN} 插件专用备份${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    local backup_dir="$BACKUP_DIR/plugins_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    echo -e "备份目标目录: $backup_dir"
    
    # 备份AstrBot插件
    echo -e "\n${CYAN}备份AstrBot插件...${RESET}"
    if docker ps --filter "name=astrbot" --format "{{.Names}}" | grep -q "astrbot"; then
        if docker exec astrbot bash -c "ls /AstrBot/plugins/" >/dev/null 2>&1; then
            docker cp astrbot:/AstrBot/plugins "$backup_dir/astrbot_plugins" 2>/dev/null
            echo -e "${GREEN}✅ AstrBot插件备份完成${RESET}"
            
            # 列出备份的插件
            local plugin_count=$(find "$backup_dir/astrbot_plugins" -name "*.py" -o -name "*.json" 2>/dev/null | wc -l)
            echo -e "${GRAY}  插件数量: ${plugin_count}个${RESET}"
        else
            echo -e "${YELLOW}⚠️  AstrBot插件目录不存在${RESET}"
        fi
    else
        echo -e "${YELLOW}⚠️  AstrBot容器未运行${RESET}"
    fi
    
    # 备份NapCat插件
    echo -e "\n${CYAN}备份NapCat插件...${RESET}"
    if docker ps --filter "name=napcat" --format "{{.Names}}" | grep -q "napcat"; then
        if docker exec napcat bash -c "ls /app/plugins/" >/dev/null 2>&1; then
            docker cp napcat:/app/plugins "$backup_dir/napcat_plugins" 2>/dev/null
            echo -e "${GREEN}✅ NapCat插件备份完成${RESET}"
            
            # 列出备份的插件
            local plugin_count=$(find "$backup_dir/napcat_plugins" -name "*.js" -o -name "*.json" 2>/dev/null | wc -l)
            echo -e "${GRAY}  插件数量: ${plugin_count}个${RESET}"
        else
            echo -e "${YELLOW}⚠️  NapCat插件目录不存在${RESET}"
        fi
    else
        echo -e "${YELLOW}⚠️  NapCat容器未运行${RESET}"
    fi
    
    # 备份配置
    echo -e "\n${CYAN}备份配置文件...${RESET}"
    
    # AstrBot配置
    if docker ps --filter "name=astrbot" --format "{{.Names}}" | grep -q "astrbot"; then
        docker exec astrbot bash -c "find /AstrBot -name '*.json' -o -name '*.yml' -o -name '*.yaml'" 2>/dev/null | head -20 | while read -r config_file; do
            local dest_path="$backup_dir/astrbot_config${config_file#/AstrBot}"
            mkdir -p "$(dirname "$dest_path")"
            docker exec astrbot bash -c "cat '$config_file'" > "$dest_path" 2>/dev/null && \
                echo -e "${GRAY}  已备份: ${config_file}${RESET}"
        done
    fi
    
    # NapCat配置
    if docker ps --filter "name=napcat" --format "{{.Names}}" | grep -q "napcat"; then
        docker exec napcat bash -c "find /app -name '*.json' -o -name '*.yml' -o -name '*.yaml'" 2>/dev/null | head -20 | while read -r config_file; do
            local dest_path="$backup_dir/napcat_config${config_file#/app}"
            mkdir -p "$(dirname "$dest_path")"
            docker exec napcat bash -c "cat '$config_file'" > "$dest_path" 2>/dev/null && \
                echo -e "${GRAY}  已备份: ${config_file}${RESET}"
        done
    fi
    
    # 创建备份信息
    cat > "$backup_dir/backup_info.txt" << EOF
插件备份信息
备份时间: $(date)
脚本版本: $CURRENT_VERSION
备份内容:
  - AstrBot插件目录
  - NapCat插件目录
  - AstrBot配置文件
  - NapCat配置文件
恢复方法:
  1. 停止容器: docker stop astrbot napcat
  2. 复制文件: docker cp 备份目录/astrbot_plugins astrbot:/AstrBot/plugins
  3. 重启容器: docker start astrbot napcat
EOF
    
    local total_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "未知")
    local total_files=$(find "$backup_dir" -type f 2>/dev/null | wc -l || echo "0")
    
    echo -e "\n${GREEN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          插件备份完成${RESET}"
    echo -e "${GREEN}════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}备份目录: ${WHITE}$backup_dir${RESET}"
    echo -e "${CYAN}总大小: ${WHITE}${total_size}${RESET}"
    echo -e "${CYAN}文件数量: ${WHITE}${total_files}个${RESET}"
    echo -e "\n${YELLOW}⚠️  重要：请妥善保管备份文件${RESET}"
}

confirm_action() {
    local action_desc="$1"
    local default="${2:-Y}"
    
    echo ""
    echo -ne "${YELLOW}${ICON_WARN} 即将执行：${action_desc}，是否继续？[Y/n]: ${RESET}"
    read -r confirm
    confirm=${confirm:-$default}
    
    if [[ "$confirm" =~ ^[Yy]$ ]] || [ -z "$confirm" ]; then
        return 0
    else
        echo -e "${GRAY}操作已取消${RESET}"
        return 1
    fi
}

safe_kill() {
    local pid=$1
    if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
        kill "$pid" >/dev/null 2>&1
        sleep 0.5
        if ps -p "$pid" >/dev/null 2>&1; then
            kill -9 "$pid" >/dev/null 2>&1
        fi
    fi
}

monitor_speed_mb() {
    echo -e "\n${CYAN}${ICON_NETWORK} 实时网速监控（M/s）${RESET}"
    echo -e "${GRAY}按任意键停止监控${RESET}"
    
    if [ -f "/sys/class/net/${DEFAULT_IFACE}/statistics/rx_bytes" ]; then
        local initial_rx=$(cat /sys/class/net/${DEFAULT_IFACE}/statistics/rx_bytes 2>/dev/null || echo 0)
        local initial_tx=$(cat /sys/class/net/${DEFAULT_IFACE}/statistics/tx_bytes 2>/dev/null || echo 0)
        
        # 设置超时机制
        local timeout=300  # 5分钟超时
        local start_time=$(date +%s)
        
        while true; do
            # 检查是否超时
            local current_time=$(date +%s)
            if [ $((current_time - start_time)) -gt $timeout ]; then
                echo -e "\n${YELLOW}监控超时，自动停止${RESET}"
                break
            fi
            
            # 检查是否有按键输入（非阻塞）
            read -t 1 -n 1 && break
            
            sleep 1
            local current_rx=$(cat /sys/class/net/${DEFAULT_IFACE}/statistics/rx_bytes 2>/dev/null || echo 0)
            local current_tx=$(cat /sys/class/net/${DEFAULT_IFACE}/statistics/tx_bytes 2>/dev/null || echo 0)
            
            local rx_speed=$(echo "scale=2; ($current_rx - $initial_rx) / 1024 / 1024" | bc 2>/dev/null || echo "0.00")
            local tx_speed=$(echo "scale=2; ($current_tx - $initial_tx) / 1024 / 1024" | bc 2>/dev/null || echo "0.00")
            
            printf "\r${GREEN}↓ ${rx_speed:0:6} M/s ${RESET}| ${BLUE}↑ ${tx_speed:0:6} M/s${RESET} ${GRAY}[按任意键停止]${RESET}"
            
            initial_rx=$current_rx
            initial_tx=$current_tx
        done
    else
        echo -e "${YELLOW}${ICON_WARN} 无法获取网卡信息，跳过网速监控！${RESET}"
    fi
    printf "\r\033[K"
    echo -e "${GREEN}网速监控已停止${RESET}"
}

# ===================== 修复的日志提取函数 =====================
extract_urls_from_logs() {
    local target=${1:-"both"}  # 默认为both，同时提取两个容器的日志
    local urls=""
    local temp_file="/tmp/url_extract_$(date +%s).txt"
    
    echo -e "\n${CYAN}正在提取URL...${RESET}"
    
    # 创建日志输出文件
    local log_output_file="${LOG_DIR}/full_logs_$(date +%Y%m%d_%H%M%S).txt"
    
    if [ "$target" = "both" ] || [ "$target" = "astrbot" ]; then
        if docker ps -a --format "{{.Names}}" | grep -q "^astrbot$"; then
            echo -e "${CYAN}提取AstrBot日志（读取8000行）...${RESET}"
            # 读取8000行日志并保存完整日志
            timeout 30 docker logs astrbot --tail=8000 2>/dev/null > "${log_output_file}.astrbot"
            
            # 从完整日志中提取URL
            echo -e "${CYAN}从AstrBot日志中提取URL（包含6185）...${RESET}"
            cat "${log_output_file}.astrbot" 2>/dev/null | \
                grep -Eo 'https?://[^[:space:]]*6185[^[:space:]]*' | \
                sort -u | while read -r url; do
                    echo "$url" >> "$temp_file"
                done
            
            # 显示统计信息
            local line_count=$(wc -l < "${log_output_file}.astrbot" 2>/dev/null || echo 0)
            echo -e "${GRAY}读取了 ${line_count} 行AstrBot日志${RESET}"
        else
            echo -e "${YELLOW}AstrBot容器不存在，跳过${RESET}"
        fi
    fi
    
    if [ "$target" = "both" ] || [ "$target" = "napcat" ]; then
        if docker ps -a --format "{{.Names}}" | grep -q "^napcat$"; then
            echo -e "${CYAN}提取NapCat日志（读取8000行）...${RESET}"
            # 读取8000行日志并保存完整日志
            timeout 30 docker logs napcat --tail=8000 2>/dev/null > "${log_output_file}.napcat"
            
            # 从完整日志中提取URL
            echo -e "${CYAN}从NapCat日志中提取URL（包含token或6099）...${RESET}"
            cat "${log_output_file}.napcat" 2>/dev/null | \
                grep -Eo 'https?://[^[:space:]]*(token|6099)[^[:space:]]*' | \
                sort -u | while read -r url; do
                    echo "$url" >> "$temp_file"
                done
            
            # 显示统计信息
            local line_count=$(wc -l < "${log_output_file}.napcat" 2>/dev/null || echo 0)
            echo -e "${GRAY}读取了 ${line_count} 行NapCat日志${RESET}"
        else
            echo -e "${YELLOW}NapCat容器不存在，跳过${RESET}"
        fi
    fi
    
    if [ -s "$temp_file" ]; then
        local url_file="${LOG_DIR}/extracted_urls_$(date +%Y%m%d_%H%M%S).txt"
        cp "$temp_file" "$url_file"
        
        echo -e "\n${GREEN}✅ 提取到的URL:${RESET}"
        cat "$temp_file"
        echo -e "\n${GREEN}✅ URL已保存到: $url_file${RESET}"
        
        # 显示统计信息
        local count=$(wc -l < "$temp_file")
        echo -e "${GRAY}共提取到 ${count} 个URL${RESET}"
        
        # 显示日志文件位置
        echo -e "${CYAN}完整日志文件:${RESET}"
        if [ -f "${log_output_file}.astrbot" ]; then
            echo -e "  AstrBot: ${log_output_file}.astrbot"
        fi
        if [ -f "${log_output_file}.napcat" ]; then
            echo -e "  NapCat: ${log_output_file}.napcat"
        fi
    else
        echo -e "${YELLOW}⚠️  未找到符合条件的URL${RESET}"
        echo -e "${GRAY}可能原因："
        echo -e "  1. 容器没有运行"
        echo -e "  2. 没有符合条件的URL"
        echo -e "  3. 日志中没有URL信息${RESET}"
        
        # 显示一些日志样本帮助调试
        echo -e "\n${CYAN}最近日志样本（最后5行）:${RESET}"
        if [ "$target" = "both" ] || [ "$target" = "astrbot" ]; then
            if docker ps -a --format "{{.Names}}" | grep -q "^astrbot$"; then
                echo -e "${CYAN}AstrBot日志样本:${RESET}"
                timeout 5 docker logs astrbot --tail=5 2>/dev/null || echo "  无法获取日志"
            fi
        fi
        if [ "$target" = "both" ] || [ "$target" = "napcat" ]; then
            if docker ps -a --format "{{.Names}}" | grep -q "^napcat$"; then
                echo -e "${CYAN}NapCat日志样本:${RESET}"
                timeout 5 docker logs napcat --tail=5 2>/dev/null || echo "  无法获取日志"
            fi
        fi
    fi
    
    rm -f "$temp_file"
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
        if timeout 5 ping -c 1 -W 2 "$host" &>/dev/null; then
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
        local size=$(du -sh "$SHARED_DIR" 2>/dev/null | awk '{print $1}' || echo "未知")
        local file_count=$(find "$SHARED_DIR" -type f 2>/dev/null | wc -l || echo "0")
        
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
            done || echo "  无法列出文件"
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
    local test_content="这是挂载测试文件 - $(date)"
    
    echo -e "${WHITE}在宿主机创建测试文件...${RESET}"
    echo "$test_content" > "$test_file"
    echo -e "${GREEN}${ICON_CHECK} 测试文件已创建: $(basename "$test_file")${RESET}"
    
    local napcat_ok=false
    local astrbot_ok=false
    
    # 测试NapCat
    if $napcat_exists; then
        echo -e "\n${WHITE}测试NapCat容器读取...${RESET}"
        if timeout 5 docker exec napcat test -f "/app/sharedFolder/$(basename "$test_file")" 2>/dev/null; then
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
        if timeout 5 docker exec astrbot test -f "/app/sharedFolder/$(basename "$test_file")" 2>/dev/null; then
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
    
    # 备份重要数据
    echo -e "\n${YELLOW}${ICON_WARN} 备份容器数据...${RESET}"
    local backup_dir="/tmp/container_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    if $astrbot_running; then
        timeout 30 docker cp astrbot:/AstrBot/data "$backup_dir/astrbot_data" 2>/dev/null || true
        timeout 30 docker cp astrbot:/AstrBot/plugins "$backup_dir/astrbot_plugins" 2>/dev/null || true
        docker inspect astrbot > "$backup_dir/astrbot.json" 2>/dev/null
    fi
    
    if $napcat_running; then
        timeout 30 docker cp napcat:/app/data "$backup_dir/napcat_data" 2>/dev/null || true
        timeout 30 docker cp napcat:/app/plugins "$backup_dir/napcat_plugins" 2>/dev/null || true
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
    echo -e "${GRAY}$(cat /etc/resolv.conf 2>/dev/null | head -10)${RESET}"
    
    echo -e "\n${WHITE}测试DNS解析...${RESET}"
    local test_domains=("google.com" "baidu.com" "github.com" "qq.com")
    local success_count=0
    
    for domain in "${test_domains[@]}"; do
        echo -n "解析 $domain ... "
        if timeout 5 dig "$domain" +short 2>/dev/null | grep -q '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'; then
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
                update_script_auto "$remote_version"
                ;;
            2)
                show_update_changelog "$remote_version"
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
    local remote_version="$1"
    
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
    local remote_version="$1"
    
    echo -e "\n${CYAN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}           更新日志${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    echo -e "${GREEN}v2.8.0 (2025-12-27)${RESET}"
    echo -e "  • 修复宽屏UI布局问题，系统状态和部署进度并排显示"
    echo -e "  • 添加自动检测已部署组件功能"
    echo -e "  • 优化核心部署选项的检测逻辑"
    echo -e "  • 改进按键提示和用户体验"
    echo -e "  • 修正部署进度状态的检测逻辑"
   
    echo -e "${GREEN}v2.7.0 (2025-12-27)${RESET}"
    echo -e "  • 修复日志提取功能，改为读取8000行日志"
    echo -e "  • 添加屏幕分辨率检测和宽屏UI支持"
    echo -e "  • 优化UI布局，支持用户手动切换界面"
    echo -e "  • 改进菜单显示，充分利用屏幕空间"
   
    echo -e "${GREEN}v2.6.0 (2025-12-26)${RESET}"
    echo -e "  • 修复日志提取功能，只提取特定格式URL"
    echo -e "  • 优化主菜单布局，充分利用屏幕空间"
    echo -e "  • 完善备份功能，备份插件和配置文件"
    echo -e "  • 添加超时机制防止脚本卡死"
    echo -e "  • 优化系统监控和资源显示"
   
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

# ===================== 自动检测部署状态 =====================
detect_deployment_status() {
    echo -e "${CYAN}${ICON_INFO} 正在检测当前部署状态...${RESET}"
    
    # 检测步骤1：网络连通性
    if test_network_connectivity >/dev/null 2>&1; then
        STEP1_DONE=true
        STEP1_DURATION=1  # 标记已通过
    else
        STEP1_DONE=false
    fi
    
    # 检测步骤2：Docker安装
    if command -v docker &>/dev/null; then
        STEP2_DONE=true
        STEP2_DURATION=1
    else
        STEP2_DONE=false
    fi
    
    # 检测步骤3：AstrBot容器
    if docker ps -a --format "{{.Names}}" | grep -q "^astrbot$"; then
        local astro_state=$(timeout 2 docker inspect -f '{{.State.Status}}' astrbot 2>/dev/null || echo "unknown")
        if [ "$astro_state" = "running" ]; then
            STEP3_DONE=true
            STEP3_DURATION=1
        else
            STEP3_DONE=false
        fi
    else
        STEP3_DONE=false
    fi
    
    # 检测步骤4：NapCat容器
    if docker ps -a --format "{{.Names}}" | grep -q "^napcat$"; then
        local napcat_state=$(timeout 2 docker inspect -f '{{.State.Status}}' napcat 2>/dev/null || echo "unknown")
        if [ "$napcat_state" = "running" ]; then
            STEP4_DONE=true
            STEP4_DURATION=1
        else
            STEP4_DONE=false
        fi
    else
        STEP4_DONE=false
    fi
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
    echo -e "${MAGENTA}║  ${WHITE}                N a p C a t  智能部署助手  v2.8.0                  ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║  ${GRAY}       修复UI布局 | 自动状态检测 | 优化核心部署逻辑               ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║                                                                              ║${RESET}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_system_status() {
    # 获取系统信息
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "0")
    local mem_total=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
    local mem_used=$(free -h 2>/dev/null | awk '/^Mem:/{print $3}' || echo "0")
    local mem_percent=$(free 2>/dev/null | awk '/^Mem:/{print $3/$2*100}' || echo "0")
    local disk_total=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "0")
    local disk_used=$(df -h / 2>/dev/null | awk 'NR==2 {print $3}' || echo "0")
    local disk_percent=$(df / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || echo "0")
    local load_avg=$(cat /proc/loadavg 2>/dev/null | awk '{print $1", "$2", "$3}' || echo "未知")
    
    # 进度条函数
    progress_bar() {
        local value=$1
        local max=100
        local bar_width=20
        local filled=$((value * bar_width / max))
        local empty=$((bar_width - filled))
        
        printf "["
        for ((i=0; i<filled; i++)); do printf "█"; done
        for ((i=0; i<empty; i++)); do printf " "; done
        printf "] %3d%%" "$value"
    }
    
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║  ${WHITE}📊 系统状态监控                                                          ${CYAN}║${RESET}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    # CPU使用率
    local cpu_color=$([ "${cpu_usage%.*}" -gt 80 ] && echo "$RED" || ([ "${cpu_usage%.*}" -gt 50 ] && echo "$YELLOW" || echo "$GREEN"))
    echo -e "${CYAN}║  ${WHITE}🖥  CPU使用率: ${cpu_color}$(progress_bar ${cpu_usage%.*})${RESET}"
    
    # 内存使用
    local mem_color=$([ "${mem_percent%.*}" -gt 80 ] && echo "$RED" || ([ "${mem_percent%.*}" -gt 50 ] && echo "$YELLOW" || echo "$GREEN"))
    echo -e "${CYAN}║  ${WHITE}💾  内存使用: ${mem_color}$(progress_bar ${mem_percent%.*})${RESET} ${mem_used}/${mem_total}"
    
    # 磁盘使用
    local disk_color=$([ "$disk_percent" -gt 80 ] && echo "$RED" || ([ "$disk_percent" -gt 50 ] && echo "$YELLOW" || echo "$GREEN"))
    echo -e "${CYAN}║  ${WHITE}💿  磁盘使用: ${disk_color}$(progress_bar $disk_percent)${RESET} ${disk_used}/${disk_total}"
    
    # 负载
    echo -e "${CYAN}║  ${WHITE}📈  系统负载: ${load_avg}${RESET}"
    
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_deployment_status() {
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║  ${WHITE}🚀 部署进度状态                                                           ${GREEN}║${RESET}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    # 重新检测状态
    detect_deployment_status
    
    local step_status=()
    step_status[1]=$([ "$STEP1_DONE" = true ] && echo "${GREEN}✓${RESET}" || echo "${GRAY}○${RESET}")
    step_status[2]=$([ "$STEP2_DONE" = true ] && echo "${GREEN}✓${RESET}" || echo "${GRAY}○${RESET}")
    step_status[3]=$([ "$STEP3_DONE" = true ] && echo "${GREEN}✓${RESET}" || echo "${GRAY}○${RESET}")
    step_status[4]=$([ "$STEP4_DONE" = true ] && echo "${GREEN}✓${RESET}" || echo "${GRAY}○${RESET}")
    
    echo -e "${GREEN}║                                                                              ║${RESET}"
    echo -e "${GREEN}║  ${WHITE}     [${step_status[1]}] ${WHITE}① 网络配置${RESET}   ${WHITE}[${step_status[2]}] ${WHITE}② Docker安装${RESET}   ${WHITE}[${step_status[3]}] ${WHITE}③ AstrBot${RESET}   ${WHITE}[${step_status[4]}] ${WHITE}④ NapCat${RESET}    ${GREEN}║${RESET}"
    echo -e "${GREEN}║                                                                              ║${RESET}"
    
    # 容器状态
    local astrbot_status=$(timeout 2 docker inspect -f '{{.State.Status}}' astrbot 2>/dev/null || echo "not_exist")
    local napcat_status=$(timeout 2 docker inspect -f '{{.State.Status}}' napcat 2>/dev/null || echo "not_exist")
    
    if [ "$STEP3_DONE" = true ] || [ "$STEP4_DONE" = true ]; then
        echo -e "${GREEN}║  ${WHITE}容器状态:                                                                 ${GREEN}║${RESET}"
        
        if [ "$STEP3_DONE" = true ]; then
            if [ "$astrbot_status" = "running" ]; then
                echo -e "${GREEN}║     ${GREEN}✅ AstrBot: 运行中${RESET} (端口: 6180-6200, 11451)                    ${GREEN}║${RESET}"
            else
                echo -e "${GREEN}║     ${YELLOW}⚠️ AstrBot: ${astrbot_status}${RESET}                                  ${GREEN}║${RESET}"
            fi
        fi
        
        if [ "$STEP4_DONE" = true ]; then
            if [ "$napcat_status" = "running" ]; then
                echo -e "${GREEN}║     ${GREEN}✅ NapCat: 运行中${RESET} (端口: 3000, 3001, 6099)                    ${GREEN}║${RESET}"
            else
                echo -e "${GREEN}║     ${YELLOW}⚠️ NapCat: ${napcat_status}${RESET}                                   ${GREEN}║${RESET}"
            fi
        fi
    else
        echo -e "${GREEN}║  ${GRAY}暂无容器运行${RESET}                                                        ${GREEN}║${RESET}"
    fi
    
    echo -e "${GREEN}║                                                                              ║${RESET}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# ===================== UI模式切换功能 =====================
toggle_ui_mode() {
    echo -e "\n${CYAN}${ICON_SCREEN} 切换UI模式${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    echo -e "${WHITE}当前终端尺寸: ${TERM_COLS}列 × ${TERM_LINES}行${RESET}"
    echo -e "${WHITE}当前UI模式: ${GREEN}${UI_MODE}${RESET}"
    
    echo -e "\n${WHITE}选择UI模式:${RESET}"
    echo -e "  ${CYAN}[1] ${GREEN}自动模式（根据屏幕宽度自动选择）${RESET}"
    echo -e "  ${CYAN}[2] ${GREEN}宽屏模式（适合120列以上终端）${RESET}"
    echo -e "  ${CYAN}[3] ${GREEN}普通模式（适合80-120列终端）${RESET}"
    echo -e "  ${CYAN}[4] ${GREEN}窄屏模式（适合80列以下终端）${RESET}"
    echo -e "  ${CYAN}[5] ${YELLOW}测试UI显示${RESET}"
    echo -e "  ${CYAN}[0] ${GRAY}取消${RESET}"
    
    echo -ne "\n${YELLOW}请选择模式: ${RESET}"
    read -r ui_choice
    
    case "$ui_choice" in
        1)
            if [ "$TERM_COLS" -ge 120 ]; then
                UI_MODE="wide"
            elif [ "$TERM_COLS" -ge 80 ]; then
                UI_MODE="normal"
            else
                UI_MODE="narrow"
            fi
            echo -e "${GREEN}${ICON_CHECK} 已切换到自动模式${RESET}"
            ;;
        2)
            UI_MODE="wide"
            echo -e "${GREEN}${ICON_CHECK} 已切换到宽屏模式${RESET}"
            ;;
        3)
            UI_MODE="normal"
            echo -e "${GREEN}${ICON_CHECK} 已切换到普通模式${RESET}"
            ;;
        4)
            UI_MODE="narrow"
            echo -e "${GREEN}${ICON_CHECK} 已切换到窄屏模式${RESET}"
            ;;
        5)
            test_ui_display
            return
            ;;
        0)
            echo -e "${GRAY}已取消${RESET}"
            return
            ;;
        *)
            echo -e "${RED}无效选择${RESET}"
            return
            ;;
    esac
    
    # 更新UI宽度设置
    if [ "$UI_MODE" = "wide" ]; then
        UI_WIDTH=120
        MENU_COLS=2
    elif [ "$UI_MODE" = "normal" ]; then
        UI_WIDTH=100
        MENU_COLS=1
    else
        UI_WIDTH=80
        MENU_COLS=1
    fi
    
    echo -e "${GRAY}UI宽度已设置为: ${UI_WIDTH}列${RESET}"
    echo -e "${GRAY}菜单列数: ${MENU_COLS}列${RESET}"
    sleep 2
}

test_ui_display() {
    echo -e "\n${CYAN}${ICON_SCREEN} UI显示测试${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    echo -e "${WHITE}终端信息:${RESET}"
    echo -e "  列数: ${TERM_COLS}"
    echo -e "  行数: ${TERM_LINES}"
    echo -e "  UI模式: ${UI_MODE}"
    echo -e "  UI宽度: ${UI_WIDTH}"
    
    echo -e "\n${WHITE}显示测试:${RESET}"
    for i in {1..5}; do
        echo -e "  ${GREEN}████${RESET}${YELLOW}████${RESET}${RED}████${RESET}${BLUE}████${RESET}${MAGENTA}████${RESET} 测试行 $i"
    done
    
    echo -e "\n${WHITE}边框测试:${RESET}"
    echo -e "${CYAN}┌────────────────────────────────────────────┐${RESET}"
    echo -e "${CYAN}│               UI显示测试                   │${RESET}"
    echo -e "${CYAN}├────────────────────────────────────────────┤${RESET}"
    echo -e "${CYAN}│  这是一个测试显示框，用于验证UI渲染       │${RESET}"
    echo -e "${CYAN}│  当前终端宽度: ${TERM_COLS}列                      │${RESET}"
    if [ "$TERM_COLS" -ge 80 ]; then
        echo -e "${CYAN}│  终端宽度足够，可以显示完整UI             │${RESET}"
    else
        echo -e "${CYAN}│  ${YELLOW}终端宽度不足，建议调整终端大小${RESET}${CYAN}        │${RESET}"
    fi
    echo -e "${CYAN}└────────────────────────────────────────────┘${RESET}"
    
    echo -e "\n${YELLOW}按任意键继续...${RESET}"
    read -p ""
}

# ===================== 窄屏主菜单 =====================
print_main_menu_narrow() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║  ${WHITE}📱 主功能菜单                                                                        ${BLUE}║${RESET}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    echo -e "${BLUE}║                                                                              ║${RESET}"
    echo -e "${BLUE}║  ${CYAN}[1] ${GREEN}🌐 网络配置${RESET}     ${CYAN}[2] ${GREEN}🐳 Docker管理${RESET}     ${CYAN}[3] ${GREEN}🤖 AstrBot${RESET}     ${CYAN}[4] ${GREEN}😺 NapCat${RESET}      ${BLUE}║${RESET}"
    echo -e "${BLUE}║     ${WHITE}优化网络     ${RESET}        ${WHITE}安装/卸载      ${RESET}      ${WHITE}6180-6200      ${RESET}     ${WHITE}3000,3001${RESET}        ${BLUE}║${RESET}"
    
    echo -e "${BLUE}║                                                                              ║${RESET}"
    
    echo -e "${BLUE}║  ${CYAN}[0] ${GREEN}🚀 一键部署${RESET}    ${CYAN}[E] ${CYAN}⚙️  扩展工具${RESET}     ${CYAN}[C] ${SKY}📋  容器状态${RESET}    ${CYAN}[U] ${YELLOW}🔄  检查更新${RESET}   ${BLUE}║${RESET}"
    echo -e "${BLUE}║     ${WHITE}自动完成    ${RESET}        ${WHITE}高级功能      ${RESET}      ${WHITE}详细状态      ${RESET}     ${WHITE}脚本更新${RESET}        ${BLUE}║${RESET}"
    
    echo -e "${BLUE}║                                                                              ║${RESET}"
    
    echo -e "${BLUE}║  ${CYAN}[T] ${PINK}📺 切换UI${RESET}      ${CYAN}[Q] ${RED}❌  退出脚本${RESET}                                                      ${BLUE}║${RESET}"
    echo -e "${BLUE}║     ${WHITE}UI模式切换${RESET}        ${WHITE}退出程序${RESET}                                                                 ${BLUE}║${RESET}"
    
    echo -e "${BLUE}║                                                                              ║${RESET}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    # 状态信息
    echo -e "${BLUE}║  ${WHITE}📊 终端: ${TERM_COLS}×${TERM_LINES} | UI: ${UI_MODE} | 进度: ${RESET}"
    
    local progress=""
    [ "$STEP1_DONE" = true ] && progress+="${GREEN}①${RESET}" || progress+="${GRAY}①${RESET}"
    [ "$STEP2_DONE" = true ] && progress+="${GREEN}②${RESET}" || progress+="${GRAY}②${RESET}"
    [ "$STEP3_DONE" = true ] && progress+="${GREEN}③${RESET}" || progress+="${GRAY}③${RESET}"
    [ "$STEP4_DONE" = true ] && progress+="${GREEN}④${RESET}" || progress+="${GRAY}④${RESET}"
    
    echo -e "${BLUE}║            ${progress} | ${YELLOW}⚠️  声明: ${WHITE}本脚本完全免费，严禁倒卖！${RESET}          ${BLUE}║${RESET}"
    echo -e "${BLUE}║  ${CYAN}💝 技术支持: ${WHITE}QQ 3076737056 | 最后更新: 2025年12月27日${RESET}                ${BLUE}║${RESET}"
    echo -e "${BLUE}║                                                                              ║${RESET}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# ===================== 宽屏主菜单 =====================
print_main_menu_wide() {
    # 首先显示标题和状态
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${MAGENTA}║  ${WHITE}📱 智能部署助手 v2.8.0 - 宽屏模式                                                                                       ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    # 显示终端和进度信息
    echo -e "${MAGENTA}║  ${WHITE}📊 终端: ${TERM_COLS}×${TERM_LINES} | UI模式: ${UI_MODE} | 部署进度: ${RESET}"
    
    local progress=""
    [ "$STEP1_DONE" = true ] && progress+="${GREEN}①${RESET}" || progress+="${GRAY}①${RESET}"
    [ "$STEP2_DONE" = true ] && progress+="${GREEN}②${RESET}" || progress+="${GRAY}②${RESET}"
    [ "$STEP3_DONE" = true ] && progress+="${GREEN}③${RESET}" || progress+="${GRAY}③${RESET}"
    [ "$STEP4_DONE" = true ] && progress+="${GREEN}④${RESET}" || progress+="${GRAY}④${RESET}"
    
    echo -e "${MAGENTA}║            ${progress} | ${YELLOW}⚠️  声明: ${WHITE}本脚本完全免费，严禁倒卖！${RESET}                                                    ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║  ${CYAN}💝 技术支持: ${WHITE}QQ 3076737056 | 最后更新: 2025年12月27日${RESET}                                                    ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    # 显示状态信息（并排显示）
    echo -e "${MAGENTA}║                                                                                                                                    ║${RESET}"
    
    # 获取系统状态和部署状态
    local system_status=$(mktemp)
    local deployment_status=$(mktemp)
    
    # 生成系统状态
    echo -e "${CYAN}╔════════════════════════════════════════════╗${RESET}" > "$system_status"
    echo -e "${CYAN}║  ${WHITE}📊 系统状态监控                          ${CYAN}║${RESET}" >> "$system_status"
    echo -e "${CYAN}╠════════════════════════════════════════════╣${RESET}" >> "$system_status"
    
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "0")
    local mem_percent=$(free 2>/dev/null | awk '/^Mem:/{print $3/$2*100}' || echo "0")
    local disk_percent=$(df / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || echo "0")
    local load_avg=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}' || echo "0")
    
    progress_bar() {
        local value=$1
        local max=100
        local bar_width=15
        local filled=$((value * bar_width / max))
        local empty=$((bar_width - filled))
        
        printf "["
        for ((i=0; i<filled; i++)); do printf "█"; done
        for ((i=0; i<empty; i++)); do printf " "; done
        printf "] %3d%%" "$value"
    }
    
    local cpu_color=$([ "${cpu_usage%.*}" -gt 80 ] && echo "$RED" || ([ "${cpu_usage%.*}" -gt 50 ] && echo "$YELLOW" || echo "$GREEN"))
    local mem_color=$([ "${mem_percent%.*}" -gt 80 ] && echo "$RED" || ([ "${mem_percent%.*}" -gt 50 ] && echo "$YELLOW" || echo "$GREEN"))
    local disk_color=$([ "$disk_percent" -gt 80 ] && echo "$RED" || ([ "$disk_percent" -gt 50 ] && echo "$YELLOW" || echo "$GREEN"))
    
    echo -e "${CYAN}║  ${WHITE}🖥  CPU: ${cpu_color}$(progress_bar ${cpu_usage%.*})${RESET}         ${CYAN}║${RESET}" >> "$system_status"
    echo -e "${CYAN}║  ${WHITE}💾  内存: ${mem_color}$(progress_bar ${mem_percent%.*})${RESET}         ${CYAN}║${RESET}" >> "$system_status"
    echo -e "${CYAN}║  ${WHITE}💿  磁盘: ${disk_color}$(progress_bar $disk_percent)${RESET}         ${CYAN}║${RESET}" >> "$system_status"
    echo -e "${CYAN}║  ${WHITE}📈  负载: ${load_avg}${RESET}                    ${CYAN}║${RESET}" >> "$system_status"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${RESET}" >> "$system_status"
    
    # 生成部署状态
    echo -e "${GREEN}╔════════════════════════════════════════════╗${RESET}" > "$deployment_status"
    echo -e "${GREEN} ║  ${WHITE}🚀 部署进度状态                          ${GREEN}║${RESET}" >> "$deployment_status"
    echo -e "${GREEN}╠════════════════════════════════════════════╣${RESET}" >> "$deployment_status"
    
    local step_status=()
    step_status[1]=$([ "$STEP1_DONE" = true ] && echo "${GREEN}✓${RESET}" || echo "${GRAY}○${RESET}")
    step_status[2]=$([ "$STEP2_DONE" = true ] && echo "${GREEN}✓${RESET}" || echo "${GRAY}○${RESET}")
    step_status[3]=$([ "$STEP3_DONE" = true ] && echo "${GREEN}✓${RESET}" || echo "${GRAY}○${RESET}")
    step_status[4]=$([ "$STEP4_DONE" = true ] && echo "${GREEN}✓${RESET}" || echo "${GRAY}○${RESET}")
    
    echo -e "${GREEN}  ║                                            ║${RESET}" >> "$deployment_status"
    echo -e "${GREEN} ║  ${WHITE}  [${step_status[1]}] ① 网络配置${RESET}                         ${GREEN}║${RESET}" >> "$deployment_status"
    echo -e "${GREEN} ║  ${WHITE}  [${step_status[2]}] ② Docker安装${RESET}                       ${GREEN}║${RESET}" >> "$deployment_status"
    echo -e "${GREEN}        ║  ${WHITE}  [${step_status[3]}] ③ AstrBot${RESET}                          ${GREEN}║${RESET}" >> "$deployment_status"
    echo -e "${GREEN}║  ${WHITE}  [${step_status[4]}] ④ NapCat${RESET}                         ${GREEN}║${RESET}" >> "$deployment_status"
    echo -e "${GREEN}║                                            ║${RESET}" >> "$deployment_status"
    
    # 容器状态
    if [ "$STEP3_DONE" = true ] || [ "$STEP4_DONE" = true ]; then
        echo -e "${GREEN}║  ${WHITE}容器状态:${RESET}                              ${GREEN}║${RESET}" >> "$deployment_status"
        
        if [ "$STEP3_DONE" = true ]; then
            local astrbot_status=$(timeout 2 docker inspect -f '{{.State.Status}}' astrbot 2>/dev/null || echo "unknown")
            if [ "$astrbot_status" = "running" ]; then
                echo -e "${GREEN}║     ${GREEN}✅ AstrBot${RESET}                      ${GREEN}║${RESET}" >> "$deployment_status"
            else
                echo -e "${GREEN}║     ${YELLOW}⚠️  AstrBot${RESET}                      ${GREEN}║${RESET}" >> "$deployment_status"
            fi
        fi
        
        if [ "$STEP4_DONE" = true ]; then
            local napcat_status=$(timeout 2 docker inspect -f '{{.State.Status}}' napcat 2>/dev/null || echo "unknown")
            if [ "$napcat_status" = "running" ]; then
                echo -e "${GREEN}║     ${GREEN}✅ NapCat${RESET}                       ${GREEN}║${RESET}" >> "$deployment_status"
            else
                echo -e "${GREEN}║     ${YELLOW}⚠️  NapCat${RESET}                       ${GREEN}║${RESET}" >> "$deployment_status"
            fi
        fi
    else
        echo -e "${GREEN}║  ${GRAY}暂无容器运行${RESET}                          ${GREEN}║${RESET}" >> "$deployment_status"
    fi
    
    echo -e "${GREEN}║                                            ║${RESET}" >> "$deployment_status"
    echo -e "${GREEN}╚════════════════════════════════════════════╝${RESET}" >> "$deployment_status"
    
    # 并排显示系统状态和部署状态
    local system_lines=()
    local deploy_lines=()
    
    mapfile -t system_lines < "$system_status"
    mapfile -t deploy_lines < "$deployment_status"
    
    for i in "${!system_lines[@]}"; do
        if [ $i -lt ${#deploy_lines[@]} ]; then
            echo -e "${MAGENTA}║  ${system_lines[$i]}   ${deploy_lines[$i]}  ${MAGENTA}║${RESET}"
        else
            echo -e "${MAGENTA}║  ${system_lines[$i]}   ${GREEN}║                                            ║${RESET}  ${MAGENTA}║${RESET}"
        fi
    done
    
    rm -f "$system_status" "$deployment_status"
    
    echo -e "${MAGENTA}║                                                                                                                                    ║${RESET}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    # 菜单区域
    echo -e "${MAGENTA}║                                                                                                                                    ║${RESET}"
    echo -e "${MAGENTA}║  ${CYAN}┌───────────────────────── 核心部署 ─────────────────────────┐${RESET}  ${CYAN}┌─────────────────────── 快捷操作 ──────────────────────┐${RESET}  ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║                                                                                                                                    ║${RESET}"
    
    # 选项布局
    echo -e "${MAGENTA}║  ${CYAN}[1] ${GREEN}🌐 网络配置${RESET}                                                               ${MAGENTA}║${RESET}  ${CYAN}[0] ${GREEN}🚀 一键部署${RESET}                                                             ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║     ${WHITE}优化网络和DNS设置，确保网络连通性                                                    ${MAGENTA}║${RESET}     ${WHITE}自动完成所有部署步骤，推荐新手使用                                ${MAGENTA}║${RESET}"
    
    echo -e "${MAGENTA}║                                                                                                                                    ║${RESET}"
    
    echo -e "${MAGENTA}║  ${CYAN}[2] ${GREEN}🐳 Docker管理${RESET}                                                            ${MAGENTA}║${RESET}  ${CYAN}[E] ${CYAN}⚙️  扩展工具${RESET}                                                              ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║     ${WHITE}安装/卸载Docker，配置镜像源                                                          ${MAGENTA}║${RESET}     ${WHITE}容器管理、网络工具、系统监控等高级功能                          ${MAGENTA}║${RESET}"
    
    echo -e "${MAGENTA}║                                                                                                                                    ║${RESET}"
    
    echo -e "${MAGENTA}║  ${CYAN}[3] ${GREEN}🤖 AstrBot部署${RESET}                                                           ${MAGENTA}║${RESET}  ${CYAN}[C] ${SKY}📋  容器状态${RESET}                                                             ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║     ${WHITE}端口: 6180-6200, 11451 | 共享目录: /app/sharedFolder                              ${MAGENTA}║${RESET}     ${WHITE}查看容器运行状态、端口映射、共享目录挂载情况                    ${MAGENTA}║${RESET}"
    
    echo -e "${MAGENTA}║                                                                                                                                    ║${RESET}"
    
    echo -e "${MAGENTA}║  ${CYAN}[4] ${GREEN}😺 NapCat部署${RESET}                                                            ${MAGENTA}║${RESET}  ${CYAN}[U] ${YELLOW}🔄  检查更新${RESET}                                                              ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║     ${WHITE}端口: 3000, 3001, 6099 | 共享目录: /app/sharedFolder                               ${MAGENTA}║${RESET}     ${WHITE}检查脚本更新，获取最新版本和功能                                ${MAGENTA}║${RESET}"
    
    echo -e "${MAGENTA}║                                                                                                                                    ║${RESET}"
    
    echo -e "${MAGENTA}║  ${CYAN}[T] ${PINK}📺 切换UI${RESET}                                                                ${MAGENTA}║${RESET}  ${CYAN}[Q] ${RED}❌  退出脚本${RESET}                                                              ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║     ${WHITE}切换UI显示模式（宽屏/普通/窄屏）                                                     ${MAGENTA}║${RESET}     ${WHITE}退出脚本，返回终端                                                      ${MAGENTA}║${RESET}"
    
    echo -e "${MAGENTA}║                                                                                                                                    ║${RESET}"
    
    echo -e "${MAGENTA}║  ${CYAN}└────────────────────────────────────────────────────────────┘${RESET}  ${CYAN}└─────────────────────────────────────────────────────┘${RESET}  ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║                                                                                                                                    ║${RESET}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# ===================== 普通主菜单 =====================
print_main_menu_normal() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║  ${WHITE}📱 主功能菜单                                                                        ${BLUE}║${RESET}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    echo -e "${BLUE}║                                                                              ║${RESET}"
    echo -e "${BLUE}║  ${CYAN}[1] ${GREEN}🌐 网络配置${RESET}     ${CYAN}[2] ${GREEN}🐳 Docker管理${RESET}     ${CYAN}[3] ${GREEN}🤖 AstrBot${RESET}     ${CYAN}[4] ${GREEN}😺 NapCat${RESET}      ${BLUE}║${RESET}"
    echo -e "${BLUE}║     ${WHITE}优化网络     ${RESET}        ${WHITE}安装/卸载      ${RESET}      ${WHITE}6180-6200      ${RESET}     ${WHITE}3000,3001${RESET}        ${BLUE}║${RESET}"
    
    echo -e "${BLUE}║                                                                              ║${RESET}"
    
    echo -e "${BLUE}║  ${CYAN}[0] ${GREEN}🚀 一键部署${RESET}    ${CYAN}[E] ${CYAN}⚙️  扩展工具${RESET}     ${CYAN}[C] ${SKY}📋  容器状态${RESET}    ${CYAN}[U] ${YELLOW}🔄  检查更新${RESET}   ${BLUE}║${RESET}"
    echo -e "${BLUE}║     ${WHITE}自动完成    ${RESET}        ${WHITE}高级功能      ${RESET}      ${WHITE}详细状态      ${RESET}     ${WHITE}脚本更新${RESET}        ${BLUE}║${RESET}"
    
    echo -e "${BLUE}║                                                                              ║${RESET}"
    
    echo -e "${BLUE}║  ${CYAN}[T] ${PINK}📺 切换UI${RESET}      ${CYAN}[Q] ${RED}❌  退出脚本${RESET}                                                      ${BLUE}║${RESET}"
    echo -e "${BLUE}║     ${WHITE}UI模式切换${RESET}        ${WHITE}退出程序${RESET}                                                                 ${BLUE}║${RESET}"
    
    echo -e "${BLUE}║                                                                              ║${RESET}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${RESET}"
    
    # 状态信息
    echo -e "${BLUE}║  ${WHITE}📊 终端: ${TERM_COLS}×${TERM_LINES} | UI: ${UI_MODE} | 进度: ${RESET}"
    
    local progress=""
    [ "$STEP1_DONE" = true ] && progress+="${GREEN}①${RESET}" || progress+="${GRAY}①${RESET}"
    [ "$STEP2_DONE" = true ] && progress+="${GREEN}②${RESET}" || progress+="${GRAY}②${RESET}"
    [ "$STEP3_DONE" = true ] && progress+="${GREEN}③${RESET}" || progress+="${GRAY}③${RESET}"
    [ "$STEP4_DONE" = true ] && progress+="${GREEN}④${RESET}" || progress+="${GRAY}④${RESET}"
    
    echo -e "${BLUE}║            ${progress} | ${YELLOW}⚠️  声明: ${WHITE}本脚本完全免费，严禁倒卖！${RESET}          ${BLUE}║${RESET}"
    echo -e "${BLUE}║  ${CYAN}💝 技术支持: ${WHITE}QQ 3076737056 | 最后更新: 2025年12月27日${RESET}                ${BLUE}║${RESET}"
    echo -e "${BLUE}║                                                                              ║${RESET}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# ===================== 主菜单选择器 =====================
print_main_menu() {
    case "$UI_MODE" in
        "wide")
            print_main_menu_wide
            ;;
        "normal")
            print_main_menu_normal
            ;;
        "narrow")
            print_main_menu_narrow
            ;;
        *)
            # 自动选择
            if [ "$TERM_COLS" -ge 120 ]; then
                print_main_menu_wide
            elif [ "$TERM_COLS" -ge 80 ]; then
                print_main_menu_normal
            else
                print_main_menu_narrow
            fi
            ;;
    esac
}

print_contact_info() {
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${MAGENTA}║                                                                              ║${RESET}"
    echo -e "${MAGENTA}║  ${YELLOW}⚠️  重要声明: ${WHITE}本脚本完全免费，严禁倒卖！${RESET}                               ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║  ${CYAN}💝 技术支持: ${WHITE}QQ 3076737056 | 最后更新: 2025年12月27日${RESET}                ${MAGENTA}║${RESET}"
    echo -e "${MAGENTA}║                                                                              ║${RESET}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# ===================== 步骤函数定义 =====================
step1() {
    CURRENT_STEP="step1"
    local step_start=$(date +%s)
    
    # 自动检测当前状态
    if test_network_connectivity >/dev/null 2>&1; then
        echo -e "${GREEN}${ICON_CHECK} 网络配置检测完成，网络连通性正常${RESET}"
        STEP1_DONE=true
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

# ===================== 第二步：优化的Docker管理 =====================
step2() {
    CURRENT_STEP="step2"
    local step_start=$(date +%s)
    
    # 检查Docker是否已安装
    if command -v docker &>/dev/null; then
        echo -e "${GREEN}${ICON_CHECK} 检测到Docker已安装，版本: $(docker --version | cut -d' ' -f3)${RESET}"
        
        if confirm_action "Docker已安装，是否进入Docker管理菜单"; then
            docker_management_menu
        else
            STEP2_DONE=true
            return
        fi
    else
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
                echo -e "${YELLOW}${ICON_WARN} Docker未安装，无法卸载${RESET}"
                sleep 2
                return
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
    fi
}

docker_management_menu() {
    while true; do
        print_header
        echo -e "${CYAN}════════════════════════════════════════════${RESET}"
        echo -e "${WHITE}          Docker 管理菜单${RESET}"
        echo -e "${CYAN}════════════════════════════════════════════${RESET}"
        
        local docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3)
        local docker_status=$(systemctl is-active docker)
        local container_count=$(docker ps -q | wc -l)
        
        echo -e "${WHITE}当前状态:${RESET}"
        echo -e "  ${CYAN}版本: ${GREEN}${docker_version}${RESET}"
        echo -e "  ${CYAN}状态: ${GREEN}${docker_status}${RESET}"
        echo -e "  ${CYAN}运行容器: ${GREEN}${container_count}个${RESET}"
        
        echo -e "\n${WHITE}请选择操作:${RESET}"
        echo -e "  ${CYAN}[1] ${GREEN}重新安装/升级 Docker${RESET}"
        echo -e "  ${CYAN}[2] ${RED}卸载 Docker${RESET}"
        echo -e "  ${CYAN}[3] ${GREEN}重启 Docker 服务${RESET}"
        echo -e "  ${CYAN}[4] ${GREEN}查看 Docker 信息${RESET}"
        echo -e "  ${CYAN}[0] ${GRAY}返回主菜单${RESET}"
        
        echo -ne "\n${YELLOW}请选择操作（0-4）: ${RESET}"
        read -r docker_choice
        
        case "$docker_choice" in
            1)
                if confirm_action "重新安装/升级 Docker（将保留现有容器和数据）"; then
                    install_docker
                fi
                ;;
            2)
                if confirm_action "卸载Docker及相关组件，此操作不可逆！"; then
                    uninstall_docker
                    return
                fi
                ;;
            3)
                if confirm_action "重启 Docker 服务"; then
                    systemctl restart docker
                    echo -e "${GREEN}${ICON_CHECK} Docker服务已重启${RESET}"
                    sleep 2
                fi
                ;;
            4)
                echo -e "\n${CYAN}Docker系统信息:${RESET}"
                docker info --format '{{json .}}' 2>/dev/null | python3 -m json.tool 2>/dev/null | head -50 || docker info 2>/dev/null | head -30
                echo -e "\n${GREEN}按任意键继续...${RESET}"
                read -p ""
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}${ICON_CROSS} 无效选择！${RESET}"
                sleep 1
                ;;
        esac
    done
}

install_docker() {
    local step_start=$(date +%s)
    
    print_header
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          安装 Docker${RESET}"
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    
    # 检查是否已安装Docker
    if command -v docker &>/dev/null; then
        echo -e "${YELLOW}${ICON_WARN} 检测到Docker已安装${RESET}"
        echo -e "${CYAN}当前版本: $(docker --version | cut -d' ' -f3)${RESET}"
        
        if ! confirm_action "是否重新安装/升级Docker？"; then
            STEP2_DONE=true
            return
        fi
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
    if timeout 120 apt-get update -y 2>&1 | tee -a "$clean_log"; then
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
    
    if timeout 300 apt-get install -y ca-certificates curl gnupg lsb-release 2>&1 | tee "$deps_log"; then
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
    if timeout 60 curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg 2>&1 | tee "$gpg_log"; then
        echo -e "${GREEN}${ICON_CHECK} Docker官方GPG密钥添加成功${RESET}"
    else
        echo -e "${YELLOW}${ICON_WARN} GPG密钥添加遇到问题，尝试备用方法...${RESET}"
        timeout 60 curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
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
    
    if timeout 120 apt-get update -y 2>&1 | tee -a "$repo_log"; then
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
    if timeout 600 apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>&1 | tee "$install_log"; then
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
    local test_output=$(timeout 30 docker run --rm hello-world 2>&1)
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
    local uninstall_output=$(timeout 300 apt-get purge -y \
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
    timeout 180 apt-get autoremove -y 2>&1 | tee -a "$uninstall_log"
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

# ===================== 第三步：优化的AstrBot部署 =====================
step3() {
    CURRENT_STEP="step3"
    local step_start=$(date +%s)
    
    # 检查Docker是否已安装
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}${ICON_CROSS} Docker未安装，请先安装Docker${RESET}"
        echo -e "${YELLOW}${ICON_WARN} 是否现在安装Docker？${RESET}"
        if confirm_action "安装Docker"; then
            step2
            if [ "$STEP2_DONE" = false ]; then
                return
            fi
        else
            return
        fi
    fi
    
    # 检查容器是否存在
    if docker ps -a --filter "name=astrbot" --format "{{.Names}}" | grep -q "astrbot"; then
        # 检查容器状态
        local container_state=$(timeout 2 docker inspect -f '{{.State.Status}}' astrbot 2>/dev/null || echo "unknown")
        
        echo -e "${CYAN}${ICON_INFO} 检测到AstrBot容器已存在${RESET}"
        
        if [ "$container_state" = "running" ]; then
            echo -e "${GREEN}${ICON_CHECK} AstrBot容器正在运行中${RESET}"
            
            if confirm_action "AstrBot已在运行，是否重新部署？（将重启容器）"; then
                # 重新部署逻辑
                redeploy_astrbot
            else
                STEP3_DONE=true
                return
            fi
        else
            echo -e "${YELLOW}${ICON_WARN} AstrBot容器存在但状态为: ${container_state}${RESET}"
            
            if confirm_action "是否启动AstrBot容器？"; then
                if timeout 10 docker start astrbot; then
                    echo -e "${GREEN}${ICON_CHECK} AstrBot容器启动成功${RESET}"
                    sleep 3
                    check_container_status "astrbot"
                    STEP3_DONE=true
                    return
                else
                    echo -e "${RED}${ICON_CROSS} AstrBot容器启动失败${RESET}"
                    
                    if confirm_action "是否删除并重新部署AstrBot？"; then
                        redeploy_astrbot
                    else
                        return
                    fi
                fi
            else
                return
            fi
        fi
    else
        # 全新部署
        deploy_astrbot
    fi
}

deploy_astrbot() {
    print_header
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          第三步：部署AstrBot${RESET}"
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    
    if ! confirm_action "部署AstrBot容器（端口6180-6200, 11451）"; then
        return
    fi
    
    setup_shared_directory
    
    echo -e "${CYAN}${ICON_LOAD} 开始部署AstrBot...${RESET}"
    
    # 启动网速监控（仅显示下载速度）
    echo -e "\n${CYAN}${ICON_NETWORK} AstrBot镜像下载速度（M/s）${RESET}"
    monitor_speed_mb &
    speed_pid=$!
    
    mkdir -p astrbot/data astrbot/config
    
    echo -e "${CYAN}${ICON_LOAD} 拉取AstrBot镜像...${RESET}"
    if timeout 300 docker pull soulter/astrbot:latest; then
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
        
        STEP3_DONE=true
        STEP3_DURATION=$(( $(date +%s) - step_start ))
        echo -e "\n${GRAY}耗时: ${STEP3_DURATION}秒${RESET}"
        
    else
        echo -e "${RED}${ICON_CROSS} AstrBot启动失败${RESET}"
        return 1
    fi
}

redeploy_astrbot() {
    echo -e "\n${YELLOW}${ICON_WARN} 重新部署AstrBot...${RESET}"
    
    # 备份数据
    local backup_dir="/tmp/astrbot_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    if docker ps -a --filter "name=astrbot" --format "{{.Names}}" | grep -q "astrbot"; then
        echo -e "${CYAN}备份AstrBot数据...${RESET}"
        docker cp astrbot:/AstrBot/data "$backup_dir/astrbot_data" 2>/dev/null || true
        docker cp astrbot:/AstrBot/plugins "$backup_dir/astrbot_plugins" 2>/dev/null || true
        docker cp astrbot:/AstrBot/config "$backup_dir/astrbot_config" 2>/dev/null || true
    fi
    
    # 停止并删除容器
    docker stop astrbot 2>/dev/null
    docker rm astrbot 2>/dev/null
    
    # 重新部署
    deploy_astrbot
    
    # 恢复数据
    if [ -d "$backup_dir/astrbot_data" ]; then
        echo -e "${CYAN}恢复AstrBot数据...${RESET}"
        docker cp "$backup_dir/astrbot_data" astrbot:/AstrBot/data 2>/dev/null || true
        docker restart astrbot 2>/dev/null
    fi
    
    echo -e "${GREEN}${ICON_CHECK} AstrBot重新部署完成${RESET}"
    echo -e "${GRAY}备份数据保存在: $backup_dir${RESET}"
}

# ===================== 第四步：优化的NapCat部署 =====================
step4() {
    CURRENT_STEP="step4"
    local step_start=$(date +%s)
    
    # 检查Docker是否已安装
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}${ICON_CROSS} Docker未安装，请先安装Docker${RESET}"
        echo -e "${YELLOW}${ICON_WARN} 是否现在安装Docker？${RESET}"
        if confirm_action "安装Docker"; then
            step2
            if [ "$STEP2_DONE" = false ]; then
                return
            fi
        else
            return
        fi
    fi
    
    # 检查容器是否存在
    if docker ps -a --filter "name=napcat" --format "{{.Names}}" | grep -q "napcat"; then
        # 检查容器状态
        local container_state=$(timeout 2 docker inspect -f '{{.State.Status}}' napcat 2>/dev/null || echo "unknown")
        
        echo -e "${CYAN}${ICON_INFO} 检测到NapCat容器已存在${RESET}"
        
        if [ "$container_state" = "running" ]; then
            echo -e "${GREEN}${ICON_CHECK} NapCat容器正在运行中${RESET}"
            
            if confirm_action "NapCat已在运行，是否重新部署？（将重启容器）"; then
                # 重新部署逻辑
                redeploy_napcat
            else
                STEP4_DONE=true
                return
            fi
        else
            echo -e "${YELLOW}${ICON_WARN} NapCat容器存在但状态为: ${container_state}${RESET}"
            
            if confirm_action "是否启动NapCat容器？"; then
                if timeout 10 docker start napcat; then
                    echo -e "${GREEN}${ICON_CHECK} NapCat容器启动成功${RESET}"
                    sleep 3
                    check_container_status "napcat"
                    STEP4_DONE=true
                    return
                else
                    echo -e "${RED}${ICON_CROSS} NapCat容器启动失败${RESET}"
                    
                    if confirm_action "是否删除并重新部署NapCat？"; then
                        redeploy_napcat
                    else
                        return
                    fi
                fi
            else
                return
            fi
        fi
    else
        # 全新部署
        deploy_napcat
    fi
}

deploy_napcat() {
    print_header
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          第四步：部署NapCat${RESET}"
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    
    if ! confirm_action "部署NapCat容器（端口3000, 3001, 6099）"; then
        return
    fi
    
    setup_shared_directory
    
    echo -e "${CYAN}${ICON_LOAD} 开始部署NapCat...${RESET}"
    
    # 启动网速监控（仅显示下载速度）
    echo -e "\n${CYAN}${ICON_NETWORK} NapCat镜像下载速度（M/s）${RESET}"
    monitor_speed_mb &
    speed_pid=$!
    
    mkdir -p napcat/data napcat/config
    
    echo -e "${CYAN}${ICON_LOAD} 拉取NapCat镜像...${RESET}"
    if timeout 300 docker pull mlikiowa/napcat-docker:latest; then
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
        
        STEP4_DONE=true
        STEP4_DURATION=$(( $(date +%s) - step_start ))
        echo -e "\n${GRAY}耗时: ${STEP4_DURATION}秒${RESET}"
        
    else
        echo -e "${RED}${ICON_CROSS} NapCat启动失败${RESET}"
        return 1
    fi
}

redeploy_napcat() {
    echo -e "\n${YELLOW}${ICON_WARN} 重新部署NapCat...${RESET}"
    
    # 备份数据
    local backup_dir="/tmp/napcat_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    if docker ps -a --filter "name=napcat" --format "{{.Names}}" | grep -q "napcat"; then
        echo -e "${CYAN}备份NapCat数据...${RESET}"
        docker cp napcat:/app/data "$backup_dir/napcat_data" 2>/dev/null || true
        docker cp napcat:/app/plugins "$backup_dir/napcat_plugins" 2>/dev/null || true
        docker cp napcat:/app/config "$backup_dir/napcat_config" 2>/dev/null || true
    fi
    
    # 停止并删除容器
    docker stop napcat 2>/dev/null
    docker rm napcat 2>/dev/null
    
    # 重新部署
    deploy_napcat
    
    # 恢复数据
    if [ -d "$backup_dir/napcat_data" ]; then
        echo -e "${CYAN}恢复NapCat数据...${RESET}"
        docker cp "$backup_dir/napcat_data" napcat:/app/data 2>/dev/null || true
        docker restart napcat 2>/dev/null
    fi
    
    echo -e "${GREEN}${ICON_CHECK} NapCat重新部署完成${RESET}"
    echo -e "${GRAY}备份数据保存在: $backup_dir${RESET}"
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
        echo -e "${CYAN}║  ${CYAN}[16] ${PINK}📺 UI模式切换${RESET}                                          ${CYAN}║${RESET}"
        
        echo -e "${CYAN}║                                                                              ║${RESET}"
        echo -e "${CYAN}║  ${WHITE}└─────────────────────────────────────┘${RESET}                               ${CYAN}║${RESET}"
        echo -e "${CYAN}║                                                                              ║${RESET}"
        
        echo -e "${CYAN}║  ${CYAN}[0] ${GRAY}🔙 返回主菜单${RESET}                                           ${CYAN}║${RESET}"
        echo -e "${CYAN}║                                                                              ║${RESET}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
        
        echo -ne "${YELLOW}${ICON_WARN} 请输入选项 (0-16) : ${RESET}"
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
            16) toggle_ui_mode ;;
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
        # 检测当前部署状态
        detect_deployment_status
        
        print_header
        
        # 根据UI模式显示不同的布局
        case "$UI_MODE" in
            "wide")
                # 宽屏模式下显示并排状态
                print_main_menu_wide
                ;;
            "normal"|"narrow")
                # 普通和窄屏模式下显示分离状态
                print_system_status
                print_deployment_status
                print_main_menu
                ;;
            *)
                # 自动模式
                if [ "$TERM_COLS" -ge 120 ]; then
                    print_main_menu_wide
                else
                    print_system_status
                    print_deployment_status
                    print_main_menu
                fi
                ;;
        esac
        
        echo -ne "${YELLOW}${ICON_WARN} 请输入选项 (0-4/E/C/U/T/Q) : ${RESET}"
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
            t|T) toggle_ui_mode ;;
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
    echo "║              智能部署助手 v2.8.0 初始化                 ║"
    echo "║          修复UI布局 | 自动状态检测 | 优化核心部署逻辑   ║"
    echo "║          本脚本完全免费，严禁倒卖！                     ║"
    echo "║          技术支持QQ: 3076737056                         ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    
    # 显示终端信息
    echo -e "${CYAN}终端信息: ${WHITE}${TERM_COLS}列 × ${TERM_LINES}行${RESET}"
    echo -e "${CYAN}UI模式: ${GREEN}${UI_MODE}${RESET}"
    
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
    
    # 自动检测部署状态
    detect_deployment_status
    
    echo -e "\n${GREEN}${ICON_CHECK} 初始化完成！${RESET}"
    echo -e "${CYAN}检测到当前部署状态:${RESET}"
    echo -e "  网络配置: $([ "$STEP1_DONE" = true ] && echo "${GREEN}已配置${RESET}" || echo "${GRAY}未配置${RESET}")"
    echo -e "  Docker: $([ "$STEP2_DONE" = true ] && echo "${GREEN}已安装${RESET}" || echo "${GRAY}未安装${RESET}")"
    echo -e "  AstrBot: $([ "$STEP3_DONE" = true ] && echo "${GREEN}已部署${RESET}" || echo "${GRAY}未部署${RESET}")"
    echo -e "  NapCat: $([ "$STEP4_DONE" = true ] && echo "${GREEN}已部署${RESET}" || echo "${GRAY}未部署${RESET}")"
    
    sleep 2
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
    show_main_menu
    
    cleanup
}

# 启动主程序
main
exit 0
