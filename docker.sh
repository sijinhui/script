#!/usr/bin/env bash

# 字体颜色配置
Green="\033[32;1m"
Red="\033[31m"
Yellow="\033[33;1m"
Blue="\033[36;1m"
Font="\033[0m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
OK="${Green}[OK]${Font}"
ERROR="${Red}[ERROR]${Font}"

function print_ok() {
  echo
  echo -e " ${OK} ${Blue} $1 ${Font}"
  echo
}
function print_error() {
  echo
  echo -e "${ERROR} ${RedBG} $1 ${Font}"
  echo
}

function ECHOY() {
  echo
  echo -e "${Yellow} $1 ${Font}"
  echo
}
function ECHOB() {
  echo -e "${Blue} $1 ${Font}"
}
function ECHOG() {
  echo
  echo -e "${Green} $1 ${Font}"
  echo
}

if [[ ! "$USER" == "root" ]]; then
  print_error "警告：请使用root用户操作!~~"
  exit 1
fi

function system_check() {
  os_id=$(source /etc/os-release && echo "$ID")
  case "$os_id" in
    centos|opencloudos|alinux)
      [[ ${CHONGXIN} == "YES" ]] && uninstall_centos_dk
      install_centos_dk
      ;;
    ubuntu)
      [[ ${CHONGXIN} == "YES" ]] && uninstall_ubuntu_dk
      install_ubuntu_dk
      ;;
    debian)
      [[ ${CHONGXIN} == "YES" ]] && uninstall_debian_dk
      install_debian_dk
      ;;
    *)
      print_error "不支持的系统!"
      exit 1
      ;;
  esac
}

# function system_check() {
#   if [[ "$(. /etc/os-release && echo "$ID")" == "centos" ]]; then
#     [[ ${CHONGXIN} == "YES" ]] && uninstall_centos_dk
#     install_centos_dk
#   elif [[ "$(. /etc/os-release && echo "$ID")" == "ubuntu" ]]; then
#     [[ ${CHONGXIN} == "YES" ]] && uninstall_ubuntu_dk
#     install_ubuntu_dk
#   elif [[ "$(. /etc/os-release && echo "$ID")" == "debian" ]]; then
#     [[ ${CHONGXIN} == "YES" ]] && uninstall_debian_dk
#     install_debian_dk
#   else
#     print_error "本一键安装docker脚本只支持（centos、ubuntu和debian）!"
#     exit 1
#   fi
# }

function jiance_dk() {
  if [[ ${OFFLINE_ACTION} == 'download' ]]; then
    if [[ -x "$(command -v docker)" ]]; then
      ECHOY "检测到docker存在，安装已退出"
      exit 1
    fi
    return
  fi
  if [[ -x "$(command -v docker)" ]]; then
    ECHOY "检测到docker存在，是否重新安装?"
    ECHOG "重新安装会把您现有的所有容器及镜像全部删除，请慎重!"
    while :; do
    export CHONGXIN=""
    read -p " 输入[ N/n ]退出安装，输入[ Y/y ]回车继续： " ANDK
    case $ANDK in
     [Yy])
       export CHONGXIN="YES"
    break
    ;;
    [Nn])
      export CHONGXIN="NO"
      ECHOG "您选择了退出安装程序!"
      sleep 1
      exit 1
    break
    ;;
    *)
      ECHOB "提示：请输入正确的选择!"
    ;;
    esac
    done
  fi
}

