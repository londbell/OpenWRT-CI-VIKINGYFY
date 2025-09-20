#!/bin/bash
. $(dirname "$(realpath "$0")")/function.sh

# 设置默认值
: ${WRT_BYPASS:=false} 

#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")


#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ NikoWRT-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
	#修改WIFI地区
	sed -i "s/country='.*'/country='CN'/g" $WIFI_UC
	#修改WIFI加密
	sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

vlmcsd_patches="./feeds/packages/net/vlmcsd/patches/"
mkdir -p $vlmcsd_patches && cp -f ../patches/001-fix_compile_with_ccache.patch $vlmcsd_patches

#修复dropbear
#sed -i "s/Interface/DirectInterface/" ./package/network/services/dropbear/files/dropbear.config
sed -i "/Interface/d" ./package/network/services/dropbear/files/dropbear.config
#拷贝files 文件夹到编译目录
cp -r ../files ./

#配置文件修改
#echo "CONFIG_PACKAGE_luci=y" >> ./.config
#echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
#echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
#echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/"
if [[ $WRT_TARGET == *"QUALCOMMAX"* ]]; then
	#取消nss相关feed
	echo "CONFIG_FEED_nss_packages=n" >> ./.config
	echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
	#设置NSS版本
	echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
	echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
	#开启sqm-nss插件
	echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
	echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

# 配置旁路由模式（关闭DHCP服务器）
if [[ "$WRT_BYPASS" == "true" ]]; then
    echo "Setting up bypass router mode (disabling DHCP server)..."

    # 设置默认网关（如果未指定则使用192.168.2.1）
    BYPASS_GATEWAY=${WRT_BYPASS_GATEWAY:-"192.168.2.1"}
    echo "Using gateway: $BYPASS_GATEWAY"

    # 创建uci-defaults脚本来配置旁路由模式
    UCI_DEFAULTS_DIR="./files/etc/uci-defaults"
    mkdir -p $UCI_DEFAULTS_DIR

    cat > $UCI_DEFAULTS_DIR/99-bypass-mode <<EOF
#!/bin/sh

# 配置旁路由模式 - 这个脚本会在路由器首次启动时执行
# 它会根据实际硬件情况修改网络配置，而不是使用预置的静态配置

# 设置静态IP地址（如果已经是静态IP则不修改）
uci -q get network.lan.proto | grep -q "static" || uci set network.lan.proto='static'

# 设置网关和DNS服务器
uci -q batch <<EOI
set network.lan.gateway='$BYPASS_GATEWAY'
del_list network.lan.dns='$BYPASS_GATEWAY' >/dev/null 2>&1
add_list network.lan.dns='$BYPASS_GATEWAY'
commit network
EOI

# 禁用DHCP服务器
uci -q batch <<EOI
set dhcp.lan.ignore='1'
commit dhcp
EOI

# 应用更改
/etc/init.d/network reload
/etc/init.d/dnsmasq reload

echo "Bypass router mode configured successfully!"
exit 0
EOF

    # 确保脚本可执行
    chmod +x $UCI_DEFAULTS_DIR/99-bypass-mode

    echo "Bypass router mode configuration completed!"
fi
