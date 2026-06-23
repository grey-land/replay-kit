# webkit-rewrite.so:
# 	valac -o $@ \
# 		--library=webkit-rewrite \
# 		-X -lm -X -shared -X -fPIC \
# 		--pkg webkitgtk-web-process-extension-6.0 webkit-ext-rewrite.val

build/gresources.c: assets/sw.js assets/ui.js
	glib-compile-resources --target=$@ --generate-source gresources.xml

build/warc-view: build/gresources.c
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

clean:
	rm -f \
		build/warc-view \
		build/gresources.c

run: clean build/warc-view
	./build/warc-view archives/example.wacz


# Phony targets declaration to prevent conflicts with matching file names
# .PHONY: all clean