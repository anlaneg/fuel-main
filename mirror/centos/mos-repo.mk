mos_centos_empty_installroot:=$(BUILD_DIR)/mirror/centos/dummy_mos_installroot

#同步yum源"fuel"到本地
$(BUILD_DIR)/mirror/centos/mos-download.done: $(BUILD_DIR)/mirror/centos/yum-config.done
	mkdir -p $(@D)
	mkdir -p $(LOCAL_MIRROR_MOS_CENTOS)
	mkdir -p "$(mos_centos_empty_installroot)/cache"
	set -ex ; env TMPDIR="$(mos_centos_empty_installroot)/cache" \
	TMP="$(mos_centos_empty_installroot)/cache" \
	reposync --norepopath --downloadcomps --plugins --delete --arch=$(CENTOS_ARCH) \
	    --cachedir="$(mos_centos_empty_installroot)/cache" \
	    -c $(BUILD_DIR)/mirror/centos/etc/yum.conf --repoid=fuel -p $(LOCAL_MIRROR_MOS_CENTOS)
	$(ACTION.TOUCH)

#创建fuel源对应的仓库
$(BUILD_DIR)/mirror/centos/mos-repo.done: $(BUILD_DIR)/mirror/centos/mos-download.done
	createrepo -g $(LOCAL_MIRROR_MOS_CENTOS)/comps.xml \
	    -o $(LOCAL_MIRROR_MOS_CENTOS)/ $(LOCAL_MIRROR_MOS_CENTOS)/
	$(ACTION.TOUCH)

