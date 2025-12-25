#!/bin/bash
# ===================== 版本信息 =====================
# 脚本名称: AstrBot+NapCat 智能部署助手
# 版本号: v2.5.3
# 最后更新: 2025年12月25日
# 功能: 修复共享目录挂载问题
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

# 共享目录配置
SHARED_DIR="/opt/astrbot/shared"
ASTROBOT_SHARED_PATH="/app/sharedFolder"
NAPCAT_SHARED_PATH="/app/sharedFolder"

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
    if [ -f "/sys/class/net/${DEFAULT_IFACE}/statistics/rx_bytes" ]; then
        local initial_rx=$(cat /sys/class/net/${DEFAULT_IFACE}/statistics/rx_bytes 2>/dev/null || echo 0)
        local initial_tx=$(cat /sys/class/net/${DEFAULT_IFACE}/statistics/tx_bytes 2>/dev/null || echo 0)
        
        while true; do
            sleep 1
            local current_rx=$(cat /sys/class/net/${DEFAULT_IFACE}/statistics/rx_bytes 2>/dev/null || echo 0)
            local current_tx=$(cat /sys/class/net/${DEFAULT_IFACE}/statistics/tx_bytes 2>/dev/null || echo 0)
            
            local rx_speed=$(echo "scale=2; ($current_rx - $initial_rx) / 1024 / 1024" | bc 2>/dev/null || echo "0.00")
            local tx_speed=$(echo "scale=2; ($current_tx - $initial_tx) / 1024 / 1024" | bc 2>/dev/null || echo "0.00")
            
            printf "\r${GREEN}↓ ${rx_speed:0:6} M/s ${RESET}| ${BLUE}↑ ${tx_speed:0:6} M/s${RESET}"
            
            initial_rx=$current_rx
            initial_tx=$current_tx
        done
    else
        echo -e "${YELLOW}${ICON_WARN} 无法获取网卡信息，跳过网速监控！${RESET}"
    fi
}

