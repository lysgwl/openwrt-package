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

# 仓库配置脚本
: ${REPO_CONFIG:="$SCRIPT_ROOT/repo_config.sh"}

# 加载仓库脚本
source $REPO_CONFIG || exit 1

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

# 导出仓库配置
_export_repo_config()
{
	local repo_name="$1"
	local config="$2"
	local target_root="$3"
	
	if [[ -z "$config" ]]; then
		log_console "ERROR" "仓库配置为空: $repo_name"
		return 1
	fi
	
	local url=$(jq -r '.url // empty' <<< "$config")
	local type=$(jq -r '.type // empty' <<< "$config")
	local ref=$(jq -r '.ref // empty' <<< "$config")
	local path=$(jq -r '.path // empty' <<< "$config")
	local enabled=$(jq -r '.enabled // true' <<< "$config")
	
	if [[ -z "$url" ||
		  -z "$type" ||
		  -z "$ref" ]]; then
		log_console "ERROR" "仓库配置不完整: $repo_name"
		return 1
	fi
	
	# 配置是否启用
	[[ "$enabled" == "true" ]] || return 0
	
	# 默认目标目录
	local target_name=$(jq -r '.target // empty' <<< "$config")
	
	if [[ -z "$target_name" ]]; then
		target_name="$repo_name"
	fi
	
	local target="$target_root/$target_name"
	log_console "INFO" "导出仓库: $repo_name -> $target"
	
	case "$type" in
		repo)
			git_export_repo \
				"$url" \
				"$ref" \
				"$target"
			;;
		contents)
			if [[ -z "$path" ]]; then
				log_console "ERROR" "缺少 path 数据配置: $repo_name"
				return 1
			fi
			
			git_export_repo_contents \
				"${url}?ref=${ref}#${path}" \
				"origin" \
				"$target"
			;;
		branches)
			git_export_branches \
				"$url" \
				"$ref" \
				"$target"
			;;
		*)
			log_console "ERROR" "未知仓库类型: $type"
			return 1
			;;
	esac
	
	return $?
}

# ============================================================================
# 更新 other 仓库
update_other_package()
{
	local package_path="$1"
	
	if [[ -z "$package_path" ]]; then
		log_console "ERROR" "参数路径不能为空: $package_path"
		return 1
	fi
	
	local repo_name
	for repo_name in "${!OTHER_REPO_CONFIG[@]}"; do
		local json_config="${OTHER_REPO_CONFIG[$repo_name]}"
		[[ -n "$json_config" ]] || continue
		
		_export_repo_config \
			"$repo_name" \
			"$json_config" \
			"$package_path" || {
			log_console " 仓库 $repo_name 导出失败!"
			continue
		}
	done
	
	return 0
}

# 更新 remote 仓库
update_remote_repo()
{
	local package_path="$1"
	
	if [[ -z "$package_path" ]]; then
		log_console "ERROR" "参数路径不能为空: $package_path"
		return 1
	fi
	
	local repo_name
	for repo_name in "${!REMOTE_REPO_CONFIG[@]}"; do
		local json_config="${REMOTE_REPO_CONFIG[$repo_name]}"
		[[ -n "$json_config" ]] || continue
		
		_export_repo_config \
			"$repo_name" \
			"$json_config" \
			"$package_path" || {
			log_console " 仓库 $repo_name 导出失败!"
			continue
		}
	done
	
	return 0
}

# 自动加载 utils 模块
_auto_load_utils || return 1