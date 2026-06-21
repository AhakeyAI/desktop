PACKAGE_NAME = ahakey-ble-bridge
VERSION = 1.0.0
ARCH = all
DEB_NAME = $(PACKAGE_NAME)_$(VERSION)_$(ARCH).deb

.PHONY: all build clean install uninstall

all: build

build:
	@echo "Building $(DEB_NAME)..."
	@cp bridge_gui.py deb_package/opt/ahakey/ble-bridge/
	@chmod 644 deb_package/opt/ahakey/ble-bridge/bridge_gui.py
	@chmod 755 deb_package/DEBIAN/postinst deb_package/DEBIAN/prerm
	@chmod 755 deb_package/usr/bin/ahakey-ble-bridge
	@dpkg-deb --build deb_package $(DEB_NAME)
	@echo "Built: $(DEB_NAME)"

clean:
	@echo "Cleaning..."
	@rm -f $(DEB_NAME)
	@rm -f deb_package/opt/ahakey/ble-bridge/bridge_gui.py

install: build
	@echo "Installing..."
	@sudo dpkg -i $(DEB_NAME)
	@sudo apt-get install -f -y

uninstall:
	@echo "Uninstalling..."
	@sudo dpkg -r $(PACKAGE_NAME)
