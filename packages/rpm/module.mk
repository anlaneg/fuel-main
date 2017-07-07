.PHONY: clean clean-rpm

clean: clean-rpm

clean-rpm:
	-mount | grep '$(BUILD_DIR)/packages/rpm/SANDBOX' | while read entry; do \
		set -- $$entry; \
		mntpt="$$3"; \
		sudo umount $$mntpt; \
	done
	sudo rm -rf $(BUILD_DIR)/packages/rpm

RPM_SOURCES:=$(BUILD_DIR)/packages/rpm/SOURCES

$(BUILD_DIR)/packages/rpm/buildd.tar.gz: SANDBOX_PACKAGES:=@buildsys-build yum yum-utils
$(BUILD_DIR)/packages/rpm/buildd.tar.gz: SANDBOX:=$(BUILD_DIR)/packages/rpm/SANDBOX/buildd
$(BUILD_DIR)/packages/rpm/buildd.tar.gz: export SANDBOX_UP:=$(SANDBOX_UP)
$(BUILD_DIR)/packages/rpm/buildd.tar.gz: export SANDBOX_DOWN:=$(SANDBOX_DOWN)
$(BUILD_DIR)/packages/rpm/buildd.tar.gz: $(BUILD_DIR)/mirror/centos/repo.done \
	$(BUILD_DIR)/mirror/centos/mos-repo.done
	#执行SANDBOX_UP宏
	sh -c "$${SANDBOX_UP}"
	sh -c "$${SANDBOX_DOWN}"
	sudo tar czf $@.tmp -C $(SANDBOX) .
	mv $@.tmp $@


# Usage:
# (eval (call build_rpm,package_name))
# $1 各个包的名称
# $2 目前未传递为NULL,故 $(BUILD_DIR)/packages/rpm/repo$2.done = $(BUILD_DIR)/packages/rpm/repo.done
define build_rpm
$(BUILD_DIR)/packages/rpm/repo$2.done: $(BUILD_DIR)/packages/rpm/$1.done
$(BUILD_DIR)/packages/rpm/repo$2.done: $(BUILD_DIR)/packages/rpm/$1-repocleanup.done

# You can use package name as a target, for example: make ruby21-rubygem-astute
# It will build astute rpm package
$1-rpm: $(BUILD_DIR)/packages/rpm/$1.done

#各项目包的build_rpm目标
$(BUILD_DIR)/packages/rpm/$1.done: SANDBOX:=$(BUILD_DIR)/packages/rpm/SANDBOX/$1
$(BUILD_DIR)/packages/rpm/$1.done: export SANDBOX_DOWN:=$$(SANDBOX_DOWN)
#rpm/$1.done依赖于包被下载并打好包，见$(BUILD_DIR)/packages/source_$1.done
$(BUILD_DIR)/packages/rpm/$1.done: $(BUILD_DIR)/packages/source_$1.done
$(BUILD_DIR)/packages/rpm/$1.done: $(BUILD_DIR)/packages/rpm/buildd.tar.gz

ifneq (late,$(findstring late,$2))
$(BUILD_DIR)/packages/rpm/$1.done: SPECFILE:=$(BUILD_DIR)/repos/$1/specs/$1.spec
$(BUILD_DIR)/repos/$1/specs/$1.spec: $(BUILD_DIR)/repos/repos.done
$(BUILD_DIR)/repos/$1/specs/$1.spec: $(BUILD_DIR)/repos/$1.done
$(BUILD_DIR)/packages/rpm/$1.done: $(BUILD_DIR)/repos/$1/specs/$1.spec
else
$(BUILD_DIR)/packages/rpm/$1.done: SPECFILE:=$(SOURCE_DIR)/packages/rpm/specs/$1.spec
endif

