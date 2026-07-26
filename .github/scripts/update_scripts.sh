#!/bin/bash
#
set -e

# 脚本目录
: ${SCRIPT_ROOT:="${GITHUB_WORKSPACE}/.github/scripts"}

# system-utils 名称
: ${SYSTEM_DIR:="system-utils"}

# system-utils 根目录
: ${SYSTEM_ROOT:="${SCRIPT_ROOT}/${SYSTEM_DIR}"}

# 通用工具目录
: ${UTILS_ROOT:="$SYSTEM_ROOT/utils"}

# ============================================================================
# 打印日志
logger()
{
	local level="$1"
	local message="${2:-}"
	local func="${3:-}"
	local file="${4:-}"
	
	if declare -F print_log &>/dev/null; then
		print_log "$level" "$message" "$func" "$file"
		return $?
	fi
	
	local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
	local log_entry="[$timestamp] [$level]"
	
	[[ -n "$func" ]] && log_entry+=" ($func)"
	log_entry+=" ${message:-No message}"
	
	case "$level" in
		ERROR|FATAL|WARNING)
			printf '%s\n' "$log_entry" >&2
			;;
		*)
			printf '%s\n' "$log_entry"
			;;
	esac
	
	[[ -n "$file" ]] && \
		printf '%s\n' "$log_entry" >> "$file" 2>/dev/null || true
}

# 控制台输出
log_console()
{
	logger "$1" "${2:-}" "${3:-}"
}

# ============================================================================
# 加载通用工具脚本
_auto_load_utils()
{
	# 检查是否已加载
	[[ "${UTILS_LOADED:-0}" == "1" ]] && return 0
	
	# 检查通用工具目录
	if [[ ! -d "$UTILS_ROOT" ]]; then
		log_console "ERROR" "通用工具不存在: $UTILS_ROOT"
		return 2
	fi
	
	# feature入口文件
	local feature_file="$UTILS_ROOT/feature.sh"
	
	if [[ ! -f "${feature_file}" ]]; then
		log_console "ERROR" "入口脚本 feature.sh 不存在: $feature_file"
		return 3
	fi
	
	log_console "INFO" "加载通用工具入口脚本: $feature_file"
	
	# 加载 feature.sh
	if ! source "${feature_file}"; then
		log_console "ERROR" "加载工具入口失败: $feature_file"
		return 4
	fi
	
	# 检查 load_featur e函数是否存在
	if ! declare -f load_feature >/dev/null; then
		log_console "ERROR" "load_feature初始函数未定义!"
		return 5
	fi
	
	# 执行加载
	load_feature
	
	# 设置加载标记
	export UTILS_LOADED="1"
}

# ============================================================================
# 更新 other 包
update_other_package()
{
	local package_path="$1"
	
	if [[ -z "$package_path" ]]; then
		log_console "ERROR" "提供的包路径为空: $package_path"
		return 1
	fi
	
	# luci-app-ddns-go
	git_export_repo \
		"https://github.com/sirpdboy/luci-app-ddns-go.git" \
		"main" \
		"${package_path}/luci-app-ddns-go"
		
	# luci-app-partexp
	git_export_repo \
		"https://github.com/sirpdboy/luci-app-partexp.git" \
		"main" \
		"${package_path}/luci-app-partexp"
		
	# luci-app-netwizard
	git_export_repo \
		"https://github.com/sirpdboy/luci-app-netwizard.git" \
		"main" \
		"${package_path}/luci-app-netwizard"
	
	# luci-app-poweroffdevice
	git_export_repo \
		"https://github.com/sirpdboy/luci-app-poweroffdevice.git" \
		"master" \
		"${package_path}/luci-app-poweroffdevice"
	
	# luci-app-socat
	git_export_repo \
		"https://github.com/chenmozhijin/luci-app-socat.git" \
		"main" \
		"${package_path}/luci-app-socat"
		
	# OpenAppFilter
	git_export_repo \
		"https://github.com/destan19/OpenAppFilter.git" \
		"master"
		"${package_path}/OpenAppFilter"
	return 0
}

# 自动加载 utils 模块
_auto_load_utils || return 1