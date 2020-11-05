all: release

release:
	git add -A
	@echo "Commit message: "; read MSG; git commit -am "$$MSG"
	standard-version
	git push --follow-tags origin main