#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#安装和更新软件包
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)  # 第5个参数为自定义名称列表
	local REPO_NAME=${PKG_REPO#*/}
	local REPO_PATH="./package/$REPO_NAME"

	echo " "

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		# 查找匹配的目录
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ./feeds/luci/ ./feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		# 删除找到的目录
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not fonud directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch $PKG_BRANCH "https://github.com/$PKG_REPO.git" $REPO_PATH

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find $REPO_PATH/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./package \;
		rm -rf $REPO_PATH
	fi
}

# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"
# UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf" 这样会把原有的open-app-filter，luci-app-appfilter，oaf相关组件删除，不会出现coremark错误。

# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg，可选，从大杂烩中单独提取包名插件"
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"
UPDATE_PACKAGE "fluent" "LazuliKao/luci-theme-fluent" "main"
UPDATE_PACKAGE "footstrap" "VizzleTF/luci-theme-footstrap" "main"
UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "kucat-config" "sirpdboy/luci-app-kucat-config" "master"
UPDATE_PACKAGE "shadcn" "eamonxg/luci-theme-shadcn" "main"
UPDATE_PACKAGE "vantage" "anothaDev/luci-theme-vantage" "main"

UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
# pushbot：自动选取上游最新 tag（形如 luci-app-pushbot-v6.01-r17），取不到则回退默认分支 master
# git clone https://github.com/zzsj0928/luci-app-pushbot package/luci-app-pushbot
UPDATE_PACKAGE "pushbot" "zzsj0928/luci-app-pushbot" "master"
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac miniupnpd sing-box luci-app-homeproxy luci-app-timewol luci-app-upnp luci-app-wolplus luci-app-wolultra"

UPDATE_PACKAGE "diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"
UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"

# 注意：包名必须写 luci-app-tailscale，不能写 tailscale
# 否则 UPDATE_PACKAGE 的清理逻辑会连 ./feeds/packages/net/tailscale（后端本体）一起删掉，
# 导致 luci-app-tailscale 的 +tailscale 依赖无包可满足，package/install 阶段报 no such package
UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"
# tailscale 后端自带的 init/config 与 luci-app-tailscale 冲突，移除后端同名文件定义
if [ -f ./feeds/packages/net/tailscale/Makefile ]; then
	sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;' ./feeds/packages/net/tailscale/Makefile
fi

# ======================================================================================
# tailscale 运行时修复：直接改写克隆下来的 luci-app-tailscale 包内容（随包安装，无需 files/ 覆盖层）
#   问题1 接口地址闪断：上游 init 同时起两个 procd 实例（tailscaled 与 tailscale_helper），
#         helper 退出码 1 触发 procd crash loop，接口反复 down/up；同时 netifd 里残留
#         proto=static、ipaddr=100.66.6.1/8 的 network.tailscale，与 tailscaled 争抢 tailscale0 地址
#   问题1b hotplug 循环：上游 hotplug 在任意接口 ifup/ifupdate 都执行 start，
#         而 tailscaled 拉起 tailscale0 本身也会产生 ifup 事件，形成 start→up→start 自激重启
#   问题2 日志 ACL：上游 ACL 只授权 /sbin/logread，而 logread 实际位于 /usr/sbin，
#         LuCI 日志页 exec 被 rpcd 拒绝：PermissionError: Access to command denied by ACL
# ======================================================================================
TS_PKG_DIR="./package/luci-app-tailscale"

if [ -d "$TS_PKG_DIR/root" ]; then
	# ---- 1. 替换 init 脚本：单实例 tailscaled + 保留 tailscale0 在「网络-接口」的显示 + 异步同步 UI 选项 ----
	mkdir -p "$TS_PKG_DIR/root/etc/init.d"
	cat > "$TS_PKG_DIR/root/etc/init.d/tailscale" <<'TS_INIT_EOF'
#!/bin/sh /etc/rc.common

# Tailscale service（构建侧修复版）
# 1) 只启动一个 tailscaled 实例，不再起 tailscale_helper，避免 procd crash loop
# 2) 保留官方形态的 network.tailscale 段（proto=none + device=tailscale0），让 tailscale0 正常显示在「网络-接口」，但不携带地址，避免 netifd 与 tailscaled 争抢 tailscale0
# 3) UI 选项通过 `tailscale set` 异步下发（该子命令不会触发登录）

START=90
STOP=10
USE_PROCD=1

PROGD=/usr/sbin/tailscaled
TSCLI=/usr/sbin/tailscale
SOCK=/var/run/tailscale/tailscaled.sock

