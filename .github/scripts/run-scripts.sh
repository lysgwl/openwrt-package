#!/bin/bash

#********************************************************************************#
# 提交代码
function check_git_commit() 
{
	# 目标目录路径
	local target_path=$1
	
	# 检查目录是否存在
	if [[ ! -d "$target_path" ]]; then
		echo "[ERROR] 目标目录不存在, 请检查! $target_path"
		return 1
	fi
	
	# 进入目标目录
	pushd "$target_path" > /dev/null || { 
		echo "[ERROR] 目标目录不能进入, 请检查! $target_path"
		return 1		
	}
	
	# 检查是否在 Git 仓库中
	if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		echo "[ERROR] 当前目录不位于工作树, 请检查! $target_path"
		popd >/dev/null
		return 2
	fi

	# 获取当前分支
	local current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
	if [[ -z "$current_branch" ]]; then
		echo "[ERROR] 无法确定当前分支, 请检查!"
		popd >/dev/null
		return 3
	fi

	# 获取远程仓库名称
	local remote_name=$(git remote)
	if [[ -z "$remote_name" ]]; then
		echo "[ERROR] 获取远程仓库的名称, 请检查!"
		popd >/dev/null
		return 4
	fi
	
	# 解决换行符警告配置
	git config core.autocrlf false			# 禁用自动换行符转换
	git config core.safecrlf false			# 禁用安全换行符检查
	git config core.eol lf					# 设置工作区使用 LF 换行符
	
	# 重新规范化换行符
	git add --renormalize . >/dev/null 2>&1

	# 添加所有变更到暂存区
	git add . || {
		echo "[ERROR] 将更改添加到暂存区失败, 请检查!"
		popd >/dev/null
		return 5
	}
	
	# 检查是否有变更
	local has_changes=$(git status --porcelain | grep '^[MADRC]')
	if [[ -n "$has_changes" ]]; then
		# 显示变更摘要
		echo "[INFO] 工作路径检测到修改...$target_path"
		git status
		
		# 创建提交
		local current_date=$(date '+%Y-%m-%d')
		local commit_message="Auto commit changes on ${current_date} [skip ci]"
		
		if ! git commit -m "$commit_message"; then
			echo "[ERROR] 提交发生失败, 请检查! $target_path"
			popd >/dev/null
			return 6
		fi
		
		# 推送变更
		echo "[INFO] 提交修改内容到: $remote_name/$current_branch..."
		if ! git push "$remote_name" "HEAD:$current_branch"; then
			echo "[ERROR] 提交推送到远端发生失败, 请检查! $remote_name/$current_branch"
			popd >/dev/null
			return 7
		fi
	fi

	# 返回原始目录
	popd > /dev/null
	
	echo "[SUCCESS] 成功提交仓库修改! $$target_path => $remote_name/$current_branch"
	return 0
}

#********************************************************************************#
# 添加获取远程仓库内容
function get_remote_repo_contents() 
{
	# 分支名
	local branch=$1
	
	# 远程仓库别名
	local remote_alias=$2
	
	# 远程仓库路径
	local remote_url_path=$3
	
	# 本地目录名
	local local_dir_name=$4
	
	# 相对于顶层目录的路径
	local package_path_rel=$5   
	
	# 添加远程仓库
	echo "add remote repository: $remote_alias"
	git remote add $remote_alias https://github.com/$remote_url_path.git || true
	git fetch $remote_alias
	
	# 转到Git顶层目录
	pushd $(git rev-parse --show-toplevel)
	
	# 计算相对于Git顶层的目标路径
	local target_path="${package_path_rel}/${local_dir_name}"
	
	# 移除路径开头的"./"
	target_path="${target_path#./}"
	
	if [ -d "$target_path" ]; then
		echo "Repository ${local_dir_name} already cloned. Pulling updates..."
		pushd "$target_path"
		
		# 更新远程内容
		git fetch $remote_alias $branch
		
		# 硬重置本地分支
		git reset --hard FETCH_HEAD
		
		popd
	else
		echo "Cloning repository content into the new prefix...$target_path"
		git subtree add --prefix="$target_path" $remote_alias $branch --squash
	fi
	
	popd
}

