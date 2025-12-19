#!/bin/sh

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
    echo_error "此脚本需要 root 权限运行"
    exit 1
fi

# 检查系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        XRAY_ARCH="64"
        ;;
    aarch64)
        XRAY_ARCH="arm64-v8a"
        ;;
    armv7l)
        XRAY_ARCH="arm32-v7a"
        ;;
    *)
        echo_error "不支持的架构: $ARCH"
        exit 1
        ;;
esac

echo_info "检测到系统架构: $ARCH"

# 安装必要的依赖
echo_info "安装必要的依赖包..."
apk update
apk add --no-cache wget unzip curl ca-certificates

# 设置安装目录
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/usr/local/etc/xray"
LOG_DIR="/var/log/xray"

# 创建必要的目录
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"

# 获取最新版本号
echo_info "获取 Xray 最新版本..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

if [ -z "$LATEST_VERSION" ]; then
    echo_error "无法获取最新版本号"
    exit 1
fi

echo_info "最新版本: v$LATEST_VERSION"

# 下载 Xray
DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/v${LATEST_VERSION}/Xray-linux-${XRAY_ARCH}.zip"
echo_info "下载 Xray: $DOWNLOAD_URL"

cd /tmp
wget -O xray.zip "$DOWNLOAD_URL"

# 解压文件
echo_info "解压文件..."
unzip -o xray.zip -d xray_temp

# 安装可执行文件
echo_info "安装 Xray..."
cp xray_temp/xray "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/xray"

# 安装 geoip 和 geosite 数据文件
if [ -f xray_temp/geoip.dat ]; then
    cp xray_temp/geoip.dat "$CONFIG_DIR/"
fi

if [ -f xray_temp/geosite.dat ]; then
    cp xray_temp/geosite.dat "$CONFIG_DIR/"
fi

# 清理临时文件
rm -rf xray_temp xray.zip

# 创建默认配置文件（如果不存在）
if [ ! -f "$CONFIG_DIR/config.json" ]; then
    echo_info "创建默认配置文件..."
    cat > "$CONFIG_DIR/config.json" << 'EOF'
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
    echo_warn "已创建默认配置文件，请根据需要修改: $CONFIG_DIR/config.json"
fi

# 创建 OpenRC 服务脚本
echo_info "创建 OpenRC 服务..."
cat > /etc/init.d/xray << 'EOF'
#!/sbin/openrc-run

name="xray"
description="Xray Service"
command="/usr/local/bin/xray"
command_args="run -config /usr/local/etc/xray/config.json"
command_background="yes"
pidfile="/run/${RC_SVCNAME}.pid"
output_log="/var/log/xray/xray.log"
error_log="/var/log/xray/xray_error.log"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --directory --mode 0755 /var/log/xray
}
EOF

chmod +x /etc/init.d/xray

# 添加到开机自启动
echo_info "设置开机自启动..."
rc-update add xray default

# 启动服务
echo_info "启动 Xray 服务..."
rc-service xray start

# 验证安装
if command -v xray >/dev/null 2>&1; then
    INSTALLED_VERSION=$(/usr/local/bin/xray version | head -n 1)
    echo_info "Xray 安装成功!"
    echo_info "版本信息: $INSTALLED_VERSION"
else
    echo_error "Xray 安装失败"
    exit 1
fi

# 显示服务状态
echo ""
echo_info "========== 安装完成 =========="
echo_info "Xray 版本: v$LATEST_VERSION"
echo_info "配置文件: $CONFIG_DIR/config.json"
echo_info "日志目录: $LOG_DIR"
echo_info "服务状态: $(rc-service xray status)"
echo ""
echo_info "常用命令:"
echo "  启动服务: rc-service xray start"
echo "  停止服务: rc-service xray stop"
echo "  重启服务: rc-service xray restart"
echo "  查看状态: rc-service xray status"
echo "  查看日志: tail -f $LOG_DIR/error.log"
echo ""
echo_warn "请记得修改配置文件: $CONFIG_DIR/config.json"