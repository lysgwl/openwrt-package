#!/bin/bash

#********************************************************************************#
# 提交代码
function check_git_commit() 
{
	# 目标目录路径
	local target_path=$1
	
	# 进入目标目录
	pushd "$target_path" > /dev/null || { echo "Error: Unable to change directory to $target_path"; exit 1; }
	
	# 将所有变更添加到暂存区
	git add .
	
	# 输出git状态
	git status
	
	# 检查git状态
	local has_changes=$(git status --porcelain | grep '^[MADRC]')
	if [ -n "$has_changes" ]; then
		current_date=$(date '+%Y-%m-%d')
		
		git commit -a -m "commit repository changes on ${current_date} [skip ci]"
		git push git@github.com:lysgwl/openwrt-package.git HEAD:master
	fi
	
	# 递归检查子目录的git状态
	#for subdir in */; do
	#	if [ -d "$subdir" ]; then
	#		check_git_commit "$subdir"
	#	fi
	#done
	
	# 返回原始目录
    popd > /dev/null
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
	git clone --depth 1 --branch ${repo_branch} ${repo_url} ${temp_dir} || {
		echo "[ERROR] 克隆远程仓库失败! URL:$repo_url, 分支:$repo_branch"
		return
	}
	
	# 准备目标目录
	mkdir -p "${local_path}"
	 
	# 安全清空 
	rm -rf "${local_path:?}"/* 2>/dev/null	
	
	# 复制内容（包括隐藏文件，排除.git）
	 echo "[INFO] 拷贝文件到本地路径..."
	rsync -a --exclude='.git' "${temp_dir}/" "${local_path}/"
}

# 同步远程仓库内容
function sync_repo_contents()
{
	# 远程仓库URL
	local remote_repo=$1        
	local local_path=$2
	
	# 获取?前缀和后缀字符
	mark_prefix="${remote_repo%%\?*}"
	mark_suffix="${remote_repo#*\?}"
	
	if [ -z "${mark_prefix}" ] || [ -z "${mark_suffix}" ]; then
		return
	fi
	
	# 远程仓库URL
	repo_url="${mark_prefix}"
	
	# 远程分支名称
	repo_branch=$(echo ${mark_suffix} | awk -F '=' '{print $2; exit}')

	git ls-remote --heads ${repo_url} | while read -r line ; do
		branch_name=$(echo $line | sed 's?.*refs/heads/??')
		if [ -z "${branch_name}" ]; then
			continue
		fi
		
		# 分支比较
		if [ -n "${repo_branch}" ]; then
			if [ "${repo_branch}" != "${branch_name}" ]; then
				continue
			fi
		fi
		
		echo "Current branch name: $branch_name"
		
		local target_path="${local_path}/${branch_name}"
		if [ ! -d "${target_path}" ]; then
			mkdir -p "${target_path}"
		fi
		
		# 临时目录，用于克隆远程仓库
		local temp_dir=$(mktemp -d)
		
		# 克隆远程仓库到临时目录
		git clone --single-branch --branch ${branch_name} ${repo_url} ${temp_dir}
		
		if [ $? -eq 0 ]; then
			rsync -a --delete ${temp_dir}/ ${target_path}/ --exclude .git
		fi
		
		rm -rf ${temp_dir}
	done
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
function clone_remote_repo()
{
	repo_other_cond=$1
	package_path_rel=$2
 
	if [ ${repo_other_cond} -eq 1 ]; then
		url="https://github.com/sbwml/luci-app-alist.git"
		clone_repo_contents "${url}" "main" "${package_path_rel}/luci-app-alist"
		
		url="https://github.com/sirpdboy/luci-app-ddns-go.git"
		clone_repo_contents "${url}" "main" "${package_path_rel}/luci-app-ddns-go"
		
		url="https://github.com/lisaac/luci-app-diskman.git/applications/luci-app-diskman?name=diskman"
		get_remote_spec_contents "${url}" "master" "${package_path_rel}/luci-app-diskman"

  		url="https://github.com/sirpdboy/luci-app-partexp.git"
    	clone_repo_contents "${url}" "main" "${package_path_rel}/luci-app-partexp"

      	url="https://github.com/sirpdboy/luci-app-netwizard.git"
		clone_repo_contents "${url}" "main" "${package_path_rel}/luci-app-netwizard"
		
		url="https://github.com/sirpdboy/luci-app-poweroffdevice.git"
		clone_repo_contents "${url}" "main" "${package_path_rel}/luci-app-poweroffdevice"
		
		url="https://github.com/chenmozhijin/luci-app-socat.git"
		clone_repo_contents "${url}" "main" "${package_path_rel}/luci-app-socat"
		
		url="https://github.com/destan19/OpenAppFilter.git"
		clone_repo_contents "${url}" "master" "${package_path_rel}/OpenAppFilter"

      	url="https://github.com/coolsnowwolf/luci.git/applications/luci-app-filetransfer?ref=master"
    	# get_remote_spec_contents "${url}" "filetransfer" "${package_path_rel}/luci-app-filetransfer"
	fi
}

# 获取远程仓库内容
function get_remote_repo()
{
	repo_remote_cond=$1
	package_path_rel=$2
	
	if [ ${repo_remote_cond} -eq 1 ]; then
		url="https://github.com/coolsnowwolf/luci.git/applications?ref=master"
		get_remote_spec_contents "$url" "coolsnowwolf" "${package_path_rel}"
	fi
	
	if [ ${repo_remote_cond} -eq 2 ]; then
		url="https://api.github.com/repos/coolsnowwolf/luci/contents/applications?ref=master"
		get_http_repo_contents "$url" "${package_path_rel}"
	fi

	if [ ${repo_remote_cond} -eq 3 ]; then
		url="https://github.com/shidahuilang/openwrt-package.git?ref=Official"
		sync_repo_contents "$url" "${package_path_rel}"
	fi

	if [ ${repo_remote_cond} -eq 4 ]; then
		url="https://github.com/kiddin9/openwrt-packages.git?ref=master"
		sync_repo_contents "$url" "${package_path_rel}"
	fi	
}