# 添加获取远程仓库指定内容
function get_remote_spec_contents() 
{
	# 远程仓库URL
	local remote_repo=$1

	# 远程分支名称
	local repo_branch=${2:-main}
	
	# 本地指定路径
	local local_path=$3
	
	if [[ -z "${local_path}" || "${local_path}" == "/" ]]; then
		echo "[ERROR] 无效的本地克隆路径, 请检查! $local_path"
		return 1
	fi
	
	# 解析URL格式: https://domain/repo.git/path?param=value
	if [[ ! "$remote_repo" =~ ^https?://.+\..+ ]]; then
		echo "[ERROR] 无效的远程URL格式, 请检查! $remote_repo"
		return 1
	fi
	
	# 获取.git前缀和后缀字符
	repo_base="${remote_repo%%.git*}"
	path_params="${remote_repo#*.git}"
	
	if [[ -z "${repo_base}" || -z "${path_params}" ]]; then
		echo "[ERROR] URL解析失败, 请检查! $remote_repo"
		return 1
	fi
	
	# URL解析失败
	local repo_url="${repo_base}.git"
	
	# 分离路径和查询参数
	local repo_path="${path_params%%\?*}"
	local query_params="${path_params#*\?}"
	
	# 处理没有查询参数的情况
	if [[ "$query_params" == "$path_params" ]]; then
		query_params=""
	fi
	
	# 远程仓库别名
	local repo_alias="origin"
	if [[ -n "$query_params" ]]; then
		# 尝试从查询参数中获取别名
		if [[ "$query_params" =~ name=([^&]+) ]]; then
			repo_alias="${BASH_REMATCH[1]}"
		elif [[ "$query_params" =~ alias=([^&]+) ]]; then
			repo_alias="${BASH_REMATCH[1]}"
		fi
	fi
	
	# 清理路径开头的斜杠
	repo_path="${repo_path#/}"

	# 创建临时目录并设置自动清理
	local temp_dir=$(mktemp -d)
	trap "rm -rf '${temp_dir}'" EXIT
	
	# 初始化本地目录
	if ! git init -b main ${temp_dir} >/dev/null 2>&1; then
		echo "[ERROR] 临时仓库初始化失败, 请检查!"
		return 2
	fi
	
	# 进入临时目录 (cd ${temp_dir})
	pushd ${temp_dir} > /dev/null
	
	# 添加远程仓库
	if ! git remote show | grep -q "^${repo_alias}$"; then
		echo "[INFO] 添加远程仓库: $repo_alias => $repo_url"
		
		if ! git remote add "${repo_alias}" "${repo_url}"; then
			echo "[ERROR]: 添加远程仓库失败, 请检查! $repo_url"
			
			popd >/dev/null
			return 3
		fi
	fi
	
	# 开启Sparse checkout模式
	git config core.sparsecheckout true
	
	# 配置要检出的目录或文件
	local sparse_file=".git/info/sparse-checkout"
	mkdir -p "$(dirname "${sparse_file}")"
	
	# 清空并写入指定路径
	echo "${repo_path}" > "${sparse_file}"

	# 从远程拉取指定内容
	echo "[INFO] 拉取远程内容(分支: $repo_branch)..."
	if ! git pull "${repo_alias}" "${repo_branch}" >/dev/null 2>&1; then
		echo "[ERROR] 内容拉取失败, 请检查! $repo_branch => $repo_path"
		popd >/dev/null
		return 4
	fi
	
	# 检查源路径是否存在
	local source_path="${temp_dir}/${repo_path}"
	if [[ ! -e "${source_path}" ]]; then
		echo "[ERROR] 远程仓库中不存在指定路径: $repo_path"
		popd >/dev/null
		return 1
	fi
	
	# 准备目标目录
	mkdir -p "${local_path}"
	if [[ $(ls -A "${local_path}" 2>/dev/null) ]]; then
		echo "[INFO] 清理目标目录..."
		rm -rf "${local_path:?}"/*
	fi

	# 复制内容（使用rsync保留隐藏文件）
	echo "[INFO] 复制内容到本地...$source_path => $local_path"
	if [[ -d "${source_path}" ]]; then
		# 目录复制
		rsync -a --exclude='.git' "${source_path}/" "${local_path}/"
	else
		# 文件复制
		cp -f "${source_path}" "${local_path}/"
	fi

	# 返回原始目录
	popd > /dev/null
	
	echo "[SUCCESS] 成功获取远程仓库内容: $repo_url => $local_path"
	return 0
}

# 克隆仓库内容
function clone_repo_contents() 
{
	# 远程仓库URL
	local remote_repo=$1
	
	# 远程分支名称
	local repo_branch=${2:-main}
	
	# 本地指定路径
	local local_path=$3
	
	if [[ -z "${local_path}" || "${local_path}" == "/" ]]; then
		echo "[ERROR]: 无效的本地克隆路径, 请检查! $local_path"
		return 1
	fi
	
	# 临时目录，用于克隆远程仓库
	local temp_dir=$(mktemp -d)
	trap "rm -rf '${temp_dir}'" EXIT

	# 克隆远程仓库到临时目录 ${proxy_cmd}
	echo "[INFO] 克隆远程仓库: ${repo_branch}"
	git clone --depth 1 --branch ${repo_branch} ${remote_repo} ${temp_dir} || {
		echo "[ERROR] 克隆远程仓库失败! $repo_branch => $remote_repo"
		return 2
	}
	
	# 准备目标目录
	mkdir -p "${local_path}"
	 
	# 安全清空 
	rm -rf "${local_path:?}"/* 2>/dev/null	
	
	# 复制内容（包括隐藏文件，排除.git）
	echo "[INFO] 拷贝文件到本地路径..."
	rsync -a --exclude='.git' "${temp_dir}/" "${local_path}/"
	
	echo "[SUCCESS] 成功克隆远程仓库: $remote_repo => $local_path"
	return 0
}

# 同步远程仓库内容
function sync_repo_contents()
{
	# 远程仓库URL
	local remote_repo=$1
	
	# 远程分支名称
	local repo_branch=${2:-main}
	
	# 本地指定路径
	local local_path=$3
	
	if [[ -z "${local_path}" || "${local_path}" == "/" ]]; then
		echo "[ERROR]: 无效的本地克隆路径, 请检查! $local_path"
		return 1
	fi
	
	# 验证URL格式
	if [[ ! "$remote_repo" =~ ^https?:// ]]; then
		echo "[ERROR] 无效的远程URL格式: $remote_repo"
		return 1
	fi
	
	# 获取所有远程分支
	echo "[INFO] 获取远程分支列表...$remote_repo"
	local branch_list
	if ! branch_list=$(git ls-remote --heads "$remote_repo" 2>/dev/null); then
		echo "[ERROR] 无法获取远程仓库分支列表, 请检查! $remote_repo"
		return 2
	fi
	
	if [[ -z "$branch_list" ]]; then
		echo "[WARNING] 未找到任何远程分支: $remote_repo"
		return 0
	fi
	
	local branch_found=0
	
	# 处理分支
	 while read -r commit_hash branch_ref; do
		# 提取分支名称
		local branch_name="${branch_ref##*/}"
		if [[ -z "$branch_name" ]]; then
			continue
		fi
		
		# 如果指定了分支，只处理该分支
		if [[ -n "$repo_branch" && "$repo_branch" != "$branch_name" ]]; then
			continue
		fi
		
		branch_found=1
		echo "[INFO] 处理分支: $branch_name"
		
		# 创建目标路径
		local target_path="$local_path/$branch_name"
		mkdir -p "$target_path"
		
		# 创建临时目录
		local temp_dir=$(mktemp -d)
		trap "rm -rf '${temp_dir}'" EXIT
		
		# 克隆指定分支
		echo "[INFO] 克隆分支: $branch_name"
		
		if ! git clone --depth 1 --single-branch --branch "$branch_name" "$remote_repo" "$temp_dir"; then
			echo "[ERROR] 克隆分支失败: $branch_name"
			rm -rf "$temp_dir"
			continue
		fi
		
		# 同步内容到目标路径
		echo "[INFO] 同步临时目录内容到: $target_path"
		rsync -a --delete --exclude='.git' "$temp_dir/" "$target_path/"
		
		# 清理临时目录
		rm -rf "$temp_dir"
		
	done <<< "$branch_list"
	 
	# 检查是否找到匹配的分支
	if [[ $branch_found -eq 0 ]]; then
		echo "[WARNING] 未找到匹配的分支: $repo_branch"
	fi
	
	echo "[SUCCESS] 成功同步远程仓库: $remote_repo => $local_path"
	return 0
}

# http协议获取远程仓库
function get_http_repo_contents()
{
	# API 请求 URL
	local repo_url=$1
	
	# 本地路径
	local repo_path=$2

	# 发送 API 请求并获取响应
	response=$(curl -s $repo_url)
	
	# 检查是否请求成功
	if [ $? -ne 0 ]; then
		echo "Failed to retrieve repository contents from: $repo_url"
		return
	fi
	
	# 检查处理JSON对象
	check_process_field() {
		local entry=$1
		local field=$2
		
		# 检查entry是否为有效的JSON对象
		type=$(echo "${entry}" | jq '. | type')
		if [[ "${type}" != '"object"' ]]; then
			return
		fi
		
		# 检查字段是否存在于JSON对象中
		has_field=$(echo "${entry}" | jq -e --arg field "${field}" '. | has($field)')
		if [[ "$has_field" != "true" ]]; then
			return
		fi
		
		# 获取字段值
		value=$(echo "$entry" | jq -r ".$field")
		echo "$value"
	}
	
	# 
	#for entry in $(echo "$response" | jq -c '.[]'); do
	echo "$response" | jq -c '.[]' | while IFS= read -r entry; do
		_jq() {
			echo ${entry} | jq -r "${1}"
		}
		
		#echo "$entry"
		fileName=$(check_process_field ${entry} "name")
		if [ -z "${fileName}" ]; then
			continue
		fi
		
		filepath="${repo_path}/${fileName}"
		if [ -z "${filepath}" ]; then
			continue
		fi
		
		filetype=$(check_process_field ${entry} "type")
		if [ -z "${filetype}" ]; then
			continue
		fi
		
		if [ "${filetype}" == "dir" ]; then
			repo_url=$(check_process_field ${entry} "url")
			if [ -z "${repo_url}" ]; then
				continue
			fi
			
			if [ ! -d "${filepath}" ]; then
				mkdir -p ${filepath}
			fi
			
			# 递归检查
			get_http_repo_contents $repo_url $filepath
			
		elif [ "${filetype}" == "file" ]; then
			fileurl=$(check_process_field ${entry} "download_url")
			if [ -z "${fileurl}" ]; then
				continue
			fi
			
			wget ${fileurl} -O ${filepath} -q
		fi
	done
}

#********************************************************************************#
# 克隆远程仓库内容
function get_other_repo()
{
	local package_path_rel=$1
 
	local url="https://github.com/sbwml/luci-app-alist.git"
	clone_repo_contents "$url" "main" "$package_path_rel/luci-app-alist"
	
	local url="https://github.com/sirpdboy/luci-app-ddns-go.git"
	clone_repo_contents "$url" "main" "$package_path_rel/luci-app-ddns-go"
	
	local url="https://github.com/lisaac/luci-app-diskman.git/applications/luci-app-diskman?name=diskman"
	get_remote_spec_contents "$url" "master" "$package_path_rel/luci-app-diskman"
	
	local url="https://github.com/sirpdboy/luci-app-partexp.git"
	clone_repo_contents "$url" "main" "$package_path_rel/luci-app-partexp"

	local url="https://github.com/sirpdboy/luci-app-netwizard.git"
	clone_repo_contents "$url" "main" "$package_path_rel/luci-app-netwizard" 
	
	local url="https://github.com/sirpdboy/luci-app-poweroffdevice.git"
	clone_repo_contents "$url" "js" "$package_path_rel/luci-app-poweroffdevice"
	
	local url="https://github.com/chenmozhijin/luci-app-socat.git"
	clone_repo_contents "$url" "main" "$package_path_rel/luci-app-socat"
	
	local url="https://github.com/destan19/OpenAppFilter.git"
	clone_repo_contents "$url" "master" "$package_path_rel/OpenAppFilter"

	local url="https://github.com/coolsnowwolf/luci.git/applications/luci-app-filetransfer?name=filetransfer"
	get_remote_spec_contents "$url" "master" "$package_path_rel/luci-app-filetransfer"
}

# 获取远程仓库内容
function get_remote_repo()
{
	local package_path_rel=$1
	
	# coolsnowwolf
	local url="https://github.com/coolsnowwolf/luci.git/applications?name=coolsnowwolf"
	# get_remote_spec_contents "$url" "master" "$package_path_rel/coolsnowwolf"
	
	local url="https://api.github.com/repos/coolsnowwolf/luci/contents/applications?ref=master"
	# get_http_repo_contents "$url" "${package_path_rel}"
	
	# shidahuilang
	local url="https://github.com/shidahuilang/openwrt-package.git"
	sync_repo_contents "$url" "Official" "${package_path_rel}/shidahuilang"
	
	# kiddin9
	local url="https://github.com/kiddin9/openwrt-packages.git?ref=master"
	#sync_repo_contents "$url" "${package_path_rel}"
}
