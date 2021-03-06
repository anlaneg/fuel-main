.PHONY: mirror clean clean-mirror make-changelog

mirror: $(BUILD_DIR)/mirror/build.done
make-changelog: $(BUILD_DIR)/mirror/make-changelog.done

clean: clean-mirror

clean-mirror:
	sudo rm -rf $(BUILD_DIR)/mirror

include $(SOURCE_DIR)/mirror/centos/module.mk
include $(SOURCE_DIR)/mirror/ubuntu/module.mk

#构造centos镜像，构造ubuntu镜像
$(BUILD_DIR)/mirror/build.done: \
		$(BUILD_DIR)/mirror/centos/build.done \
		$(BUILD_DIR)/mirror/ubuntu/build.done
	$(ACTION.TOUCH)

#执行report-changelog.sh脚本,生成centos,ubuntu的changelog
$(BUILD_DIR)/mirror/make-changelog.done: $(BUILD_DIR)/mirror/build.done
	sudo bash -c "export LOCAL_MIRROR=$(LOCAL_MIRROR); \
		$(SOURCE_DIR)/report-changelog.sh"
	$(ACTION.TOUCH)
