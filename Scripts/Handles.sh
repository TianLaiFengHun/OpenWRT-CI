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

# tailscale：保留 helper + 接口地址交还 tailscaled（改写克隆下来的 luci-app-tailscale 包内容，随包安装）
#   1) helper 完整保留（连接、MagicDNS、子网路由、防火墙 zone），只去掉它写接口地址的部分
#   2) network.tailscale 改 proto=none：地址与 100.64.0.0/10 路由由 tailscaled 自己配，避免 netifd 先配后被跳过
#   3) LuCI「网络-接口」仍显示 tailscale0，界面只作显示，不参与配置
#   4) ACL 只补 logread 真实路径，其余授权保持上游原版
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
#   1) 保留 tailscale_helper（连接、MagicDNS、子网路由、防火墙 zone 等逻辑一行不动）
#   2) 只把 helper 写 network.tailscale 的地址部分去掉：proto 改 none、不写 ipaddr/ip6addr/netmask
#      原因：tailscaled 1.104 重构后「先检查再动手」，netifd 已配的地址会让它跳过整个接口配置，
#            导致 100.64.0.0/10 路由不装；地址交给 tailscaled 自己配才完整
#   3) 「网络-接口」仍显示 tailscale0（内核地址可读），配置段保留但 netifd 不再 apply
#   4) ACL 只补 logread 真实路径，其余授权保持上游原版
# ======================================================================================
TS_PKG_DIR="$PACKAGE_PATH/luci-app-tailscale"

if [ -d "$TS_PKG_DIR/root" ]; then
	# ---- 1. helper：接口地址交还 tailscaled ----
	TS_HELPER="$TS_PKG_DIR/root/usr/sbin/tailscale_helper"
	if [ -f "$TS_HELPER" ]; then
		sed -i \
			-e "s/\(network\.tailscale\.proto=\)'static'/\1none/" \
			-e "s/\(network\.tailscale\.proto=\)\"static\"/\1none/" \
			-e "s/\(network\.tailscale\.proto=\)static/\1none/" \
			-e "/network\.tailscale\.ipaddr=/d" \
			-e "/network\.tailscale\.ip6addr=/d" \
			-e "/network\.tailscale\.netmask=/d" \
			"$TS_HELPER"
		if grep -q "proto=none" "$TS_HELPER"; then
			echo "tailscale: helper patched (interface addr owned by tailscaled)"
		else
			echo "tailscale: WARN helper proto not patched, check helper source!"
		fi
	else
		echo "tailscale: tailscale_helper not found, skip"
	fi

	# ---- 2. ACL 增量补丁：只补 logread 真实路径，其余授权保持上游原版 ----
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
