#!/bin/bash

#********************************************************************************#
# 添加获取远程仓库内容
function get_remote_repo_contents() 
{
	local branch=$1             # 分支名
	local remote_alias=$2       # 远程仓库别名
	local remote_url_path=$3    # 远程仓库路径
	local local_dir_name=$4     # 本地目录名
	local package_path_rel=$5   # 相对于顶层目录的路径
	
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
	local branch=$1             # 分支名
	local remote_alias=$2       # 远程仓库别名
	local remote_url_path=$3    # 远程仓库路径
	local remote_spec_path=$4   # 远程指定路径
	local local_spec_path=$5    # 本地指定路径
	
	# 临时目录，用于克隆远程仓库
	local temp_dir=$(mktemp -d)
	
	# 初始化本地目录
	git init -b main ${temp_dir}
	
	# 进入临时目录
	cd ${temp_dir}
	
	# 添加远程仓库
	echo "add remote repository: $remote_alias"
	git remote add $remote_alias https://github.com/$remote_url_path.git || true
	
	# 开启Sparse checkout模式
	git config core.sparsecheckout true
	
	# 配置要检出的目录或文件
	sparse_file=".git/info/sparse-checkout"
	if [ ! -e "${sparse_file}" ]; then
		touch "${sparse_file}"
	fi
	
	echo "${remote_spec_path}" >> ${sparse_file}
	echo "Pulling from $remote_alias branch $branch..."
	
	# 从远程将目标目录或文件拉取下来
	git pull ${remote_alias} ${branch}
	
	# 判断目标目录是否为空
	if [ ! -z "$(ls -A ${local_spec_path})" ]; then
		rm -rf "${local_spec_path:?}"/*  
	fi

	if [ -e "${temp_dir}/${remote_spec_path}" ]; then
		cp -rf ${temp_dir}/${remote_spec_path}/* ${local_spec_path}
		#mv ${temp_dir}/${remote_spec_path}/* ${local_spec_path}
	fi
	
	# 清理临时目录
	rm -rf $temp_dir
}

# 克隆仓库内容
function clone_repo_contents() 
{
	local remote_repo=$1        # 远程仓库URL
	local branch=$2             # 分支名
	local local_dir_name=$3     # 本地目录名
	local package_path_rel=$4   # 相对于顶层目录的路径
	
	# 临时目录，用于克隆远程仓库
	local temp_dir=$(mktemp -d)
	
	# 克隆远程仓库到临时目录
	git clone --depth 1 --branch $branch $remote_repo $temp_dir
	
	if [ $? -eq 0 ]; then
		local target_path="$package_path_rel/$local_dir_name"
		
		if [ -d "$target_path" ]; then
			echo "Removing old files from $target_path."
			
			# 使用:?防止变量为空时删除根目录
			rm -rf "${target_path:?}"/*  
		else
			# 如果目标路径不存在，创建目标路径
			mkdir -p "$target_path"
		fi
		# 创建目标路径
		mkdir -p "$package_path_rel/$local_dir_name"
	
		# 复制克隆的内容到目标路径
		cp -r $temp_dir/* "$package_path_rel/$local_dir_name/"
	fi
	
	# 清理临时目录
	rm -rf $temp_dir
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
# 获取远程仓库包
function get_retmote_repo_package()
{
	get_remote_repo_contents master diskman lisaac/luci-app-diskman luci-app-diskman $1
	get_remote_repo_contents main ddns-go sirpdboy/luci-app-ddns-go luci-app-ddns-go $1
	get_remote_repo_contents master OpenAppFilter destan19/OpenAppFilter luci-app-OpenAppFilter $1
	get_remote_repo_contents master poweroff esirplayground/luci-app-poweroff luci-app-poweroff $1
	get_remote_repo_contents main socat chenmozhijin/luci-app-socat luci-app-socat $1
}

# 获取远程仓库内容
function get_remote_repo()
{
	repo_remote_cond=$1
	
	if [ $repo_remote_cond -eq 1 ]; then
		package_path_rel="$1"		# 相对于git顶层目录的路径
		mkdir -p "$package_path_rel"
		
		# 获取当前的HEAD哈希值
        original_head=$(git rev-parse HEAD)
		
		# 获取远程仓库的包
		get_retmote_repo_package $package_path_rel
		
		# 获取新的HEAD哈希值
        new_head=$(git rev-parse HEAD)
		
		# 根据哈希值判断状态
        if [[ "$original_head" != "$new_head" ]]; then
            status="successful"
        else
            status="no_changes"
        fi
        
        echo "repo_status=$status" >> $GITHUB_ENV
	else
		package_path_rel="${PWD}/${1}/coolsnowwolf"
		mkdir -p "$package_path_rel"
		
		get_remote_spec_contents "master" "lede" "coolsnowwolf/luci" "applications" ${package_path_rel}
	fi
}

# 克隆远程仓库内容
function clone_remote_repo()
{
	package_path_rel="$1"		# 相对于git顶层目录的路径
	mkdir -p "$package_path_rel"
	
	clone_repo_contents https://github.com/lisaac/luci-app-diskman.git master luci-app-diskman $package_path_rel
	clone_repo_contents https://github.com/sirpdboy/luci-app-ddns-go.git main luci-app-ddns-go $package_path_rel
	clone_repo_contents https://github.com/destan19/OpenAppFilter.git master luci-app-OpenAppFilter $package_path_rel
	clone_repo_contents https://github.com/esirplayground/luci-app-poweroff.git master luci-app-poweroff $package_path_rel
	clone_repo_contents https://github.com/chenmozhijin/luci-app-socat.git main luci-app-socat $package_path_rel
}

# http协议获取远程仓库内容
function get_remote_http_repo()
{
	package_path_rel="$1/coolsnowwolf"		# 相对于git顶层目录的路径
	mkdir -p "$package_path_rel"
	
	# 请求 URL (branch,repo_owner,repo_name,repo_path)
    url="https://api.github.com/repos/coolsnowwolf/luci/contents/applications?ref=master"
	get_http_repo_contents $url $package_path_rel
}

# 提交代码
function check_git_commit() 
{
	# 目标目录路径
	local target_path=$1   
	
	# 进入目标目录
	cd "$target_path" || { echo "Error: Unable to change directory to $target_path"; exit 1; }
	
	# 将所有变更添加到暂存区
	git add .
	
	# 输出git状态
	git status
	
	# 检查git状态
	local has_changes=$(git status --porcelain | grep '^[MADRC]')
	if [ -n "$has_changes" ]; then
		current_date=$(date '+%Y-%m-%d')
		
		git commit -a -m "commit repository  changes on $current_date"
		git push git@github.com:lysgwl/openwrt-package.git HEAD:master
	fi
	
	# 递归检查子目录的git状态
	for subdir in */; do
		if [ -d "$subdir" ]; then
			check_git_commit "$subdir"
		fi
	done
}