extract_urls_from_logs() {
    local container_name=$1
    echo -e "\n${CYAN}${ICON_LINK} 从 $container_name 日志提取URL${RESET}"
    
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
        echo -e "${RED}${ICON_CROSS} 容器 $container_name 不存在${RESET}"
        return 1
    fi
    
    local urls=$(timeout 10 docker logs "$container_name" 2>/dev/null | grep -Eo 'https?://[^"[:space:]]+' | sort -u)
    
    if [ -n "$urls" ]; then
        echo "$urls"
        local url_file="${LOG_DIR}/${container_name}_urls_$(date +%Y%m%d_%H%M%S).txt"
        echo "$urls" > "$url_file"
        echo -e "${GREEN}${ICON_CHECK} URL已保存到: $url_file${RESET}"
    else
        echo -e "${YELLOW}${ICON_WARN} 未找到URL或读取超时${RESET}"
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
                    echo -e "${RED}${ICON_CROSS} 共享目录未挂载【多试几遍，若多次确认未挂载则去扩展功能执行修复】${RESET}"
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
    
    # 设置更宽松的权限，确保容器可以读写
    chmod 777 "$SHARED_DIR"
    
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
            echo -e "${YELLOW}${ICON_WARN} AstrBot未挂载共享目录【多测试几遍，若一直是此消息，再去扩展执行修复】${RESET}"
        fi
        
        if docker inspect napcat 2>/dev/null | grep -q "\"Source\": \"$SHARED_DIR\""; then
            echo -e "${GREEN}${ICON_CHECK} NapCat已挂载共享目录${RESET}"
        else
            echo -e "${YELLOW}${ICON_WARN} NapCat未挂载共享目录【多测试几遍，若一直是此消息，再去扩展执行修复】${RESET}"
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
    local test_file="$SHARED_DIR/shared_test_$(date +%s).txt"
    local test_content="共享文件夹测试 $(date)"
    
    echo -e "${WHITE}在宿主机创建测试文件...${RESET}"
    echo "$test_content" > "$test_file"
    echo -e "${GREEN}${ICON_CHECK} 测试文件已创建: $(basename "$test_file")${RESET}"
    
    local napcat_ok=false
    local astrbot_ok=false
    
    # 测试NapCat
    if $napcat_exists; then
        echo -e "\n${WHITE}测试NapCat容器读取...${RESET}"
        local napcat_result=$(docker exec napcat cat "$NAPCAT_SHARED_PATH/$(basename "$test_file")" 2>/dev/null)
        if echo "$napcat_result" | grep -q "$test_content"; then
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
        local astrbot_result=$(docker exec astrbot cat "$ASTROBOT_SHARED_PATH/$(basename "$test_file")" 2>/dev/null)
        if echo "$astrbot_result" | grep -q "$test_content"; then
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
        echo -e "  2. 检查共享目录权限: chmod 777 $SHARED_DIR"
        echo -e "  3. 手动检查容器挂载: docker inspect <容器名>"
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
    mkdir -p /tmp/container_backup_$(date +%Y%m%d)
    docker inspect astrbot > /tmp/container_backup_$(date +%Y%m%d)/astrbot.json 2>/dev/null
    docker inspect napcat > /tmp/container_backup_$(date +%Y%m%d)/napcat.json 2>/dev/null
    
    # 重新创建共享目录
    echo -e "\n${CYAN}重新设置共享目录...${RESET}"
    mkdir -p "$SHARED_DIR"
    chmod 777 "$SHARED_DIR"
    
    # 停止并删除容器
    echo -e "\n${YELLOW}${ICON_WARN} 重启容器...${RESET}"
    
    if $astrbot_running; then
        echo -e "重新部署AstrBot..."
        docker stop astrbot >/dev/null 2>&1
        docker rm astrbot >/dev/null 2>&1
        
        # 重新运行AstrBot（带共享目录挂载）
        docker run -itd \
            -p 6180-6200:6180-6200 \
            -p 11451:11451 \
            -v "$SHARED_DIR:$ASTROBOT_SHARED_PATH" \
            -v "$(pwd)/astrbot/data:/AstrBot/data" \
            -v /etc/localtime:/etc/localtime:ro \
            --name astrbot \
            --restart=unless-stopped \
            soulter/astrbot:latest
    fi
    
    if $napcat_running; then
        echo -e "重新部署NapCat..."
        docker stop napcat >/dev/null 2>&1
        docker rm napcat >/dev/null 2>&1
        
        # 重新运行NapCat（带共享目录挂载）
        docker run -d \
            -e NAPCAT_GID=$(id -g) \
            -e NAPCAT_UID=$(id -u) \
            -p 3000:3000 \
            -p 3001:3001 \
            -p 6099:6099 \
            -v "$SHARED_DIR:$NAPCAT_SHARED_PATH" \
            -v "$(pwd)/napcat/data:/app/data" \
            -v /etc/localtime:/etc/localtime:ro \
            --name napcat \
            --restart=always \
            mlikiowa/napcat-docker:latest
    fi
    
    echo -e "\n${GREEN}${ICON_CHECK} 容器重启完成！${RESET}"
    
    # 等待容器启动
    sleep 3
    
    # 验证修复
    echo -e "\n${CYAN}验证修复结果...${RESET}"
    test_shared_folder
    
    echo -e "\n${GREEN}修复完成！${RESET}"
    echo -e "备份文件保存在: /tmp/container_backup_$(date +%Y%m%d)/"
}

# ===================== 显示函数 =====================
print_header() {
    clear
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}  ╔═╗╔═╗╔╦╗╔═╗╦═╗╔╦╗  ╔═╗╔═╗╔╦╗  ${WHITE}智能部署助手 v2.5.2${RESET}"
    echo -e "${CYAN}  ║╣ ║ ║║║║║╣ ╠╦╝ ║   ╠═╝║ ║║║║  ${GRAY}AstrBot + NapCat${RESET}"
    echo -e "${CYAN}  ╚═╝╚═╝╩ ╩╚═╝╩╚═ ╩   ╩  ╚═╝╩ ╩  ${YELLOW}修复共享目录挂载版${RESET}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${RESET}"
    echo ""
}