function install_centos_dk() {
  if [[ ${OFFLINE_ACTION} = "install" ]]; then
    echo '离线安装......'
    yum install ./docker-images/rpm/*.rpm -y
  else
    ECHOY "正在安装docker，请耐心等候..."
    yum install -y wget curl
    yum install -y device-mapper-persistent-data lvm2
    yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo || dnf config-manager --add-repo=http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    
    if [[ ${OFFLINE_ACTION} = "download" ]]; then
      yumdownloader --destdir=./docker-images/rpm --resolve wget curl docker-ce docker-ce-cli containerd.io
    else
      yum install -y docker-ce docker-ce-cli containerd.io --skip-broken
    fi
  fi
  if [[ ! ${OFFLINE_ACTION} = "download" ]]; then
    sed -i 's#ExecStart=/usr/bin/dockerd -H fd://#ExecStart=/usr/bin/dockerd#g' /lib/systemd/system/docker.service
    docker_daemon
    systemctl daemon-reload
    systemctl enable docker
    systemctl restart docker
    if [[ -x "$(command -v docker)" ]]; then
      print_ok "docker安装完成"
      docker_compose
      install_nvidia_toolkit
    else
      print_error "docker安装失败"
      exit 1
    fi
  fi

}

function uninstall_centos_dk() {
  ECHOY "正在御载docker..."
  docker stop $(docker ps -a -q)
  docker rm $(docker ps -a -q)
  docker rmi $(docker images -q)
  yum -y remove docker-ce.x86_64
  yum -y remove docker-*
  rm -rf /var/lib/docker
  rm -rf /etc/docker /etc/systemd/system/docker.service.d
  rm -rf /lib/systemd/system/{docker.service,docker.socket}
  rm /var/lib/dpkg/info/$nomdupaquet* -f
}


function install_ubuntu_dk() {
  ECHOY "正在安装docker，请耐心等候..."

  # 判断是否下载，或者从deb包加载
  if [[ ${OFFLINE_ACTION} = "install" ]]; then
    echo '离线安装......'
    dpkg -i ./docker-images/deb/*.deb
  else
    apt-get -y update
    apt-get install -y wget curl
    apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
      "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    if [[ ${OFFLINE_ACTION} = "download" ]]; then
      apt install -y aptitude
      aptitude --download-only install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      mkdir -p ./docker-images/deb
      cp /var/cache/apt/archives/*.deb ./docker-images/deb
    else
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
  fi

  if [[ ! ${OFFLINE_ACTION} = "download" ]]; then
    sed -i 's#ExecStart=/usr/bin/dockerd -H fd://#ExecStart=/usr/bin/dockerd#g' /lib/systemd/system/docker.service
    docker_daemon
    systemctl daemon-reload
    systemctl restart docker
    if [[ -x "$(command -v docker)" ]]; then
      print_ok "docker安装完成"
      docker_compose
      install_nvidia_toolkit
    else
      print_error "docker安装失败"
      exit 1
    fi
  fi
}

function uninstall_ubuntu_dk() {
  ECHOY "正在御载docker..."
  docker stop $(docker ps -a -q)
  docker rm $(docker ps -a -q)
  docker rmi $(docker images -q)
  apt-get -y autoremove docker-* --purge
  apt-get -y autoremove --purge
  apt-get -y clean
  rm -rf /var/lib/docker
  rm -rf /etc/docker /etc/systemd/system/docker.service.d
  rm -rf /lib/systemd/system/{docker.service,docker.socket}
  rm /var/lib/dpkg/info/$nomdupaquet* -f
}

function install_debian_dk() {
  # 判断是否下载，或者从deb包加载
  if [[ ${OFFLINE_ACTION} = "install" ]]; then
    echo '离线安装......'
    dpkg -i ./docker-images/deb/*.deb
  else
    ECHOY "正在安装docker，请耐心等候..."
    apt-get -y update
    apt-get install -y wget curl
    apt install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common
    curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/debian/gpg | apt-key add -
    if [[ $? -ne 0 ]];then
      curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/debian/gpg | apt-key add -
    fi
    apt-key fingerprint 0EBFCD88
    if [[ `apt-key fingerprint 0EBFCD88 | grep -c "0EBF CD88"` = '0' ]]; then
      print_error "密匙验证出错，或者没下载到密匙了，请检查网络，或者上游有问题"
      exit 1
    fi
    add-apt-repository -y "deb [arch=amd64] https://mirrors.ustc.edu.cn/docker-ce/linux/debian $(lsb_release -cs) stable"
    apt update
    if [[ ${OFFLINE_ACTION} = "download" ]]; then
      apt install -y aptitude
      aptitude --download-only install -y docker-ce docker-ce-cli containerd.io
      mkdir -p ./docker-images/deb
      cp /var/cache/apt/archives/*.deb ./docker-images/deb
    else
      apt install -y docker-ce docker-ce-cli containerd.io
    fi
  fi

  if [[ ! ${OFFLINE_ACTION} = "download" ]]; then
    sed -i 's#ExecStart=/usr/bin/dockerd -H fd://#ExecStart=/usr/bin/dockerd#g' /lib/systemd/system/docker.service
    docker_daemon
    systemctl daemon-reload
    systemctl restart docker
    if [[ -x "$(command -v docker)" ]]; then
      print_ok "docker安装完成"
      docker_compose
      install_nvidia_toolkit
    else
      print_error "docker安装失败"
      exit 1
    fi
  fi

}

function uninstall_debian_dk() {
  ECHOY "正在御载docker..."
  docker stop $(docker ps -a -q)
  docker rm $(docker ps -a -q)
  docker rmi $(docker images -q)
  apt -y autoremove docker-* --purge
  apt -y autoremove --purge
  apt -y clean
  rm -rf /var/lib/docker
  rm -rf /etc/docker /etc/systemd/system/docker.service.d
  rm -rf /lib/systemd/system/{docker.service,docker.socket}
  rm /var/lib/dpkg/info/$nomdupaquet* -f
}

function hello_world() {
  if [ -n "${OFFLINE_ACTION}" ]; then
    return
  fi
  ECHOY "测试docker拉取镜像是否成功"
  docker run hello-world |tee build.log
  if [[ `docker ps -a | grep -c "hello-world"` -ge '1' ]] && [[ `grep -c "hub.docker.com" build.log` -ge '1' ]]; then
    ECHOG "测试镜像拉取成功，正在删除测试镜像..."
    docker stop $(docker ps -a -q)
    docker rm $(docker ps -a -q)
    docker rmi $(docker images -q)
    rm -fr build.log
    ECHOY "测试镜像删除完毕"
    print_ok "docker安装成功"
  else
    ECHOY "docker虽然安装成功但是拉取镜像失败，这个原因很多是因为以前的docker没御载完全造成的，或者容器网络问题"
    ECHOY "重启服务器后，用 docker run hello-world 命令测试吧，能拉取成功就成了"
    rm -fr build.log
    sleep 2
    exit 1
  fi
}

function check_nvidia_driver() {
  if command -v nvidia-smi &> /dev/null; then
    ECHOG "检测到NVIDIA显卡驱动已安装"
    nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1
    return 0
  else
    ECHOY "未检测到NVIDIA显卡驱动"
    return 1
  fi
}

function install_nvidia_container_toolkit_centos() {
  ECHOY "正在为CentOS/RedHat系统安装nvidia-container-toolkit..."

  if [[ ${OFFLINE_ACTION} = "install" ]]; then
    echo "离线安装nvidia-container-toolkit..."
    if command -v dnf &> /dev/null; then
      dnf install ./docker-images/rpm/nvidia-container-toolkit*.rpm ./docker-images/rpm/libnvidia-container*.rpm -y
    else
      yum install ./docker-images/rpm/nvidia-container-toolkit*.rpm ./docker-images/rpm/libnvidia-container*.rpm -y
    fi
  else
    # 安装curl依赖
    if command -v dnf &> /dev/null; then
      dnf install -y curl
    else
      yum install -y curl
    fi

    # 配置NVIDIA仓库
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
      tee /etc/yum.repos.d/nvidia-container-toolkit.repo

    if [[ ${OFFLINE_ACTION} = "download" ]]; then
      mkdir -p ./docker-images/rpm
      if command -v dnf &> /dev/null; then
        dnf download --resolve --destdir=./docker-images/rpm nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
      else
        yumdownloader --destdir=./docker-images/rpm --resolve nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
      fi
    else
      # 安装完整的包集合
      if command -v dnf &> /dev/null; then
        dnf install -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
      else
        yum install -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
      fi
    fi
  fi

  if [[ ! ${OFFLINE_ACTION} = "download" ]]; then
    # 配置Docker runtime
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
    print_ok "nvidia-container-toolkit安装完成"
  fi
}

function install_nvidia_container_toolkit_ubuntu() {
  ECHOY "正在为Ubuntu系统安装nvidia-container-toolkit..."

  if [[ ${OFFLINE_ACTION} = "install" ]]; then
    echo "离线安装nvidia-container-toolkit..."
    dpkg -i ./docker-images/deb/nvidia-container-toolkit*.deb ./docker-images/deb/libnvidia-container*.deb
  else
    # 安装依赖
    apt-get update
    apt-get install -y --no-install-recommends curl gnupg2

    # 配置GPG key和仓库
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
      sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
      tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    # 更新包列表
    apt-get update

    if [[ ${OFFLINE_ACTION} = "download" ]]; then
      mkdir -p ./docker-images/deb
      apt-get install -y aptitude
      aptitude --download-only install -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
      cp /var/cache/apt/archives/nvidia-container-toolkit*.deb ./docker-images/deb/ 2>/dev/null || true
      cp /var/cache/apt/archives/libnvidia-container*.deb ./docker-images/deb/ 2>/dev/null || true
    else
      # 安装完整的包集合
      apt-get install -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
    fi
  fi

  if [[ ! ${OFFLINE_ACTION} = "download" ]]; then
    # 配置Docker runtime
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
    print_ok "nvidia-container-toolkit安装完成"
  fi
}

function install_nvidia_container_toolkit_debian() {
  ECHOY "正在为Debian系统安装nvidia-container-toolkit..."

  if [[ ${OFFLINE_ACTION} = "install" ]]; then
    echo "离线安装nvidia-container-toolkit..."
    dpkg -i ./docker-images/deb/nvidia-container-toolkit*.deb ./docker-images/deb/libnvidia-container*.deb
  else
    # 安装依赖
    apt-get update
    apt-get install -y --no-install-recommends curl gnupg2

    # 配置GPG key和仓库
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
      sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
      tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    # 更新包列表
    apt update

    if [[ ${OFFLINE_ACTION} = "download" ]]; then
      mkdir -p ./docker-images/deb
      apt install -y aptitude
      aptitude --download-only install -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
      cp /var/cache/apt/archives/nvidia-container-toolkit*.deb ./docker-images/deb/ 2>/dev/null || true
      cp /var/cache/apt/archives/libnvidia-container*.deb ./docker-images/deb/ 2>/dev/null || true
    else
      # 安装完整的包集合
      apt install -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
    fi
  fi

  if [[ ! ${OFFLINE_ACTION} = "download" ]]; then
    # 配置Docker runtime
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
    print_ok "nvidia-container-toolkit安装完成"
  fi
}

function install_nvidia_toolkit() {
  if check_nvidia_driver; then
    os_id=$(source /etc/os-release && echo "$ID")
    case "$os_id" in
      centos|opencloudos|alinux)
        install_nvidia_container_toolkit_centos
        ;;
      ubuntu)
        install_nvidia_container_toolkit_ubuntu
        ;;
      debian)
        install_nvidia_container_toolkit_debian
        ;;
      *)
        print_error "不支持的系统!"
        return 1
        ;;
    esac

    # 验证安装
    if [[ ! ${OFFLINE_ACTION} = "download" ]]; then
      test_nvidia_toolkit
    fi
  else
    ECHOY "跳过nvidia-container-toolkit安装（未检测到NVIDIA驱动）"
  fi
}

function test_nvidia_toolkit() {
  if [ -n "${OFFLINE_ACTION}" ]; then
    return
  fi

  ECHOY "测试nvidia-container-toolkit是否正常工作..."

  # 检测nvidia-container-runtime命令是否存在
  if command -v nvidia-container-runtime &> /dev/null; then
    ECHOG "nvidia-container-runtime命令检测成功！"
    nvidia-container-runtime --version
    print_ok "nvidia-container-toolkit安装验证通过"
  else
    print_error "nvidia-container-runtime命令未找到，安装可能失败"
    ECHOY "您可以稍后手动运行以下命令测试GPU支持："
    ECHOY "  docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi"
    return 1
  fi
}

function docker_daemon() {
mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<-EOF
{
    "registry-mirrors": ["https://hub.xiaosi.cc"],
    "runtimes": {
        "nvidia": {
            "path": "/usr/bin/nvidia-container-runtime",
            "runtimeArgs": []
         }
    }
}
EOF
chmod +x /etc/docker/daemon.json
}

function docker_compose() {
  if [ -f /usr/bin/docker-compose ]; then
    echo "/usr/bin/docker-compose 文件存在"
  else
    echo -e "\033[36m开始在线安装docker-compose......\033[0m"
    # curl -L https://get.daocloud.io/docker/compose/releases/download/v2.16.0/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
    curl -L https://xiaosi.cc/docker-compose > /usr/bin/docker-compose
    chmod +x /usr/bin/docker-compose
  fi
}


memu() {
  jiance_dk
  system_check
  hello_world
}

#memu "$@"

while [ ${#} -gt 0 ]; do
	case $1 in
		-D|--download)
		  echo -e "\033[36m开始生成docker离线安装文件包......\033[0m"
			OFFLINE_ACTION='download'
			break
			;;
		-I|--install)
		  echo -e "\033[36m加载docker离线安装环境......\033[0m"
			OFFLINE_ACTION='install'
			break
			;;
		-C|--compose)
		  echo -e "\033[36m开始在线安装docker-compose......\033[0m"
      curl -L https://xiaosi.cc/docker-compose > /usr/bin/docker-compose
      chmod +x /usr/bin/docker-compose
			break
			;;
		*)
			echo '参数错误'
			;;
	esac
	shift 1
done

memu "$@"