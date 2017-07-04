
# Problem: --archlist=x86_64 really means "x86_64 and i686". Therefore yum
# tries to resolve dependencies of i686 packages. Sometimes this fails due
# to an upgraded x86_64 only package available in the fuel repo. For
# instance, when yum is asked to download dmraid package it tries to resolve
# the dependencies of i686 version. This fails since the upgraded
# device-mapper-libs package (from the fuel repo) is x86_64 only:
# Package: device-mapper-libs-1.02.79-8.el6.i686 (base)
#   Requires: device-mapper = 1.02.79-8.el6
#   Available: device-mapper-1.02.79-8.el6.x86_64 (base)
#     device-mapper = 1.02.79-8.el6
#   Installing: device-mapper-1.02.90-2.mira1.x86_64 (fuel)
#        device-mapper = 1.02.90-2.mira1
# The obvious solution is to exclude i686 packages. However syslinux
# package depends on i686 package syslinux-nonlinux (which contians
# the binaries that run in the syslinux environment). Since excluding
# packages by regexp is impossible (only glob patterns are supported)
# base and updates repos are "cloned". Those "cloned" repos contain
# a few whitelisted i686 packages (for now only syslinux).
# Note: these packages should be also excluded from base and updates.
x86_rpm_packages_whitelist:=syslinux*

#提供/etc/yum.conf文件内容
define yum_conf
[main]
#//缓存的目录，yum 在此存储下载的rpm 包和数据库，默认设置为/var/cache/yum
cachedir=$(BUILD_DIR)/mirror/centos/cache
#//安装完成后是否保留软件包，0为不保留（默认为0），1为保留
keepcache=0
#//Debug 信息输出等级，范围为0-10，缺省为2
debuglevel=6
#//yum 日志文件位置。用户可以到/var/log/yum.log 文件去查询过去所做的更新。
logfile=$(BUILD_DIR)/mirror/centos/yum.log
#//包的策略。一共有两个选项，newest 和last，这个作用是如果你设置了多个repository，而同一软件在不同的repository 中同时存在，
#yum 应该安装哪一个，如果是newest，则yum 会安装最新的那个版本。如果是last，则yum 会将服务器id 以字母表排序，并选择最后的那个服务器上的软件安装。
#一般都是选newest。
#pkgpolicy=newest
#// 排除某些软件在升级名单之外，可以用通配符，列表中各个项目要用空格隔开，这个对于安装了诸如美化包，中文补丁的朋友特别有用。
exclude=ntp-dev*
#//有1和0两个选项，设置为1，则yum 只会安装和系统架构匹配的软件包，例如，yum 不会将i686的软件包安装在适合i386的系统中。默认为1。
exactarch=1
#//这是一个update 的参数，具体请参阅yum(8)，简单的说就是相当于upgrade，允许更新陈旧的RPM包。
obsoletes=1
#// 有1和0两个选择，分别代表是否是否进行gpg(GNU Private Guard) 校验，以确定rpm 包的来源是有效和安全的。
# 这个选项如果设置在[main]部分，则对每个repository 都有效。默认值为0。
gpgcheck=0
#//是否启用插件，默认1为允许，0表示不允许。我们一般会用yum-fastestmirror这个插件。
plugins=1
#//一个插件就是一个".py"的python脚本文件，这个文件会被安装到一个通过yum.conf的pluginpath选项指定的目录。
pluginpath=$(BUILD_DIR)/mirror/centos/etc/yum-plugins
#//A list of directories where yum should look for plugin configuration files. Default is ‘/etc/yum/pluginconf.d’
pluginconfpath=$(BUILD_DIR)/mirror/centos/etc/yum/pluginconf.d
#// 列出yum寻找.repo文件的目录，默认是/etc/yum/repos.d
reposdir=$(BUILD_DIR)/mirror/centos/etc/yum.repos.d
sslverify=False
endef

#定义官方的repo(含base,updates,...)
define yum_repo_official
[base]
name=CentOS-$(CENTOS_RELEASE) - Base
#mirrorlist=http://mirrorlist.centos.org/?release=$(CENTOS_RELEASE)&arch=$(CENTOS_ARCH)&repo=os
baseurl=$(MIRROR_CENTOS)/os/$(CENTOS_ARCH)
gpgcheck=0
enabled=1
exclude=*i686 $(x86_rpm_packages_whitelist)
priority=90