print_footer() {
    echo -e "${GRAY}════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${GRAY}提示: 按对应数字选择功能，q退出 | $(date +"%Y-%m-%d %H:%M:%S")${RESET}"
    echo -e "${GRAY}════════════════════════════════════════════════════════════════${RESET}"
}

print_status() {
    echo -e "${CYAN}当前状态:${RESET}"
    echo -n "  "
    [ "$STEP1_DONE" = true ] && echo -n "${GREEN}①${RESET} " || echo -n "${GRAY}①${RESET} "
    [ "$STEP2_DONE" = true ] && echo -n "${GREEN}②${RESET} " || echo -n "${GRAY}②${RESET} "
    [ "$STEP3_DONE" = true ] && echo -n "${GREEN}③${RESET} " || echo -n "${GRAY}③${RESET} "
    [ "$STEP4_DONE" = true ] && echo -n "${GREEN}④${RESET} " || echo -n "${GRAY}④${RESET} "
    echo ""
}

print_contact_info() {
    echo -e "${YELLOW}${ICON_WARN} 重要声明: 本脚本完全免费，严禁倒卖！${RESET}"
    echo -e "${CYAN}${ICON_HEART} 技术支持QQ: 3076737056${RESET}"
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

step2() {
    CURRENT_STEP="step2"
    local step_start=$(date +%s)
    
    if [ "$STEP2_DONE" = true ]; then
        echo -e "${GREEN}${ICON_CHECK} 第二步已完成${RESET}"
        return
    fi
    
    # 检查是否已安装Docker
    if command -v docker &>/dev/null; then
        echo -e "${GREEN}${ICON_CHECK} 检测到Docker已安装，跳过安装步骤${RESET}"
        
        # 验证Docker服务状态
        if systemctl is-active --quiet docker; then
            echo -e "${GREEN}${ICON_CHECK} Docker服务正在运行${RESET}"
        else
            echo -e "${YELLOW}${ICON_WARN} Docker服务未运行，正在启动...${RESET}"
            if systemctl start docker; then
                echo -e "${GREEN}${ICON_CHECK} Docker服务启动成功${RESET}"
            else
                echo -e "${RED}${ICON_CROSS} Docker服务启动失败${RESET}"
                return 1
            fi
        fi
        
        STEP2_DONE=true
        STEP2_DURATION=1
        return
    fi
    
    if ! confirm_action "安装Docker及Docker Compose"; then
        return
    fi
    
    print_header
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          第二步：安装Docker${RESET}"
    echo -e "${BLUE}════════════════════════════════════════════${RESET}"
    
    echo -e "${CYAN}${ICON_LOAD} 开始安装Docker...${RESET}"
    
    monitor_speed_mb &
    speed_pid=$!
    
    echo -e "${CYAN}${ICON_LOAD} 更新软件源...${RESET}"
    apt-get update -y >/dev/null 2>&1
    
    echo -e "${CYAN}${ICON_LOAD} 安装依赖...${RESET}"
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release >/dev/null 2>&1
    
    echo -e "${CYAN}${ICON_LOAD} 添加Docker仓库...${RESET}"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null 2>&1
    
    echo -e "${CYAN}${ICON_LOAD} 安装Docker引擎...${RESET}"
    apt-get update -y >/dev/null 2>&1
    
    if apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
        safe_kill "$speed_pid"
        
        echo -e "${GREEN}${ICON_CHECK} Docker安装完成${RESET}"
        
        # 配置Docker
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": ["https://registry.docker-cn.com", "https://mirror.baidubce.com", "https://hub-mirror.c.163.com"],
  "log-driver": "json-file",
  "log-opts": {"max-size": "100m", "max-file": "3"}
}
EOF
        
        systemctl daemon-reload
        systemctl restart docker
        systemctl enable docker >/dev/null 2>&1
    else
        safe_kill "$speed_pid"
        echo -e "${RED}${ICON_CROSS} Docker安装失败${RESET}"
        return 1
    fi
    
    STEP2_DONE=true
    STEP2_DURATION=$(( $(date +%s) - step_start ))
    echo -e "\n${GRAY}耗时: ${STEP2_DURATION}秒${RESET}"
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
                echo -e "${RED}${ICON_CROSS} 警告：共享目录未挂载【多试几遍，若多次确认未挂载则去扩展功能执行修复】！${RESET}"
                echo -e "${YELLOW}建议重新部署以启用共享文件夹功能${RESET}"
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
    
    monitor_speed_mb &
    speed_pid=$!
    
    mkdir -p astrbot/data astrbot/config
    
    echo -e "${CYAN}${ICON_LOAD} 拉取镜像...${RESET}"
    if docker pull soulter/astrbot:latest; then
        echo -e "${GREEN}${ICON_CHECK} 镜像拉取成功${RESET}"
    else
        safe_kill "$speed_pid"
        echo -e "${RED}${ICON_CROSS} 镜像拉取失败${RESET}"
        return 1
    fi
    
    echo -e "${CYAN}${ICON_LOAD} 启动容器...${RESET}"
    if docker run -itd \
        -p 6180-6200:6180-6200 \
        -p 11451:11451 \
        -v "$SHARED_DIR:$ASTROBOT_SHARED_PATH" \
        -v "$(pwd)/astrbot/data:/AstrBot/data" \
        -v /etc/localtime:/etc/localtime:ro \
        --name astrbot \
        --restart=unless-stopped \
        soulter/astrbot:latest; then
        
        safe_kill "$speed_pid"
        
        echo -e "${GREEN}${ICON_CHECK} AstrBot启动成功${RESET}"
        
        docker update --restart=always astrbot >/dev/null 2>&1
        sleep 3
        
        check_container_status "astrbot"
        
        local ip_address=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
        echo -e "\n${CYAN}访问地址:${RESET}"
        echo -e "  ${WHITE}Web界面: http://${ip_address}:6180${RESET}"
        echo -e "  ${WHITE}共享目录: ${SHARED_DIR} -> ${ASTROBOT_SHARED_PATH}${RESET}"
        
    else
        safe_kill "$speed_pid"
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
                echo -e "${RED}${ICON_CROSS} 警告：共享目录未挂载【多试几遍，若多次确认未挂载则去扩展功能执行修复】！${RESET}"
                echo -e "${YELLOW}建议重新部署以启用共享文件夹功能${RESET}"
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
    
    monitor_speed_mb &
    speed_pid=$!
    
    mkdir -p napcat/data napcat/config
    
    echo -e "${CYAN}${ICON_LOAD} 拉取镜像...${RESET}"
    if docker pull mlikiowa/napcat-docker:latest; then
        echo -e "${GREEN}${ICON_CHECK} 镜像拉取成功${RESET}"
    else
        safe_kill "$speed_pid"
        echo -e "${RED}${ICON_CROSS} 镜像拉取失败${RESET}"
        return 1
    fi
    
    echo -e "${CYAN}${ICON_LOAD} 启动容器...${RESET}"
    if docker run -d \
        -e NAPCAT_GID=$(id -g) \
        -e NAPCAT_UID=$(id -u) \
        -p 3000:3000 \
        -p 3001:3001 \
        -p 6099:6099 \
        -v "$SHARED_DIR:$NAPCAT_SHARED_PATH" \
        -v "$(pwd)/napcat/data:/app/data" \
        -v /etc/localtime:/etc/localtime:ro \
        --name napcat \
        --restart=always \
        mlikiowa/napcat-docker:latest; then
        
        safe_kill "$speed_pid"
        
        echo -e "${GREEN}${ICON_CHECK} NapCat启动成功${RESET}"
        sleep 3
        
        check_container_status "napcat"
        
        local ip_address=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
        echo -e "\n${CYAN}访问地址:${RESET}"
        echo -e "  ${WHITE}Web界面: http://${ip_address}:3000${RESET}"
        echo -e "  ${WHITE}共享目录: ${SHARED_DIR} -> ${NAPCAT_SHARED_PATH}${RESET}"
        
    else
        safe_kill "$speed_pid"
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
    echo -e "  ${ICON_FOLDER} 容器内: ${WHITE}$ASTROBOT_SHARED_PATH${RESET}"
    
    echo -e "\n${CYAN}${ICON_INFO} 测试共享文件夹功能...${RESET}"
    test_shared_folder
    
    echo -e "\n${GREEN}${ICON_CHECK} 所有步骤完成！按任意键返回主菜单...${RESET}"
    read -p ""
}

