#!/bin/bash

# 批量创建用户脚本
# 功能：创建用户、设置初始密码、强制首次登录修改密码、加入sudo和docker组

# 定义初始密码
INIT_PASSWORD="AinnovationInittialPassword"

# 定义用户信息数组（格式：用户名:UID:GID）
USER_INFO=(
    "si:1:10511703"
)

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
    echo "错误：请使用root权限运行此脚本"
    exit 1
fi

# 日志文件
LOG_FILE="/var/log/batch_create_users_$(date +%Y%m%d_%H%M%S).log"

echo "========================================" | tee -a "$LOG_FILE"
echo "批量创建用户脚本开始执行" | tee -a "$LOG_FILE"
echo "执行时间: $(date)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# 检查并创建必要的组
check_and_create_groups() {
    echo "" | tee -a "$LOG_FILE"
    echo "检查必要的用户组..." | tee -a "$LOG_FILE"

    # 检查sudo组（某些系统可能是wheel组）
    if getent group sudo &>/dev/null; then
        SUDO_GROUP="sudo"
        echo "  [信息] 找到sudo组" | tee -a "$LOG_FILE"
    elif getent group wheel &>/dev/null; then
        SUDO_GROUP="wheel"
        echo "  [信息] 找到wheel组（替代sudo）" | tee -a "$LOG_FILE"
    else
        echo "  [警告] 未找到sudo或wheel组，将创建sudo组" | tee -a "$LOG_FILE"
        groupadd sudo 2>>"$LOG_FILE"
        SUDO_GROUP="sudo"
        # 配置sudo组权限
        if [ ! -f /etc/sudoers.d/sudo-group ]; then
            echo "%sudo ALL=(ALL:ALL) ALL" > /etc/sudoers.d/sudo-group
            chmod 440 /etc/sudoers.d/sudo-group
            echo "  [成功] sudo组已创建并配置权限" | tee -a "$LOG_FILE"
        fi
    fi

    # 检查docker组
    if ! getent group docker &>/dev/null; then
        echo "  [警告] 未找到docker组，将创建docker组" | tee -a "$LOG_FILE"
        groupadd docker 2>>"$LOG_FILE"
        if [ $? -eq 0 ]; then
            echo "  [成功] docker组已创建" | tee -a "$LOG_FILE"
        else
            echo "  [错误] 创建docker组失败" | tee -a "$LOG_FILE"
        fi
    else
        echo "  [信息] 找到docker组" | tee -a "$LOG_FILE"
    fi

    # 如果docker服务存在，重启以应用组权限
    if systemctl is-active --quiet docker 2>/dev/null; then
        echo "  [信息] Docker服务正在运行" | tee -a "$LOG_FILE"
    fi
}

# 创建用户函数
create_user() {
    local username=$1
    local uid=$2
    local gid=$3

    echo "" | tee -a "$LOG_FILE"
    echo "处理用户: $username (UID:$uid, GID:$gid)" | tee -a "$LOG_FILE"

    # 检查用户是否已存在
    if id "$username" &>/dev/null; then
        echo "  [警告] 用户 $username 已存在，跳过创建" | tee -a "$LOG_FILE"
        # 即使用户已存在，也尝试添加到组
        add_user_to_groups "$username"
        return 1
    fi

    # 检查UID是否已被使用
    if getent passwd "$uid" &>/dev/null; then
        echo "  [警告] UID $uid 已被使用，跳过用户 $username" | tee -a "$LOG_FILE"
        return 1
    fi

    # 创建用户组（如果不存在）
    if ! getent group "$gid" &>/dev/null; then
        groupadd -g "$gid" "$username" 2>>"$LOG_FILE"
        if [ $? -eq 0 ]; then
            echo "  [成功] 创建用户组 GID:$gid" | tee -a "$LOG_FILE"
        else
            echo "  [错误] 创建用户组失败" | tee -a "$LOG_FILE"
            return 1
        fi
    fi

    # 创建用户
    useradd -u "$uid" -g "$gid" -m -s /bin/bash "$username" 2>>"$LOG_FILE"
    if [ $? -ne 0 ]; then
        echo "  [错误] 创建用户 $username 失败" | tee -a "$LOG_FILE"
        return 1
    fi
    echo "  [成功] 用户 $username 创建成功" | tee -a "$LOG_FILE"

    # 设置初始密码
    echo "$username:$INIT_PASSWORD" | chpasswd 2>>"$LOG_FILE"
    if [ $? -ne 0 ]; then
        echo "  [错误] 设置密码失败" | tee -a "$LOG_FILE"
        return 1
    fi
    echo "  [成功] 初始密码设置成功" | tee -a "$LOG_FILE"

    # 强制用户首次登录时修改密码
    chage -d 0 "$username" 2>>"$LOG_FILE"
    if [ $? -ne 0 ]; then
        echo "  [错误] 设置密码过期失败" | tee -a "$LOG_FILE"
        return 1
    fi
    echo "  [成功] 已设置首次登录强制修改密码" | tee -a "$LOG_FILE"

    # 添加用户到sudo和docker组
    add_user_to_groups "$username"

    # 设置家目录权限
    chmod 700 "/home/$username" 2>>"$LOG_FILE"
    chown "$username:$gid" "/home/$username" 2>>"$LOG_FILE"

    echo "  [完成] 用户 $username 配置完成" | tee -a "$LOG_FILE"
    return 0
}

