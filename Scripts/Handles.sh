#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

FEEDS_PATH="./feeds"
PACKAGE_PATH="./package"

#修补命令统一入口：FIX <名称> <守卫目录> <命令...>
#守卫目录不存在时直接跳过，保证在 bash -e 下不中断
FIX() {
	local NAME=$1
	local GUARD=$2
	shift 2

	[ -d "$GUARD" ] || return 0

	echo " "
	if "$@"; then
		echo "$NAME has been fixed!"
	else
		echo "$NAME fix failed; continuing!"
	fi
}

#修改argon主题字体和颜色
FIX "theme-argon" "$PACKAGE_PATH/luci-theme-argon" sed -i \
	"s/primary '.*'/primary '#31a1a1'/g; s/'0.2'/'0.5'/g; s/'none'/'bing'/g; s/'600'/'normal'/g" \
	"$PACKAGE_PATH/luci-theme-argon/luci-app-argon-config/root/etc/config/argon"

#修改aurora菜单式样
FIX "theme-aurora" "$PACKAGE_PATH/luci-app-aurora-config" find \
	"$PACKAGE_PATH/luci-app-aurora-config/root/usr/share/aurora/" -type f -name '*.template' -exec sed -i \
	"s/nav_type '.*'/nav_type 'dropdown'/g; s/struct_radius_base '.*'/struct_radius_base '0.125rem'/g" {} +

#修改vantage进度条标签字体（anothaDev/luci-theme-vantage#52）
FIX "theme-vantage" "$PACKAGE_PATH/luci-theme-vantage" sed -i \
	-e '/^\/\* progress bars: thin track/,$ { /^\.cbi-progressbar::before {/,/^}/ { s/^[[:space:]]*font: 500 var(--fs-micro)\/1\.2 var(--mono);/\tfont: inherit; line-height: normal;/; } }' \
	"$PACKAGE_PATH/luci-theme-vantage/luci-theme-vantage/htdocs/luci-static/vantage/vantage.css"

#修改mini-diskmanager菜单位置
FIX "mini-diskmanager" "$PACKAGE_PATH/luci-app-mini-diskmanager" sed -i "s/services/system/g" \
	"$PACKAGE_PATH/luci-app-mini-diskmanager/luci-app-mini-diskmanager/root/usr/share/luci/menu.d/luci-app-mini-diskmanager.json"

#修改natmapt菜单位置
FIX "natmapt" "$PACKAGE_PATH/luci-app-natmapt" sed -i "s/network/services/g" \
	"$PACKAGE_PATH/luci-app-natmapt/root/usr/share/luci/menu.d/luci-app-natmap.json"

#修改 UPnP IGD 菜单位置到"网络"，并置于 DHCP 之后（dhcp order=40，upnp order=41）
UPNP_MENU=$(find ./ ../feeds/ -path "*/luci-app-upnp/root/usr/share/luci/menu.d/luci-app-upnp.json" 2>/dev/null | head -n 1)
if [ -n "$UPNP_MENU" ]; then
	sed -i 's#"admin/services/upnp#"admin/network/upnp#g' "$UPNP_MENU"
	if python3 - "$UPNP_MENU" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
new = {}
for k, v in data.items():
    nk = k.replace("admin/services/upnp", "admin/network/upnp", 1)
    if nk == "admin/network/upnp" and isinstance(v, dict) and "order" not in v:
        v = dict(v)
        v["order"] = 41
    new[nk] = v
with open(path, "w", encoding="utf-8") as f:
    json.dump(new, f, indent="\t", ensure_ascii=False)
    f.write("\n")
PYEOF
	then
		echo "upnp menu moved to network (after dhcp, order 41)"
	else
		echo "upnp menu fix failed; continuing!"
	fi
fi

#删除系统菜单下的"插件"项
SYS_MENU=$(find ./ ../feeds/ -path "*/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json" 2>/dev/null | head -n 1)
if [ -n "$SYS_MENU" ]; then
	sed -i '/"admin\/system\/plugins": {/,/^\t},$/d' "$SYS_MENU"
	echo "system plugins menu removed"