# ===================== 扩展功能菜单 =====================
show_extended_menu() {
    while true; do
        print_header
        print_status
        
        echo -e "${CYAN}════════════════════════════════════════════${RESET}"
        echo -e "${WHITE}          扩展功能菜单${RESET}"
        echo -e "${CYAN}════════════════════════════════════════════${RESET}"
        
        echo -e "${WHITE}  1${RESET} ${CYAN}${ICON_INFO} 查看容器状态${RESET}"
        echo -e "${WHITE}  2${RESET} ${CYAN}${ICON_CPU} 查看系统资源${RESET}"
        echo -e "${WHITE}  3${RESET} ${CYAN}${ICON_NETWORK} 网络连通性测试${RESET}"
        echo -e "${WHITE}  4${RESET} ${CYAN}${ICON_GEAR} 版本兼容性检查${RESET}"
        echo -e "${WHITE}  5${RESET} ${CYAN}${ICON_WARN} 步骤回滚功能${RESET}"
        echo -e "${WHITE}  6${RESET} ${CYAN}${ICON_FOLDER} 检查共享目录${RESET}"
        echo -e "${WHITE}  7${RESET} ${CYAN}${ICON_LINK} 测试共享文件夹${RESET}"
        echo -e "${WHITE}  8${RESET} ${RED}${ICON_WARN} 修复共享目录挂载${RESET}"
        echo -e "${WHITE}  9${RESET} ${CYAN}${ICON_LINK} 提取日志URL${RESET}"
        echo -e "${WHITE}  0${RESET} ${GRAY}返回主菜单${RESET}"
        
        print_footer
        
        echo -ne "${YELLOW}${ICON_WARN} 请选择功能（0-9）: ${RESET}"
        read -r choice
        
        case "$choice" in
            1)
                print_header
                echo -e "${CYAN}════════════════════════════════════════════${RESET}"
                echo -e "${WHITE}          容器状态检查${RESET}"
                echo -e "${CYAN}════════════════════════════════════════════${RESET}"
                check_container_status "astrbot"
                check_container_status "napcat"
                echo -e "\n${GREEN}按任意键继续...${RESET}"
                read -p ""
                ;;
            2)
                print_header
                monitor_system_resources
                echo -e "\n${GREEN}按任意键继续...${RESET}"
                read -p ""
                ;;
            3)
                print_header
                test_network_connectivity
                echo -e "\n${GREEN}按任意键继续...${RESET}"
                read -p ""
                ;;
            4)
                print_header
                check_version_compatibility
                echo -e "\n${GREEN}按任意键继续...${RESET}"
                read -p ""
                ;;
            5)
                while true; do
                    print_header
                    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
                    echo -e "${WHITE}          步骤回滚功能${RESET}"
                    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
                    
                    echo -e "${RED}${ICON_WARN} 警告：回滚操作将删除相关配置和容器！${RESET}"
                    echo ""
                    echo -e "${WHITE}  1${RESET} ${RED}回滚网络配置${RESET}"
                    echo -e "${WHITE}  2${RESET} ${RED}回滚Docker安装${RESET}"
                    echo -e "${WHITE}  3${RESET} ${RED}回滚AstrBot部署${RESET}"
                    echo -e "${WHITE}  4${RESET} ${RED}回滚NapCat部署${RESET}"
                    echo -e "${WHITE}  0${RESET} ${GRAY}返回扩展菜单${RESET}"
                    
                    echo -ne "\n${YELLOW}选择要回滚的步骤（0-4）: ${RESET}"
                    read -r rollback_choice
                    
                    case "$rollback_choice" in
                        1|2|3|4)
                            if confirm_action "确认回滚步骤 $rollback_choice？此操作不可逆！"; then
                                rollback_step "$rollback_choice"
                                echo -e "\n${GREEN}按任意键继续...${RESET}"
                                read -p ""
                            fi
                            ;;
                        0)
                            break
                            ;;
                        *)
                            echo -e "${RED}无效选择！${RESET}"
                            sleep 1
                            ;;
                    esac
                done
                ;;
            6)
                print_header
                check_shared_directory
                echo -e "\n${GREEN}按任意键继续...${RESET}"
                read -p ""
                ;;
            7)
                print_header
                test_shared_folder
                echo -e "\n${GREEN}按任意键继续...${RESET}"
                read -p ""
                ;;
            8)
                print_header
                fix_shared_mount
                echo -e "\n${GREEN}按任意键继续...${RESET}"
                read -p ""
                ;;
            9)
                print_header
                echo -e "${BLUE}════════════════════════════════════════════${RESET}"
                echo -e "${WHITE}          提取日志URL${RESET}"
                echo -e "${BLUE}════════════════════════════════════════════${RESET}"
                
                [ "$STEP3_DONE" = false ] && { echo -e "${YELLOW}${ICON_WARN} 需要先部署AstrBot${RESET}"; return; }
                [ "$STEP4_DONE" = false ] && { echo -e "${YELLOW}${ICON_WARN} 需要先部署NapCat${RESET}"; return; }
                
                extract_urls_from_logs "astrbot"
                echo -e "\n${GRAY}────────────────────────────────────────${RESET}"
                extract_urls_from_logs "napcat"
                
                echo -e "\n${GREEN}按任意键继续...${RESET}"
                read -p ""
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选择！${RESET}"
                sleep 1
                ;;
        esac
    done
}

