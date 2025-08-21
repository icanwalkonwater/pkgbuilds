.PHONY: all
all:
	makepkg --geninteg >> PKGBUILD
	makepkg --verifysource
	makepkg --printsrcinfo > .SRCINFO
