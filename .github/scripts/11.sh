# 仓库状态检查
git_check_repo()
{
	local -n __result="$1"
	local repo_dir="$2"
	
	__result=()
	
	[[ -d "$repo_dir" ]] || {
		_logger "ERROR" "Git目录不存在: $repo_dir"
		return 1
	}
	
	pushd "$repo_dir" >/dev/null || {
		return 1
	}
	
	# 检查 Git 仓库
	if ! git rev-parse \
			--is-inside-work-tree \
			>/dev/null 2>&1; then
		popd >/dev/null
		return 2
	fi
	
	__result[root]=$(git rev-parse --show-toplevel)
	
	# 获取分支
	__result[branch]=$(git symbolic-ref \
		--short HEAD 2>/dev/null)
	
	if [[ -z "${__result[branch]}" ]]; then
		__result[branch]="DETACHED"
	fi
	
	# 获取远端
	__result[remote]=$(git remote | head -n1)
	
	popd >/dev/null
	return 0
}

# 检测是否存在变化
git_check_changes()
{
	local repo_dir="$1"
	
	[[ -d "$repo_dir" ]] || return 1
	
	(
		cd "$repo_dir" || exit 1
		
		git status \
			--porcelain
	)
}

# 提交 + 推送
git_commit_changes()
{
	local -n __result="$1"
	
	local repo_dir="$2"
	local remote="$3"
	local message="$4"
	
	shift 4
	
	local -a files=("$@")
	__result=()
	
	[[ -d "$repo_dir" ]] || {
		_logger "ERROR" "Git仓库不存在: $repo_dir"
		return 1
	}
	
	pushd "$repo_dir" >/dev/null || {
		return 1
	}
	
	_logger "INFO" "准备提交 Git 修改: $repo_dir"
	
	# Git换行规范
	git config core.autocrlf false
	git config core.safecrlf false
	git config core.eol lf
	
	# 重新规范化文件
	git add --renormalize . \
		>/dev/null 2>&1
		
	# 添加文件
	if (( ${#files[@]} > 0 )); then
		git add "${files[@]}" || {
			_logger "ERROR" "Git添加文件失败: ${files[*]}"
			popd >/dev/null
			return 2
		}
	else
		git add . || {
			_logger "ERROR" "Git添加全部文件失败!"
			popd >/dev/null
			return 2
		}
	fi
	
	# 判断是否需要提交
	if git diff --cached --quiet; then
		_logger "INFO" "没有检测到可提交内容!"
		popd >/dev/null
		return 0
	fi
	
	# 提交
	git commit -m "$message" || {
		_logger "INFO" "Git提交内容失败!"
		popd >/dev/null
		return 3
	}
	
	# 获取提交哈希
	local commit_hash=$(git rev-parse --short HEAD)
	
	# 获取分支
	local branch=$(git branch --show-current)
	
	if [[ -z "$branch" ]]; then
		_logger "ERROR" "无法获取当前分支，禁止推送!"
		popd >/dev/null
		return 4
	fi
	
	[[ -n "$remote" ]] || {
		remote="origin"
	}
	
	_logger "INFO" "推送提交: $hash -> $remote/$branch"
	
	# 推送
	git push \
		"$remote" \
		"HEAD:${branch}" || {
		_logger "ERROR" "Git推送失败: $remote/$branch"
		popd >/dev/null
		return 5
	}
	
	# 返回结果
	__result[hash]="$commit_hash"
	__result[branch]="$branch"
	__result[remote]="$remote"
	
	popd >/dev/null
	
	_logger "INFO" "Git提交完成: $hash"
	return 0
}