#buildd.tar.gz将被解压到$(BUILD_DIR)/packages/rpm/SANDBOX/$1处
#然后在这个clean的环境下，安装$1依赖的包，并制作$1的rpm包
#创建沙盒的目的是为了生成rpm包
$(BUILD_DIR)/packages/rpm/$1.done:
	mkdir -p $(BUILD_DIR)/packages/rpm/RPMS/x86_64
	#创建$(SANDBOX)目录，并将buildd.tar.gz解压至此处，挂载/proc,/dev,/mirrors
	# 将$1的包copy到/tmp/SOURCES下
	mkdir -p $$(SANDBOX) && \
	sudo tar xzf $(BUILD_DIR)/packages/rpm/buildd.tar.gz -C $$(SANDBOX) && \
	sudo chroot $$(SANDBOX) bash -c "(mkdir -p /tmp/user/0)"
	sudo mount --bind /proc $$(SANDBOX)/proc && \
	sudo mount --bind /dev $$(SANDBOX)/dev && \
	sudo mount --bind $$(LOCAL_MIRROR) $$(SANDBOX)/mirrors && \
	mkdir -p $$(SANDBOX)/tmp/SOURCES && \
	sudo cp -r $(BUILD_DIR)/packages/sources/$1/* $$(SANDBOX)/tmp/SOURCES
	-test -f $(BUILD_DIR)/packages/sources/$1/changelog && cat $(BUILD_DIR)/packages/sources/$1/changelog >> $$(SPECFILE)
	#切换到SANDBOX/tmp目录，并安装$1依赖的包
	sudo cp $$(SPECFILE) $$(SANDBOX)/tmp && \
	sudo chroot $$(SANDBOX) yum-builddep -y /tmp/$1.spec
	#制作$1对应的rpm包
	test -f $$(SANDBOX)/tmp/SOURCES/version && \
		sudo chroot $$(SANDBOX) rpmbuild --nodeps --define "_topdir /tmp" --define "release `awk -F'=' '/RPMRELEASE/ {print $$$$2}' $$(SANDBOX)/tmp/SOURCES/version`" -ba /tmp/$1.spec || \
		sudo chroot $$(SANDBOX) rpmbuild --nodeps --define "_topdir /tmp" -ba /tmp/$1.spec
	#将做好的RPM包copy到packages中
	cp $$(SANDBOX)/tmp/RPMS/*/*.rpm $(BUILD_DIR)/packages/rpm/RPMS/x86_64
	#取消挂载
	sudo sh -c "$$$${SANDBOX_DOWN}"
	$$(ACTION.TOUCH)

ifneq (late,$(findstring late,$2))
$(BUILD_DIR)/packages/rpm/$1-repocleanup.done: SPECFILE:=$(BUILD_DIR)/repos/$1/specs/$1.spec
$(BUILD_DIR)/packages/rpm/$1-repocleanup.done: $(BUILD_DIR)/packages/source_$1.done
else
$(BUILD_DIR)/packages/rpm/$1-repocleanup.done: SPECFILE:=$(SOURCE_DIR)/packages/rpm/specs/$1.spec
endif
$(BUILD_DIR)/packages/rpm/$1-repocleanup.done: $(BUILD_DIR)/mirror/centos/mos-repo.done
	python $(SOURCE_DIR)/packages/rpm/genpkgnames.py $$(SPECFILE) | xargs -I{} sudo find $(LOCAL_MIRROR_MOS_CENTOS_OS_BASEURL)/Packages -type f -regex '.*/{}-[^-]+-[^-]+' -delete
	$$(ACTION.TOUCH)
endef


packages_list:=\
astute \
fuel-agent \
fuel-library$(FUEL_LIBRARY_VERSION) \
fuel-main \
fuel-nailgun \
fuel-ostf \
fuel-ui \
fuelmenu \
nailgun-agent \
network-checker \
python-fuelclient \
shotgun

#针对packages_list中的每个包，调用build_rpm
$(eval $(foreach pkg,$(packages_list),$(call build_rpm,$(pkg))$(NEWLINE)))

#repo.done会被合并，它依赖于各个包的build_rpm
#看$(BUILD_DIR)/packages/rpm/repo$2.done
$(BUILD_DIR)/packages/rpm/repo.done:
	#将$(packages_list)生成的相关rpm包 copy到Packages目录下，并创建新的仓库
	find $(BUILD_DIR)/packages/rpm/RPMS -name '*.rpm' -exec cp -u {} $(LOCAL_MIRROR_MOS_CENTOS_OS_BASEURL)/Packages \;
	createrepo -g $(LOCAL_MIRROR_MOS_CENTOS)/comps.xml \
		-o $(LOCAL_MIRROR_MOS_CENTOS_OS_BASEURL) $(LOCAL_MIRROR_MOS_CENTOS_OS_BASEURL)
	$(ACTION.TOUCH)

$(BUILD_DIR)/packages/rpm/build.done:
ifeq (1,$(strip $(BUILD_PACKAGES)))
# 如果需要构建package,则需要repo.done,而repo.done实际上例赖于package-list中的所有包
$(BUILD_DIR)/packages/rpm/build.done: $(BUILD_DIR)/packages/rpm/repo.done
endif
	$(ACTION.TOUCH)
