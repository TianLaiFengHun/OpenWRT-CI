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