# 让 tailscale0 按官方形态出现在「网络 - 接口」：
# 保留一个 network.tailscale 段（proto=none + device=tailscale0），netifd 只托管展示、不配任何地址，
# 因此既不会从列表里消失，也不会与 tailscaled 争抢同一张网卡（地址闪断的真正根因是地址字段，不是段本身）。
ensure_netifd_interface() {
	local s o changed=0

	# 1) 清掉除 network.tailscale 之外、同样指向 tailscale0 的重复段
	for s in $(uci -q show network 2>/dev/null | grep -E "\.(device|ifname)='tailscale0'" | cut -d. -f2 | sort -u); do
		[ "$s" = "tailscale" ] && continue
		uci -q delete network."$s"
		changed=1
		echo "tailscale: removed duplicate netifd section network.$s (device=tailscale0)"
	done

	# 2) 确保 tailscale 接口段存在，且固定为 proto=none + device=tailscale0
	[ "$(uci -q get network.tailscale)" = "interface" ] || { uci -q set network.tailscale='interface'; changed=1; }
	[ "$(uci -q get network.tailscale.proto)" = "none" ] || { uci -q set network.tailscale.proto='none'; changed=1; }
	[ "$(uci -q get network.tailscale.device)" = "tailscale0" ] || { uci -q set network.tailscale.device='tailscale0'; changed=1; }

	# 3) 删掉会让 netifd 参与配地址/路由的字段（这些字段才是把 tailscale0 变成"抢地址接口"的原因）
	for o in ifname ipaddr netmask ip6addr ip6prefix ip6assign gateway ip6gw dns broadcast; do
		[ -n "$(uci -q get network.tailscale.$o)" ] && { uci -q delete network.tailscale."$o"; changed=1; }
	done

	[ "$changed" = "1" ] || return 0

	uci commit network
	# 新写入的段要等 netifd 重新加载后才会出现在「网络-接口」；期间用标记文件挡住 hotplug 递归
	touch /tmp/.tailscale_netifd_busy
	/etc/init.d/network reload >/dev/null 2>&1
	( sleep 5; rm -f /tmp/.tailscale_netifd_busy ) &
	echo "tailscale: netifd section network.tailscale normalized (proto=none, device=tailscale0)"
	return 0
}

start_service() {
	config_load tailscale
	config_foreach start_instance tailscale
}

start_instance() {
	local cfg="$1"
	local enabled port config_path fw_mode log_stdout log_stderr

	config_get_bool enabled "$cfg" 'enabled' 0
	if [ "$enabled" != "1" ]; then
		echo "tailscale: disabled in /etc/config/tailscale"
		return 0
	fi

	config_get port "$cfg" 'port' 41641
	config_get config_path "$cfg" 'config_path' /etc/tailscale
	config_get_bool log_stdout "$cfg" 'log_stdout' 1
	config_get_bool log_stderr "$cfg" 'log_stderr' 1

	[ -n "$config_path" ] || config_path=/etc/tailscale
	mkdir -p "$config_path"
	mkdir -p /var/run/tailscale

	# 纯 nftables 固件：不引入 iptables 兼容层，防火墙模式一律 nftables
	fw_mode=nftables

	ensure_netifd_interface

	/usr/sbin/tailscaled --cleanup >/dev/null 2>&1

	procd_open_instance
	procd_set_param command "$PROGD"
	procd_append_param command --port "$port"
	procd_append_param command --state "$config_path/tailscaled.state"
	procd_set_param env TS_DEBUG_FIREWALL_MODE="$fw_mode"
	procd_append_param env TS_NO_LOGS_NO_SUPPORT=true
	procd_set_param respawn 3600 5 0
	procd_set_param stdout "$log_stdout"
	procd_set_param stderr "$log_stderr"
	procd_close_instance

	apply_settings "$cfg" &
}