fi

#修改"超级网络唤醒(WOL Ultra)"菜单位置：Control -> 服务
FIX "wolultra-menu" "$PACKAGE_PATH/packages/luci-app-wolultra" sed -i \
	's#"admin/control/wolultra"#"admin/services/wolultra"#' \
	"$PACKAGE_PATH/packages/luci-app-wolultra/root/usr/share/luci/menu.d/luci-app-wolultra.json"

#修改"DDNS-GO"菜单位置：服务 -> VPN
DDNSGO_MENU=$(find ./ ../feeds/ -path "*/luci-app-ddns-go/root/usr/share/luci/menu.d/luci-app-ddns-go.json" 2>/dev/null | head -n 1)
if [ -n "$DDNSGO_MENU" ]; then
	sed -i 's#admin/services/ddns-go#admin/vpn/ddns-go#g' "$DDNSGO_MENU"
	echo "ddns-go menu moved to vpn"
else
	echo "ddns-go menu not found; skipping!"
fi

#锁定 lucky 核心为 3.8.1(标准版)，并改为使用仓库内置离线包，不走 GitHub release 下载
LUCKY_MK=$(find ./ ../feeds/ -path "*/lucky/lucky/Makefile" 2>/dev/null | head -n 1)
if [ -n "$LUCKY_MK" ]; then
	python3 - "$LUCKY_MK" <<'PYEOF'
import re, sys

path = sys.argv[1]
with open(path, encoding="utf-8", newline="") as f:
    s = f.read()

nl = "\r\n" if "\r\n" in s else "\n"


def setvar(text, name, val):
    return re.sub(r"(?m)^" + re.escape(name) + r":=.*?(?=\r?\n|$)", name + ":=" + val, text, count=1)


s = setvar(s, "PKG_VERSION", "3.8.1")
s = setvar(s, "PKG_SOURCE", "")
s = setvar(s, "PKG_SOURCE_URL", "")
s = setvar(s, "PKG_HASH", "skip")

block = nl.join([
    "define Build/Prepare",
    "\tgzip -dc $(TOPDIR)/Scripts/lucky/lucky_$(PKG_VERSION)_Linux_$(LUCKY_ARCH).tar.gz | $(HOST_TAR) -C $(PKG_BUILD_DIR) -xf -",
    "\t$(Build/Patch)",
    "endef",
])
if re.search(r"(?s)define Build/Prepare.*?\nendef", s):
    s = re.sub(r"(?s)define Build/Prepare.*?\nendef", block, s, count=1)
else:
    s = s.replace("include $(INCLUDE_DIR)/package.mk", block + nl + nl + "include $(INCLUDE_DIR)/package.mk", 1)

with open(path, "w", encoding="utf-8", newline="") as f:
    f.write(s)

print("lucky: PKG_VERSION=3.8.1, source -> Scripts/lucky local tarball")
PYEOF
else
	echo "lucky Makefile not found; skipping!"
fi

#修改"Lucky"菜单位置：服务 -> VPN 的首项（DDNS-GO order 58，故取 10）
LUCKY_MENU=$(find ./ ../feeds/ -path "*/luci-app-lucky/root/usr/share/luci/menu.d/luci-app-lucky.json" 2>/dev/null | head -n 1)
if [ -n "$LUCKY_MENU" ]; then
	sed -i \
		-e 's#"admin/services/lucky"#"admin/vpn/lucky"#' \
		-e 's#"order": 60#"order": 10#' \
		"$LUCKY_MENU"
	echo "lucky menu moved to vpn (first item)"
else
	echo "lucky menu not found; skipping!"
fi

