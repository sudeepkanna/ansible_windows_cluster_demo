# Simple helper targets
.PHONY: test awx-package

# Run the repository validator (checks required vars & inventory)
test:
	# Runs: scripts/check_required_vars.py
	python3 scripts/check_required_vars.py

# Build an AWX project package using the manifest at awx/awx_manifest.yml
awx-package:
	# Creates: build/awx_project.tar.gz (used for AWX project upload or SCM)
	./scripts/build_awx_package.sh
