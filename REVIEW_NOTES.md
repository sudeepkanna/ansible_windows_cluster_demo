# Review

- Existing cluster returns `changed=false` only when nodes and static IP match.
- Drift in nodes or cluster IP fails safely.
- Check mode reports creation without changing state.
- Quorum changes only when witness type/path differs.
- File share witness and no-witness modes are handled explicitly.