# tailscale：单实例 init + hotplug 守卫 + 接口自动建段（改写克隆下来的 luci-app-tailscale 包内容，随包安装）
#   1) init 只起一个 tailscaled，不再调用 tailscale_helper（helper 文件由构建脚本直接删除）
#   2) hotplug 加 pgrep 守卫：tailscaled 拉起 tailscale0 也会 ifup，原版无条件 start 会 start→up→start 自激
#   3) 启用后自动建 network.tailscale 段（static + 真实 IPv4/IPv6），「网络-接口」显示 tailscale0
#   4) 复现 helper 的必需副作用：firewall zone(tszone, network=tailscale)+4 条 forwarding，停止时对称清理（MagicDNS/subnet 路由不迁移）
#   5) ACL 只补 logread 真实路径，其余授权保持上游原版
# tailscale 后端自带的 init/config 与 luci-app-tailscale 冲突，移除后端同名文件定义
TS_BACKEND_MK=$(find ./ ../feeds/ -path "*/net/tailscale/Makefile" 2>/dev/null | head -n 1)
if [ -n "$TS_BACKEND_MK" ]; then
	sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;' "$TS_BACKEND_MK"
	echo "tailscale backend init/config removed from Makefile"
else
	echo "tailscale backend Makefile not found; skipping!"
fi

# ======================================================================================
# tailscale 运行时修复：直接改写克隆下来的 luci-app-tailscale 包内容（随包安装，无需 files/ 覆盖层）
#   1) init 只起一个 tailscaled，不再调用 tailscale_helper（helper 文件由构建脚本直接删除）
#   2) hotplug 加 pgrep 守卫：tailscaled 拉起 tailscale0 也会 ifup，原版无条件 start 会 start→up→start 自激
#   3) 启用后自动建 network.tailscale 段（static + 真实 IPv4/IPv6），「网络-接口」显示 tailscale0
#   4) 复现 helper 的必需副作用：firewall zone(tszone, network=tailscale)+4 条 forwarding，停止时对称清理（MagicDNS/subnet 路由不迁移）
#   5) ACL 只补 logread 真实路径，其余授权保持上游原版
# ======================================================================================
TS_PKG_DIR="$PACKAGE_PATH/luci-app-tailscale"

if [ -d "$TS_PKG_DIR/root" ]; then
	# ---- 1. 替换 init 脚本：单实例 tailscaled（去掉 tailscale_helper）+ 异步同步 UI 选项 ----
	mkdir -p "$TS_PKG_DIR/root/etc/init.d"
	cat > "$TS_PKG_DIR/root/etc/init.d/tailscale" <<'TS_INIT_EOF'
#!/bin/sh /etc/rc.common

# Tailscale service（构建侧修复版）
# 1) 单实例 tailscaled，不起 tailscale_helper（避免 procd crash loop）
# 2) UI 选项通过 `tailscale set` 异步下发（该子命令不会触发登录）
# 3) 拿到地址后同步 network.tailscale 段，使「网络-接口」显示 tailscale0 及 IPv4/IPv6（IP 变化自动刷新）

START=90
STOP=10
USE_PROCD=1

PROGD=/usr/sbin/tailscaled
TSCLI=/usr/sbin/tailscale
SOCK=/var/run/tailscale/tailscaled.sock

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

	/usr/sbin/tailscaled --cleanup >/dev/null 2>&1

	procd_open_instance
	procd_set_param command "$PROGD"
	procd_append_param command --port "$port"
	procd_append_param command --state "$config_path/tailscaled.state"
	procd_set_param env TS_DEBUG_FIREWALL_MODE="$fw_mode"
	procd_set_param respawn 3600 5 0
	procd_set_param stdout "$log_stdout"
	procd_set_param stderr "$log_stderr"
	procd_close_instance

	apply_settings "$cfg" &
	ensure_netifd_iface &
	watch_iface_changes &
}

watch_iface_changes() {
	local pidfile=/var/run/tailscale_iface_watch.pid

	(
		while :; do
			sleep 30
			pgrep -f /usr/sbin/tailscaled >/dev/null 2>&1 && ensure_netifd_iface
		done
	) &
	echo "$!" > "$pidfile"
}

