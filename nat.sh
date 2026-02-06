#!/usr/bin/env bash

# --- 核心配置 (根据您的截图已固定) ---
WAN_INTERFACE="vmbr0"       # 外网出口
GATEWAY_IP="172.16.1.1"     # 内网网关 (跳过此IP)
USER_IP_HEAD="172.16."      # 内网前缀
# ----------------------------------

# 尝试自动获取公网IP
AUTO_IP=$(curl -s -4 ifconfig.me || echo "")

echo -e "==============================================="
echo -e "   PVE NAT 批量端口转发脚本 (适配 172.16.x.x)"
echo -e "   外网口: $WAN_INTERFACE | 网关: $GATEWAY_IP"
echo -e "==============================================="

# 1. 获取公网 IP (默认使用自动获取到的)
echo -e "Please input your server main ip"
if [[ -n "$AUTO_IP" ]]; then
    read -p "(Default: ${AUTO_IP}):" main_ip
    [[ -z "${main_ip}" ]] && main_ip="${AUTO_IP}"
else
    read -p "(e.g. 154.26.214.23):" main_ip
fi

[[ -z "${main_ip}" ]] && echo -e "Error: IP is empty, cancel..." && exit 1

# 2. 获取子网数量
echo -e "\nPlease input how many /24 you want to use, max is 5"
read -p "(Default: 1):" user_ip_num
[[ -z "${user_ip_num}" ]] && user_ip_num=1

echo -e "\nRunning..."

# 3. 清理旧规则
iptables -t nat -F

# 4. 配置 SNAT (上网)
iptables -t nat -A POSTROUTING -o ${WAN_INTERFACE} -j SNAT --to ${main_ip}

# 5. 循环生成规则
for (( c = 1; c <= ${user_ip_num}; c++ ));do
    for (( d = 1; d <= 255; d++ ));do
        user_ip=${USER_IP_HEAD}${c}"."${d}
        
        # 跳过网关 IP
        if [[ "${user_ip}" == "${GATEWAY_IP}" ]]; then
            continue
        fi

        # 端口计算
        if (("$d" < 10)); then
            ssh_port="6"${c}"00"${d}
            user_port_first=${c}"00"${d}"0"
            user_port_last=${c}"00"${d}"9"
        elif (("$d" < 100)); then
            ssh_port="6"${c}"0"${d}
            user_port_first=${c}"0"${d}"0"
            user_port_last=${c}"0"${d}"9"
        else
            ssh_port="6"${c}${d}
            user_port_first=${c}${d}"0"
            user_port_last=${c}${d}"9"
        fi
        
        # DNAT 规则
        iptables -t nat -A PREROUTING -p tcp -m tcp --dport ${ssh_port} -j DNAT --to-destination ${user_ip}:22
        iptables -t nat -A PREROUTING -p tcp -m tcp --dport ${user_port_first}:${user_port_last} -j DNAT --to-destination ${user_ip}
        iptables -t nat -A PREROUTING -p udp -m udp --dport ${user_port_first}:${user_port_last} -j DNAT --to-destination ${user_ip}    
    done
    
    # 伪装规则
    iptables -t nat -A POSTROUTING -s ${USER_IP_HEAD}${c}.0/24 -j MASQUERADE
done

# 6. 保存规则
if command -v iptables-save >/dev/null 2>&1; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    echo "Rules saved to /etc/iptables/rules.v4"
    # 如果安装了 netfilter-persistent 则再次保存
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save
    fi
else
    service iptables save
    service iptables restart
fi

echo -e "Done! NAT configured for ${main_ip}"