apply_settings() {
	local cfg="$1"
	local accept_routes accept_dns advertise_exit_node exit_node
	local advertise_routes disable_snat authkey login_server flags hostname
	local args="" i=0

	config_get accept_routes "$cfg" 'accept_routes' 1
	config_get accept_dns "$cfg" 'accept_dns' 1
	config_get advertise_exit_node "$cfg" 'advertise_exit_node' 0
	config_get exit_node "$cfg" 'exit_node'
	config_get advertise_routes "$cfg" 'advertise_routes'
	config_get disable_snat "$cfg" 'disable_snat_subnet_routes' 0
	config_get authkey "$cfg" 'authkey'
	config_get login_server "$cfg" 'login_server'
	config_get flags "$cfg" 'flags'
	config_get hostname "$cfg" 'hostname'

	[ "$accept_routes" = "1" ] && args="$args --accept-routes=true" || args="$args --accept-routes=false"
	[ "$accept_dns" = "0" ] && args="$args --accept-dns=false" || args="$args --accept-dns=true"
	[ "$advertise_exit_node" = "1" ] && args="$args --advertise-exit-node=true" || args="$args --advertise-exit-node=false"
	[ -n "$exit_node" ] && args="$args --exit-node=$exit_node --exit-node-allow-lan-access=true" || args="$args --exit-node="
	[ -n "$advertise_routes" ] && args="$args --advertise-routes=$(echo "$advertise_routes" | tr ' ' ',')"
	[ -n "$hostname" ] && args="$args --hostname=$hostname"
	[ "$disable_snat" = "1" ] && args="$args --snat-subnet-routes=false" || args="$args --snat-subnet-routes=true"

	while [ $i -lt 30 ]; do
		[ -S "$SOCK" ] && break
		sleep 1
		i=$((i + 1))
	done

	if [ ! -S "$SOCK" ]; then
		echo "tailscale: socket $SOCK not ready, skip applying settings"
		return 0
	fi

	$TSCLI set $args >/dev/null 2>&1
	[ -n "$login_server" ] && flags="$flags --login-server=$login_server"
	[ -n "$authkey" ] && $TSCLI up --authkey="$authkey" $args $flags >/dev/null 2>&1
	return 0
}

stop_service() {
	[ -x /usr/sbin/tailscaled ] && /usr/sbin/tailscaled --cleanup >/dev/null 2>&1
	return 0
}

reload_service() {
	stop
	start
}

service_triggers() {
	procd_add_reload_trigger "tailscale"
}
TS_INIT_EOF
	chmod 0755 "$TS_PKG_DIR/root/etc/init.d/tailscale"
	echo "tailscale: init script replaced"

	# ---- 1.1 替换 hotplug 脚本：原版在任意接口 ifup/ifupdate 时都执行 start，
	#          与 tailscaled 自己拉起 tailscale0 的事件互相触发，形成 start->up->start 循环 ----
	mkdir -p "$TS_PKG_DIR/root/etc/hotplug.d/iface"
	cat > "$TS_PKG_DIR/root/etc/hotplug.d/iface/40-tailscale" <<'TS_HOTPLUG_EOF'
#!/bin/sh

# 接口上线时确保 tailscaled 在跑：
# 1) 进程已在运行则直接退出——tailscaled 拉起 tailscale0 本身也会产生 ifup 事件，
#    原版无条件 start 会形成 start→up→start 自激重启并导致 IPv4 闪断
# 2) 不限定接口名，避免 WAN 被改成 pppoe-wan 等名称后服务永不启动