ensure_netifd_iface() {
	local v4 v6 i=0 changed=0

	# 等 tailscaled 拿到地址（最多 60 秒）
	while [ $i -lt 60 ]; do
		[ -S "$SOCK" ] && [ -n "$($TSCLI ip -4 2>/dev/null)" ] && break
		sleep 1
		i=$((i + 1))
	done
	v4=$($TSCLI ip -4 2>/dev/null | head -n1)
	v6=$($TSCLI ip -6 2>/dev/null | head -n1)
	if [ -n "$v4" ]; then
		case "$v4" in */*) ;; *) v4="$v4/32" ;; esac
	fi
	if [ -n "$v6" ]; then
		case "$v6" in */*) ;; *) v6="$v6/128" ;; esac
	fi

	# 接口页显示：静态地址 + 真实 IPv4/IPv6，设备固定 tailscale0；值有变化才提交并 reload
	[ "$(uci -q get network.tailscale)" = "interface" ] || { uci -q set network.tailscale='interface'; changed=1; }
	[ "$(uci -q get network.tailscale.proto)" = "static" ] || { uci -q set network.tailscale.proto='static'; changed=1; }
	[ "$(uci -q get network.tailscale.device)" = "tailscale0" ] || { uci -q set network.tailscale.device='tailscale0'; changed=1; }
	if [ -n "$v4" ]; then
		[ "$(uci -q get network.tailscale.ipaddr)" = "$v4" ] || { uci -q set network.tailscale.ipaddr="$v4"; changed=1; }
	fi
	if [ -n "$v6" ]; then
		[ "$(uci -q get network.tailscale.ip6addr)" = "$v6" ] || { uci -q set network.tailscale.ip6addr="$v6"; changed=1; }
	fi
	if [ "$changed" = "1" ]; then
		uci -q commit network
		/etc/init.d/network reload >/dev/null 2>&1 &
	fi

	ensure_extras
	return 0
}

# 复现上游 tailscale_helper 的必需副作用（原版由 helper 完成，去掉 helper 后必须自理）
#   firewall.tszone（network=tailscale）+ 4 条 forwarding，字段与 helper 完全一致
# 幂等：值无变化不提交、不 reload，避免 30 秒轮询引起防火墙抖动
ensure_fw_fwd() {
	local sec="$1" src="$2" dest="$3"

	[ "$(uci -q get firewall.$sec)" = "forwarding" ] || { uci -q set firewall.$sec='forwarding'; fw_changed=1; }
	[ "$(uci -q get firewall.$sec.src)" = "$src" ] || { uci -q set firewall.$sec.src="$src"; fw_changed=1; }
	[ "$(uci -q get firewall.$sec.dest)" = "$dest" ] || { uci -q set firewall.$sec.dest="$dest"; fw_changed=1; }
}

ensure_extras() {
	local access kv k v fw_changed=0 net_changed=0

	config_load tailscale
	config_get access 'settings' 'access'
	config_get accept_dns 'settings' 'accept_dns' 1

	if [ "$accept_dns" = "1" ] && [ -n "$MagicDNSSuffix" ]; then
		local _dnsmasq_suffix="${MagicDNSSuffix#*/}"
		uci -q del_list dhcp.dnsmasq.address="magicdns"
		uci -q add_list dhcp.dnsmasq.address="/${_dnsmasq_suffix}/100.100.100.100" || { log "Failed to set MagicDNS suffix"; return 1; }
	fi

	# 防火墙：ACCESS 非空才建 zone（与 helper 判定一致），zone 必须绑定 network=tailscale
	if [ -n "$access" ]; then
		[ "$(uci -q get firewall.tszone)" = "zone" ] || { uci -q set firewall.tszone='zone'; fw_changed=1; }
		for kv in name=tailscale network=tailscale input=ACCEPT output=ACCEPT forward=ACCEPT masq=1 mtu_fix=1; do
			k=${kv%%=*}; v=${kv#*=}
			[ "$(uci -q get firewall.tszone.$k)" = "$v" ] || { uci -q set firewall.tszone.$k="$v"; fw_changed=1; }
		done
		case " $access " in *" ts_ac_lan "*) ensure_fw_fwd ts_ac_lan tailscale lan ;; esac
		case " $access " in *" ts_ac_wan "*) ensure_fw_fwd ts_ac_wan tailscale wan ;; esac
		case " $access " in *" lan_ac_ts "*) ensure_fw_fwd lan_ac_ts lan tailscale ;; esac
		case " $access " in *" wan_ac_ts "*) ensure_fw_fwd wan_ac_ts wan tailscale ;; esac
	fi

	if [ "$fw_changed" = "1" ]; then
		uci -q commit firewall
		/etc/init.d/firewall reload >/dev/null 2>&1 &
	fi
	return 0
}