[updates]
name=CentOS-$(CENTOS_RELEASE) - Updates
#mirrorlist=http://mirrorlist.centos.org/?release=$(CENTOS_RELEASE)&arch=$(CENTOS_ARCH)&repo=updates
baseurl=$(MIRROR_CENTOS)/updates/$(CENTOS_ARCH)
gpgcheck=0
enabled=1
exclude=*i686 $(x86_rpm_packages_whitelist)
priority=90

[base_i686_whitelisted]
name=CentOS-$(CENTOS_RELEASE) - Base
#mirrorlist=http://mirrorlist.centos.org/?release=$(CENTOS_RELEASE)&arch=$(CENTOS_ARCH)&repo=os
baseurl=$(MIRROR_CENTOS)/os/$(CENTOS_ARCH)
gpgcheck=0
enabled=1
includepkgs=$(x86_rpm_packages_whitelist)
priority=90

[updates_i686_whitelisted]
name=CentOS-$(CENTOS_RELEASE) - Updates
#mirrorlist=http://mirrorlist.centos.org/?release=$(CENTOS_RELEASE)&arch=$(CENTOS_ARCH)&repo=updates
baseurl=$(MIRROR_CENTOS)/updates/$(CENTOS_ARCH)
gpgcheck=0
enabled=1
includepkgs=$(x86_rpm_packages_whitelist)
priority=90
endef

#定义仓库extra
define yum_repo_extras
[extras]
name=CentOS-$(CENTOS_RELEASE) - Extras
#mirrorlist=http://mirrorlist.centos.org/?release=$(CENTOS_RELEASE)&arch=$(CENTOS_ARCH)&repo=extras
baseurl=$(MIRROR_CENTOS)/extras/$(CENTOS_ARCH)
gpgcheck=0
enabled=1
exclude=*i686
priority=90

[centosplus]
name=CentOS-$(CENTOS_RELEASE) - Plus
#mirrorlist=http://mirrorlist.centos.org/?release=$(CENTOS_RELEASE)&arch=$(CENTOS_ARCH)&repo=centosplus
baseurl=$(MIRROR_CENTOS)/centosplus/$(CENTOS_ARCH)
gpgcheck=0
enabled=0
priority=90

[contrib]
name=CentOS-$(CENTOS_RELEASE) - Contrib
#mirrorlist=http://mirrorlist.centos.org/?release=$(CENTOS_RELEASE)&arch=$(CENTOS_ARCH)&repo=contrib
baseurl=$(MIRROR_CENTOS)/contrib/$(CENTOS_ARCH)
gpgcheck=0
enabled=0
priority=90
endef

#定义仓库fuel
define yum_repo_fuel
[fuel]
name=Fuel Packages
baseurl=$(MIRROR_FUEL)
gpgcheck=0
enabled=1
priority=20
exclude=*debuginfo*
endef

# Accept EXTRA_RPM_REPOS in a form of a list of: name,url,priority
# Accept EXTRA_RPM_REPOS in a form of list of (default priority=10): name,url
#将$1按','号划分，并取第一部分
get_repo_name=$(shell echo $1 | cut -d ',' -f 1)
#将$1按','号划分，并取第二部分
get_repo_url=$(shell echo $1 | cut -d ',' -f2)
#将$1按','号划分，并取第三部分，如果第三部分没有配置，则取10，否则取配置值
get_repo_priority=$(shell val=`echo $1 | cut -d ',' -f3`; echo $${val:-10})

# It's a callable object.
# Usage: $(call create_extra_repo,repo)
# where:
# repo=repo_name,http://path_to_the_repo,repo_priority
# repo_priority is a number from 1 to 99
# 生成extra仓库，$1按逗号划分第一部分为仓库名称
# $1 按逗号划分第二部分为url
# $1 按逗号划分第三部分为优先级
define create_extra_repo
[$(call get_repo_name,$1)]
name = Repo "$(call get_repo_name,$1)"
baseurl = $(call get_repo_url,$1)
gpgcheck = 0
enabled = 1
priority = $(call get_repo_priority,$1)
exclude=*debuginfo*
endef

define create_fuelnode_repo
[$(call get_repo_name,$1)]
name = Repo "$(call get_repo_name,$1)"
baseurl = file:///var/www/nailgun/extra-repos/$(call get_repo_name,$1)
gpgcheck = 0
enabled = 1
priority = $(call get_repo_priority,$1)
endef

