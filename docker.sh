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
    centos|opencloudos|alinux|almalinux)
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
    yum install -y sudo wget curl
    sudo yum install -y device-mapper-persistent-data lvm2
    yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo || dnf config-manager --add-repo=http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    
    if [[ ${OFFLINE_ACTION} = "download" ]]; then
      yumdownloader --destdir=./docker-images/rpm --resolve wget curl docker-ce docker-ce-cli containerd.io
    else
      sudo yum install -y docker-ce docker-ce-cli containerd.io --skip-broken
    fi
  fi
  if [[ ! ${OFFLINE_ACTION} = "download" ]]; then
    sed -i 's#ExecStart=/usr/bin/dockerd -H fd://#ExecStart=/usr/bin/dockerd#g' /lib/systemd/system/docker.service
    docker_daemon
    sudo systemctl daemon-reload
    sudo systemctl enable docker
    sudo systemctl restart docker
    if [[ -x "$(command -v docker)" ]]; then
      print_ok "docker安装完成"
      docker_compose
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
  sudo yum -y remove docker-ce.x86_64
  sudo yum -y remove docker-*
  sudo rm -rf /var/lib/docker
  sudo rm -rf /etc/docker /etc/systemd/system/docker.service.d
  sudo rm -rf /lib/systemd/system/{docker.service,docker.socket}
  rm /var/lib/dpkg/info/$nomdupaquet* -f
}


function install_ubuntu_dk() {
  ECHOY "正在安装docker，请耐心等候..."

  # 判断是否下载，或者从deb包加载
  if [[ ${OFFLINE_ACTION} = "install" ]]; then
    echo '离线安装......'
    sudo dpkg -i ./docker-images/deb/*.deb
  else
    apt-get -y update
    apt-get install -y sudo wget curl
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common
    # curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
    # if [[ $? -ne 0 ]];then
    #   curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
    # fi
    curl -sS https://download.docker.com/linux/debian/gpg | gpg --dearmor > /usr/share/keyrings/docker-ce.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-ce.gpg] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu $(lsb_release -sc) stable" > /etc/apt/sources.list.d/docker.list

    sudo apt-get update
    if [[ ${OFFLINE_ACTION} = "download" ]]; then
      sudo apt install -y aptitude
      sudo aptitude --download-only install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      mkdir -p ./docker-images/deb
      cp /var/cache/apt/archives/*.deb ./docker-images/deb
    else
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi
  fi

  if [[ ! ${OFFLINE_ACTION} = "download" ]]; then
    sed -i 's#ExecStart=/usr/bin/dockerd -H fd://#ExecStart=/usr/bin/dockerd#g' /lib/systemd/system/docker.service
    docker_daemon
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    if [[ -x "$(command -v docker)" ]]; then
      print_ok "docker安装完成"
      docker_compose
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
  sudo apt-get -y autoremove docker-* --purge
  sudo apt-get -y autoremove --purge
  sudo apt-get -y clean
  sudo rm -rf /var/lib/docker
  sudo rm -rf /etc/docker /etc/systemd/system/docker.service.d
  sudo rm -rf /lib/systemd/system/{docker.service,docker.socket}
  rm /var/lib/dpkg/info/$nomdupaquet* -f
}

function install_debian_dk() {
  # 判断是否下载，或者从deb包加载
  if [[ ${OFFLINE_ACTION} = "install" ]]; then
    echo '离线安装......'
    sudo dpkg -i ./docker-images/deb/*.deb
  else
    ECHOY "正在安装docker，请耐心等候..."
    apt-get -y update
    apt-get install -y wget curl
    sudo apt install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common
    curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/debian/gpg | sudo apt-key add -
    if [[ $? -ne 0 ]];then
      curl -fsSL https://mirrors.ustc.edu.cn/docker-ce/linux/debian/gpg | sudo apt-key add -
    fi
    sudo apt-key fingerprint 0EBFCD88
    if [[ `sudo apt-key fingerprint 0EBFCD88 | grep -c "0EBF CD88"` = '0' ]]; then
      print_error "密匙验证出错，或者没下载到密匙了，请检查网络，或者上游有问题"
      exit 1
    fi
    sudo add-apt-repository -y "deb [arch=amd64] https://mirrors.ustc.edu.cn/docker-ce/linux/debian $(lsb_release -cs) stable"
    sudo apt update
    if [[ ${OFFLINE_ACTION} = "download" ]]; then
      sudo apt install -y aptitude
      sudo aptitude --download-only install -y docker-ce docker-ce-cli containerd.io
      mkdir -p ./docker-images/deb
      cp /var/cache/apt/archives/*.deb ./docker-images/deb
    else
      sudo apt install -y docker-ce docker-ce-cli containerd.io
    fi
  fi

  if [[ ! ${OFFLINE_ACTION} = "download" ]]; then
    sed -i 's#ExecStart=/usr/bin/dockerd -H fd://#ExecStart=/usr/bin/dockerd#g' /lib/systemd/system/docker.service
    docker_daemon
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    if [[ -x "$(command -v docker)" ]]; then
      print_ok "docker安装完成"
      docker_compose
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
  sudo apt -y autoremove docker-* --purge
  sudo apt -y autoremove --purge
  sudo apt -y clean
  sudo rm -rf /var/lib/docker
  sudo rm -rf /etc/docker /etc/systemd/system/docker.service.d
  sudo rm -rf /lib/systemd/system/{docker.service,docker.socket}
  rm /var/lib/dpkg/info/$nomdupaquet* -f
}

function hello_world() {
  if [ -n "${OFFLINE_ACTION}" ]; then
    return
  fi
  ECHOY "测试docker拉取镜像是否成功"
  sudo docker run hello-world |tee build.log
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
    ECHOY "重启服务器后，用 sudo docker run hello-world 命令测试吧，能拉取成功就成了"
    rm -fr build.log
    sleep 2
    exit 1
  fi
}

function docker_daemon() {
sudo mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<-EOF
{
    "registry-mirrors": ["https://hub.sivpn.cn"],
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