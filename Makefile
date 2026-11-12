# make release                  publish the next version (Claude writes the notes and picks the bump)
# make release DRY=1            notes and version only, nothing written
# make release VERSION=1.0.0    this version instead of the bump
# make release BRIEF="…"        wishes for the notes, e.g. what to leave out
.PHONY: release
release:
	@scripts/release.sh