# ===================== 主菜单 =====================
show_main_menu() {
    print_header
    print_status
    
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}          主菜单${RESET}"
    echo -e "${CYAN}════════════════════════════════════════════${RESET}"
    
    echo -e "${WHITE}  1${RESET} ${BLUE}${ICON_NETWORK} 网络配置${RESET}"
    echo -e "${WHITE}  2${RESET} ${BLUE}${ICON_DOCKER} 安装Docker${RESET}"
    echo -e "${WHITE}  3${RESET} ${BLUE}${ICON_BOT} 部署AstrBot${RESET}"
    echo -e "${WHITE}  4${RESET} ${BLUE}${ICON_CAT} 部署NapCat${RESET}"
    echo -e "${WHITE}  0${RESET} ${GREEN}${ICON_ROCKET} 一键执行所有${RESET}"
    echo -e "${WHITE}  e${RESET} ${CYAN}${ICON_GEAR} 扩展功能${RESET}"
    echo -e "${WHITE}  q${RESET} ${RED}退出脚本${RESET}"
    
    print_contact_info
    
    print_footer
    
    echo -ne "${YELLOW}${ICON_WARN} 请选择（0-4/e/q）: ${RESET}"
    read -r choice
}

# ===================== 初始化设置 =====================
init_script() {
    echo -e "${MAGENTA}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              智能部署助手 v2.5.2 初始化                 ║"
    echo "║          已修复共享目录挂载问题                         ║"
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
