watch:
	rg --files src build.zig | entr -rc zig build test --summary all
