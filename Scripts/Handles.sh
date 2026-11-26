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

# tailscale：只做两处改动（官方要求 + ACL 日志修复），其余保持上游原版
#   1) 官方要求：后端 Makefile 不装 /etc/init.d/tailscale 与 /etc/config/tailscale（改用 luci 版）
#   2) ACL 只补 logread 真实路径，其余授权保持上游原版
#   注：helper 的 proto=none 由上游代码自身在非单播分支写入，此处不再 sed 覆盖
TS_BACKEND_MK=$(find ./ ../feeds/ -path "*/net/tailscale/Makefile" 2>/dev/null | head -n 1)
if [ -n "$TS_BACKEND_MK" ]; then
	sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;' "$TS_BACKEND_MK"
	echo "tailscale backend init/config removed from Makefile"
else
	echo "tailscale backend Makefile not found; skipping!"
fi

# ======================================================================================
# tailscale 运行时修复：只补 ACL 日志授权一处，其余保持上游原版
# ======================================================================================
TS_PKG_DIR="$PACKAGE_PATH/luci-app-tailscale"

if [ -d "$TS_PKG_DIR/root" ]; then
	# ---- 1. ACL 增量补丁：只补 logread 真实路径，其余授权保持上游原版 ----
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

# ======================================================================================
# tailscale 运行时修复 2：start 后补齐 tailscale0 双栈地址（reload 保持官方原版）
# ======================================================================================
# 现象：刷机后 tailscale0 上既没有 IPv4 也没有全局 IPv6（只剩 fe80 链路本地），
#       插件页（读 tailscaled 状态）显示双栈正常、系统接口页（读内核/netifd）却是空的，两处对不上；
#       重启服务也补不回来。
# 根因（tailscaled v1.104.6 日志实证）：
#   router: removed 2 stale Tailscale address(es) from tailscale0 left by a previous instance:
#           [100.66.6.1/8 fd7a:115c:a1e0::f82f:7380/128]
#   官方设计就是 proto=static + netmask 255.0.0.0（100.66.6.1/8），前缀长度本身没有问题；
#   但 tailscaled 每次进程启动都会把链路上 CGNAT 段的地址一律当成「上一实例残留」清掉，
#   清完自己不补，netifd 又只在 ifup 时下发一次，于是接口长期没有地址。
# 处理：不改编 reload 语义（保持官方 stop+start），只在 start_instance 拉起 tailscaled 后异步
#   等它就绪，按 uci 里的 ipaddr/netmask/ip6addr 原值把双栈补回（v4 保持 /8 语义与 100.0.0.0/8 直连路由，
#   v6 按上游节点的 /128 补）。
TS_INIT=$(find ./ ../feeds/ -path "*/luci-app-tailscale/root/etc/init.d/tailscale" 2>/dev/null | head -n 1)
if [ -n "$TS_INIT" ]; then
	if grep -q 'TS_ADDR_GUARD' "$TS_INIT"; then
		echo "tailscale: address guard already present, skip"
	else
		awk '
		{ print }
		/^[[:space:]]*tailscale_helper / {
			print ""
			print "\t# TS_ADDR_GUARD: netifd 下发的地址会被 tailscaled 启动时的 stale cleanup 清掉，等它就绪后按 uci 原值补回"
			print "\t("
			print "\t\ti=0"
			print "\t\twhile [ $i -lt 60 ]; do /usr/sbin/tailscale ip -4 >/dev/null 2>&1 && break; i=$((i+1)); sleep 1; done"
			print "\t\tsleep 2"
			print "\t\ta=$(uci -q get network.tailscale.ipaddr); m=$(uci -q get network.tailscale.netmask)"
			print "\t\ta6=$(uci -q get network.tailscale.ip6addr)"
			print "\t\t[ -n \"$a\" ] || a=$(/usr/sbin/tailscale ip -4 2>/dev/null | head -n1)"
			print "\t\t[ -n \"$a6\" ] || a6=$(/usr/sbin/tailscale ip -6 2>/dev/null | head -n1)"
			print "\t\t[ -n \"$m\" ] || m=255.0.0.0"
			print "\t\tif [ -n \"$a\" ] && ! ip -4 addr show dev tailscale0 2>/dev/null | grep -q \"inet $a/\"; then"
			print "\t\t\tip addr add \"$a/$m\" dev tailscale0 2>/dev/null || ip addr add \"$a/8\" dev tailscale0"
			print "\t\tfi"
			print "\t\tif [ -n \"$a6\" ] && ! ip -6 addr show dev tailscale0 2>/dev/null | grep -q \"inet6 $a6/\"; then"
			print "\t\t\tip -6 addr add \"$a6/128\" dev tailscale0"
			print "\t\tfi"
			print "\t) &"
		}
		' "$TS_INIT" > "$TS_INIT.patched" && mv "$TS_INIT.patched" "$TS_INIT"
		chmod 0755 "$TS_INIT"
		if grep -q 'TS_ADDR_GUARD' "$TS_INIT"; then
			echo "tailscale: address guard added after tailscale_helper"
		else
			echo "tailscale: WARN address guard not inserted (tailscale_helper missing)"
		fi
	fi
else
	echo "tailscale: init script not found; skipping!"
fi