[ "$ACTION" = "ifup" ] || exit 0
# init 正在规范化 network.tailscale 段并 reload netifd 时不要响应，避免 start→reload→start 递归
[ -f /tmp/.tailscale_netifd_busy ] && exit 0
[ "$(uci -q get tailscale.settings.enabled)" = "1" ] || exit 0
pgrep -f /usr/sbin/tailscaled >/dev/null 2>&1 && exit 0
/etc/init.d/tailscale start >/tmp/tailscale.log 2>&1 &
TS_HOTPLUG_EOF
	chmod 0755 "$TS_PKG_DIR/root/etc/hotplug.d/iface/40-tailscale"
	echo "tailscale: hotplug script replaced"

	# ---- 2. 重写 ACL：补齐 logread 双路径与 tailscale 子命令，修复日志页 ACL 拒绝 ----
	mkdir -p "$TS_PKG_DIR/root/usr/share/rpcd/acl.d"
	cat > "$TS_PKG_DIR/root/usr/share/rpcd/acl.d/luci-app-tailscale.json" <<'TS_ACL_EOF'
{
	"luci-app-tailscale": {
		"description": "Grant access to Tailscale configuration",
		"read": {
			"file": {
				"/sbin/logread": [ "read", "exec" ],
				"/usr/libexec/logread-ubox": [ "read", "exec" ],
				"/usr/sbin/logread": [ "read", "exec" ],
				"/sbin/logread -e tailscale": [ "exec" ],
				"/usr/libexec/logread-ubox -e tailscale": [ "exec" ],
				"/usr/sbin/logread -e tailscale": [ "exec" ],
				"/usr/bin/logread -e tailscale": [ "exec" ],
				"/sbin/ip -s -j ad": [ "exec" ],
				"/usr/sbin/ip -s -j ad": [ "exec" ],
				"/usr/sbin/tailscale status --json": [ "exec" ],
				"/usr/bin/tailscale status --json": [ "exec" ],
				"/usr/sbin/tailscale netcheck": [ "exec" ],
				"/usr/bin/tailscale netcheck": [ "exec" ],
				"/usr/sbin/tailscale version": [ "exec" ],
				"/usr/bin/tailscale version": [ "exec" ],
				"/usr/sbin/tailscale ip": [ "exec" ],
				"/usr/bin/tailscale ip": [ "exec" ],
				"/usr/sbin/tailscale login": [ "exec" ],
				"/usr/bin/tailscale login": [ "exec" ],
				"/usr/sbin/tailscale logout": [ "exec" ],
				"/usr/bin/tailscale logout": [ "exec" ]
			},
			"ubus": {
				"service": [ "list" ]
			},
			"uci": [ "tailscale" ]
		},
		"write": {
			"file": {
				"/sbin/logread": [ "read", "exec" ],
				"/usr/libexec/logread-ubox": [ "read", "exec" ],
				"/usr/sbin/logread": [ "read", "exec" ],
				"/sbin/logread -e tailscale": [ "exec" ],
				"/usr/libexec/logread-ubox -e tailscale": [ "exec" ],
				"/usr/sbin/logread -e tailscale": [ "exec" ],
				"/usr/bin/logread -e tailscale": [ "exec" ],
				"/sbin/ip -s -j ad": [ "exec" ],
				"/usr/sbin/ip -s -j ad": [ "exec" ],
				"/usr/sbin/tailscale status --json": [ "exec" ],
				"/usr/bin/tailscale status --json": [ "exec" ],
				"/usr/sbin/tailscale login": [ "exec" ],
				"/usr/bin/tailscale login": [ "exec" ],
				"/usr/sbin/tailscale logout": [ "exec" ],
				"/usr/bin/tailscale logout": [ "exec" ],
				"/usr/sbin/tailscale up": [ "exec" ],
				"/usr/bin/tailscale up": [ "exec" ],
				"/usr/sbin/tailscale down": [ "exec" ],
				"/usr/bin/tailscale down": [ "exec" ],
				"/usr/sbin/tailscale set": [ "exec" ],
				"/usr/bin/tailscale set": [ "exec" ]
			},
			"uci": [ "tailscale" ]
		}
	}
}
TS_ACL_EOF
	chmod 0644 "$TS_PKG_DIR/root/usr/share/rpcd/acl.d/luci-app-tailscale.json"
	echo "tailscale: ACL rewritten (logread /usr/sbin path granted)"
else
	echo "tailscale: luci-app-tailscale package dir not found, skip runtime fix"
fi

UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "lucky" "gdy666/luci-app-lucky" "main"
UPDATE_PACKAGE "netspeedtest" "sirpdboy/netspeedtest" "main" "" "homebox ookla-speedtest"
UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "timecontrol" "sirpdboy/luci-app-timecontrol" "main"

UPDATE_PACKAGE "natmapt" "muink/openwrt-natmapt" "master"
UPDATE_PACKAGE "stuntman" "muink/openwrt-stuntman" "master"
UPDATE_PACKAGE "luci-app-natmapt" "muink/luci-app-natmapt" "master"

UPDATE_PACKAGE "airpi3000m-fancontrol" "LianXia233/luci-app-airpi3000m-fancontrol" "main"
UPDATE_PACKAGE "chfs" "LianXia233/luci-app-chfs" "main"
UPDATE_PACKAGE "fm350" "LianXia233/luci-app-fm350" "main"
UPDATE_PACKAGE "h5000m-netmode" "LianXia233/luci-app-h5000m-netmode" "main"
UPDATE_PACKAGE "mt5700" "LianXia233/luci-app-mt5700" "main"
UPDATE_PACKAGE "mt5700m" "LianXia233/luci-app-mt5700m" "main"
UPDATE_PACKAGE "netmonitor" "LianXia233/luci-app-netmonitor" "main"
UPDATE_PACKAGE "qmodem-generic" "LianXia233/luci-app-qmodem-generic" "main"

#更新软件包版本
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./package/ ./feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo -e "\n$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" $PKG_FILE)
		local PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")

		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		local OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER=$(echo $PKG_TAG | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		local NEW_URL=$(echo $PKG_URL | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}

#UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
#UPDATE_VERSION "sing-box"

#引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi
