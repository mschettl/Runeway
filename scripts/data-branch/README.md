# Runeway – raw data branch

This branch holds only the raw wow.export output (`Wow export files/`), separate from the code on `main`.
It is updated with `scripts/update_data_branch.ps1` on `main`; do not commit code here.

## Use in a checkout of `main` (e.g. cloud processing)

```bash
git fetch origin data
git restore --source=origin/data --worktree -- "Wow export files"
```

The folder is ignored on `main`, so the working tree stays clean and the build scripts find the data at the same path as locally.

## Data only

```bash
git clone --branch data --single-branch --depth 1 https://github.com/mschettl/Runeway.git runeway-data
```
