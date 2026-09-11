.PHONY: build app run stop logs probe install clean

build:
	swift build

app:
	scripts/build-app.sh release

run: app
	-pkill -x LyricBar || true
	open build/LyricBar.app

stop:
	-pkill -x LyricBar || true

logs:
	tail -n 50 -f ~/Library/Logs/LyricBar/lyricbar.log

# make probe TITLE="Song" ARTIST="Artist" DURATION=208
probe: build
	.build/debug/LyricBar --probe "$(TITLE)" "$(ARTIST)" "$(DURATION)"

install: app
	-pkill -x LyricBar || true
	rm -rf /Applications/LyricBar.app
	cp -R build/LyricBar.app /Applications/LyricBar.app
	open /Applications/LyricBar.app

clean:
	rm -rf .build build
