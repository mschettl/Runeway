# Commits the current contents of "Wow export files" as a new commit on the orphan branch "data".
# Uses a temporary index, so the working tree and the current branch are not touched.
# Usage: scripts\update_data_branch.ps1 [-Message "..."] [-Push]
param(
    [string]$Message = "Update raw export data",
    [switch]$Push
)
$ErrorActionPreference = 'Stop'

$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) { $git = "$env:ProgramFiles\Git\cmd\git.exe" }
$root = Split-Path $PSScriptRoot -Parent
$dataDir = 'Wow export files'
$branch = 'data'

function G {
    $out = & $git -C $root @args
    if ($LASTEXITCODE) { throw "git $args failed ($LASTEXITCODE)" }
    $out
}

if (-not (Test-Path (Join-Path $root $dataDir))) { throw "Missing folder: $dataDir" }

# Base on the local branch, else on origin/data (e.g. fresh clone on another machine)
$parent = & $git -C $root rev-parse --verify -q "refs/heads/$branch"
if (-not $parent) { $parent = & $git -C $root rev-parse --verify -q "refs/remotes/origin/$branch" }

$index = Join-Path (G rev-parse --absolute-git-dir) 'data-index'
Remove-Item $index -ErrorAction SilentlyContinue
$env:GIT_INDEX_FILE = $index
try {
    # -f: the folder is ignored on main; autocrlf off: keep raw files byte-exact
    G -c core.autocrlf=false add -f -- $dataDir | Out-Null
    foreach ($f in 'README.md', '.gitattributes') {
        $sha = G hash-object -w -- "scripts/data-branch/$f"
        G update-index --add --cacheinfo "100644,$sha,$f" | Out-Null
    }
    $tree = G write-tree
} finally {
    Remove-Item Env:\GIT_INDEX_FILE
    Remove-Item $index -ErrorAction SilentlyContinue
}

if ($parent -and (G rev-parse "$parent^{tree}") -eq $tree) {
    Write-Host "No changes in '$dataDir' - nothing to commit."
} else {
    if ($parent) {
        $commit = G commit-tree $tree -p $parent -m $Message
        G update-ref "refs/heads/$branch" $commit | Out-Null
    } else {
        $commit = G commit-tree $tree -m $Message
        # zero oid = branch must not exist yet ("" is dropped by Windows PowerShell)
        G update-ref "refs/heads/$branch" $commit ('0' * 40) | Out-Null
    }
    Write-Host "Branch '$branch' -> $commit"
    G diff --shortstat $(if ($parent) { $parent } else { '4b825dc642cb6eb9a060e54bf8d69288fbee4904' }) $commit
}

if ($Push) { G push -u origin $branch }
