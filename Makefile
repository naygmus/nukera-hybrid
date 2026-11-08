# Static checks that run anywhere Python runs (no cargo/flutter needed).
# Full verification on a Linux build box: cargo check --workspace && flutter analyze
.PHONY: check

check:
	python scripts/check_static.py
