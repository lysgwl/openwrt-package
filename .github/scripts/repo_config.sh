#!/bin/bash
#

# other package 仓库
declare -gA OTHER_REPO_CONFIG=(
	[luci-app-ddns-go]='{
		"url":"https://github.com/sirpdboy/luci-app-ddns-go.git",
		"type":"repo",
		"ref":"main"
	}'
	[luci-app-partexp]='{
		"url":"https://github.com/sirpdboy/luci-app-partexp.git",
		"type":"repo",
		"ref":"main"
	}'
	[luci-app-netwizard]='{
		"url":"https://github.com/sirpdboy/luci-app-netwizard.git",
		"type":"repo",
		"ref":"main"
	}'
	[luci-app-poweroffdevice]='{
		"url":"https://github.com/sirpdboy/luci-app-poweroffdevice.git",
		"type":"repo",
		"ref":"master"
	}'
	[luci-app-socat]='{
		"url":"https://github.com/chenmozhijin/luci-app-socat.git",
		"type":"repo",
		"ref":"main"
	}'
	[luci-app-openlist2]='{
		"url":"https://github.com/sbwml/luci-app-openlist2.git",
		"type":"repo",
		"ref":"main"
	}'
	[OpenAppFilter]='{
		"url":"https://github.com/destan19/OpenAppFilter.git",
		"type":"repo",
		"ref":"master"
	}'
	[luci-app-diskman]='{
		"url":"https://github.com/lisaac/luci-app-diskman.git",
		"type":"contents",
		"ref":"master",
		"path":"applications/luci-app-diskman"
	}'
)

# remote package仓库
declare -gA REMOTE_REPO_CONFIG=(
	[coolsnowwolf]='{
		"url":"https://github.com/coolsnowwolf/luci.git",
		"type":"contents",
		"ref":"master",
		"path":"applications"
	}'
	[shidahuilang]='{
		"url":"https://github.com/shidahuilang/openwrt-package.git",
		"type":"branches",
		"ref":"Lede"
	}'
)