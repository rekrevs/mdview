.PHONY: build bundle install clean

build:
	swift build

bundle: build
	./bundle.sh

install: bundle
	@mkdir -p ~/Applications
	@rm -rf ~/Applications/mdview.app
	cp -r mdview.app ~/Applications/
	@echo "Installed to ~/Applications/mdview.app"
	@echo ""
	@echo "To set as default for .md files:"
	@echo "  1. Right-click any .md file in Finder"
	@echo "  2. Get Info (⌘I)"
	@echo "  3. Under 'Open with', select mdview"
	@echo "  4. Click 'Change All...'"

clean:
	swift package clean
	rm -rf mdview.app
