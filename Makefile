
# PREFIX is environment variable, but if it is not set, then set default value
ifeq ($(PREFIX),)
	PREFIX := /usr
endif

# Phony targets declaration to prevent conflicts with matching file names
.PHONY: all install clean run doc uninstall

all: build/replay-kit build/replay-kit.desktop

build/gresources.c: assets/sw.js assets/ui.js
	glib-compile-resources --target=$@ --generate-source gresources.xml

build/replay-kit: build/gresources.c
	valac \
		-o $@ \
		--pkg libarchive \
		--pkg json-glib-1.0 \
		--pkg gtk4 \
		--pkg libadwaita-1 \
		--pkg webkitgtk-6.0 \
		--gresources gresources.xml \
		build/gresources.c \
		wacz.vala \
		server.vala \
		app.vala

build/doc:
	valadoc -o $@ \
		--pkg libarchive \
		--pkg json-glib-1.0 \
		--pkg gtk4 \
		--pkg libadwaita-1 \
		--pkg webkitgtk-6.0 \
		--package-name=replay \
		--package-version=$(VERSION) \
		wacz.vala \
		server.vala \
		app.vala

build/replay-kit.desktop:
	sed "s#__PREFIX__#$(PREFIX)#g" assets/replay-kit.desktop.tmpl > $@

install: all
	install -m 755 build/replay-kit $(PREFIX)/bin/replay-kit
	install -m 755 build/replay-kit.desktop $(PREFIX)/share/applications/replay-kit.desktop

doc: build/doc
	python -m http.server -d build/doc

clean:
	rm -rf build/replay-kit build/gresources.c build/doc build/replay-kit.desktop

uninstall:
	rm -f $(PREFIX)/bin/replay-kit

run: clean build/replay-kit
	./build/replay-kit archives/example.wacz