# 添加用户到sudo和docker组的函数
add_user_to_groups() {
    local username=$1

    # 添加到sudo组
    usermod -aG "$SUDO_GROUP" "$username" 2>>"$LOG_FILE"
    if [ $? -eq 0 ]; then
        echo "  [成功] 用户 $username 已添加到 $SUDO_GROUP 组" | tee -a "$LOG_FILE"
    else
        echo "  [错误] 添加用户 $username 到 $SUDO_GROUP 组失败" | tee -a "$LOG_FILE"
    fi

    # 添加到docker组
    if getent group docker &>/dev/null; then
        usermod -aG docker "$username" 2>>"$LOG_FILE"
        if [ $? -eq 0 ]; then
            echo "  [成功] 用户 $username 已添加到 docker 组" | tee -a "$LOG_FILE"
        else
            echo "  [错误] 添加用户 $username 到 docker 组失败" | tee -a "$LOG_FILE"
        fi
    fi
}

# 检查并创建必要的组
check_and_create_groups

# 主循环：遍历用户信息并创建
success_count=0
failed_count=0
skipped_count=0

for user_entry in "${USER_INFO[@]}"; do
    IFS=':' read -r username uid gid <<< "$user_entry"

    create_user "$username" "$uid" "$gid"
    result=$?

    if [ $result -eq 0 ]; then
        ((success_count++))
    elif [ $result -eq 1 ]; then
        ((skipped_count++))
    else
        ((failed_count++))
    fi
done

# 输出统计信息
echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "批量创建用户脚本执行完成" | tee -a "$LOG_FILE"
echo "----------------------------------------" | tee -a "$LOG_FILE"
echo "成功创建: $success_count 个用户" | tee -a "$LOG_FILE"
echo "跳过: $skipped_count 个用户" | tee -a "$LOG_FILE"
echo "失败: $failed_count 个用户" | tee -a "$LOG_FILE"
echo "----------------------------------------" | tee -a "$LOG_FILE"
echo "日志文件: $LOG_FILE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# 显示创建的用户列表及其组成员
echo "" | tee -a "$LOG_FILE"
echo "已创建的用户列表及组成员信息:" | tee -a "$LOG_FILE"
echo "----------------------------------------" | tee -a "$LOG_FILE"
for user_entry in "${USER_INFO[@]}"; do
    IFS=':' read -r username uid gid <<< "$user_entry"
    if id "$username" &>/dev/null; then
        groups_info=$(groups "$username" 2>/dev/null | cut -d: -f2)
        echo "  ✓ $username (UID:$uid) - 组:$groups_info" | tee -a "$LOG_FILE"
    fi
done

# 提示信息
echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "重要提示:" | tee -a "$LOG_FILE"
echo "1. 所有用户初始密码: $INIT_PASSWORD" | tee -a "$LOG_FILE"
echo "2. 用户首次登录时必须修改密码" | tee -a "$LOG_FILE"
echo "3. 所有用户已加入 $SUDO_GROUP 组（拥有sudo权限）" | tee -a "$LOG_FILE"
echo "4. 所有用户已加入 docker 组（可执行docker命令）" | tee -a "$LOG_FILE"
echo "5. 用户需要重新登录后docker组权限才能生效" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

exit 0