# 停止时对称清理，对应上游 stop_instance，避免停用后残留空绑定的 zone
cleanup_extras() {
	local sec fw_changed=0 net_changed=0

	config_load tailscale
	config_get accept_dns 'settings' 'accept_dns' 1

	for sec in firewall.tszone firewall.ts_ac_lan firewall.ts_ac_wan firewall.lan_ac_ts firewall.wan_ac_ts; do
		uci -q delete "$sec" && fw_changed=1
	done
	uci -q delete network.tailscale && net_changed=1

	if [ "$accept_dns" = "1" ]; then
		uci -q del_list dhcp.dnsmasq.address="magicdns"
	fi

	[ "$fw_changed" = "1" ] && uci -q commit firewall
	[ "$net_changed" = "1" ] && uci -q commit network
	return 0
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
	local pidfile=/var/run/tailscale_iface_watch.pid
	if [ -s "$pidfile" ]; then
		kill "$(cat "$pidfile")" >/dev/null 2>&1
		rm -f "$pidfile"
	fi
	cleanup_extras
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
[ "$(uci -q get tailscale.settings.enabled)" = "1" ] || exit 0
pgrep -f /usr/sbin/tailscaled >/dev/null 2>&1 && exit 0
/etc/init.d/tailscale start >/tmp/tailscale.log 2>&1 &
TS_HOTPLUG_EOF
	chmod 0755 "$TS_PKG_DIR/root/etc/hotplug.d/iface/40-tailscale"
	echo "tailscale: hotplug script replaced"

	# ---- 2. 删除随包安装的 tailscale_helper：init 已不再调用它，其必要功能已在 init 内复现；
	#          留着会与 init 的 uci 写入互相打架，也可能被手工/hotplug 误调 ----
	TS_HELPER="$TS_PKG_DIR/root/usr/sbin/tailscale_helper"
	if [ -f "$TS_HELPER" ]; then
		rm -f "$TS_HELPER"
		rmdir "$TS_PKG_DIR/root/usr/sbin" 2>/dev/null
		echo "tailscale: tailscale_helper removed"
	else
		echo "tailscale: tailscale_helper not found, skip"
	fi

	# ---- 3. ACL 增量补丁：只补 logread 真实路径，其余授权保持上游原版 ----
	#   上游只授 /sbin/logread，本设备该路径为软链、真实目标 /usr/libexec/logread-ubox，
	#   rpcd 按真实路径校验，故补该路径 read/exec 及 -e tailscale 变体，否则日志页报 ACL 拒绝
	ACL_JSON="$TS_PKG_DIR/root/usr/share/rpcd/acl.d/luci-app-tailscale.json"
	if [ -f "$ACL_JSON" ]; then
		jq '.["luci-app-tailscale"].read.file = ((.["luci-app-tailscale"].read.file // {}) + {"/sbin/logread":["read","exec"],"/usr/libexec/logread-ubox":["read","exec"],"/usr/libexec/logread-ubox -e tailscale":["exec"]}) | .["luci-app-tailscale"].write.file = ((.["luci-app-tailscale"].write.file // {}) + {"/sbin/logread":["read","exec"],"/usr/libexec/logread-ubox":["read","exec"],"/usr/libexec/logread-ubox -e tailscale":["exec"]})' "$ACL_JSON" > "$ACL_JSON.tmp" && mv "$ACL_JSON.tmp" "$ACL_JSON"
		chmod 0644 "$ACL_JSON"
		echo "tailscale: ACL patched (logread realpath granted)"
	else
		echo "tailscale: ACL file not found, skip"
	fi
else
	echo "tailscale: luci-app-tailscale package dir not found, skip runtime fix"
fi
