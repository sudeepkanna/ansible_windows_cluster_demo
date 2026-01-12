AWX / Tower packaging and sync

Purpose:
- This folder describes which files should be included when you publish a project to AWX/Tower.
- Use `awx/awx_manifest.yml` to mark the files/folders that should be included in the AWX project package.

How to mark files for AWX:
- If you add or update playbooks, roles, inventory, plugins, or modules that should be included in the AWX project, update `awx/awx_manifest.yml` with the relative path.
- Open your PR including both the file changes and the manifest update so reviewers can see what will be deployed to AWX.

Packaging:
- You can produce a tarball suitable for AWX SCM or manual upload using the helper script:

  ./scripts/build_awx_package.sh

- Or run via Make: `make awx-package`

The produced artifact is `build/awx_project.tar.gz`.

Notes:
- We keep a separate manifest + packaging step instead of renaming source folders. This avoids duplicating or renaming code while making it explicit what goes to AWX.
- If you'd prefer folder suffixes like `-AWX` to visually mark content for PRs, we can add that convention — say the team prefers `playbooks-AWX` — and I can apply that change instead.
