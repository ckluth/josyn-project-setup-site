#!/usr/bin/env pwsh
# Deterministic regenerator for `overview.md` (decision-trail, ADR-0040).
#
# This script is an OPTIONAL companion. The normative refresh procedure is the
# prose spec in `working-method.md` / `AGENTS.md`; this script is a faithful
# implementation of it — same five derived views, same ordering. It is
# instruction-triggered: the agent runs it if present, otherwise regenerates the
# prose way. Only the *output* (`overview.md`) is contract, not this script, so an
# adopter may replace it with an equivalent in any language.
#
# It refuses to emit a drifted index: on any non-conformant header (bare/bullet-less
# block per ADR-0026, or a title-line ordinal disagreeing with the filename slot per
# ADR-0028) it FLAGS the problem and aborts without writing, rather than dropping or
# misfiling a row.
#
# Usage:  pwsh ./regen-overview.ps1 [-Root <dir>]
#   -Root  the directory that contains ideas/ decisions/ plans/ (auto-detected by
#          walking up from the script location if omitted).

[CmdletBinding()]
param(
    [string]$Root
)

$ErrorActionPreference = 'Stop'

function Find-Root {
    param([string]$Start)
    $dir = (Resolve-Path $Start).ToString()
    while ($null -ne $dir) {
        $ok = (Test-Path (Join-Path $dir 'ideas')) -and
              (Test-Path (Join-Path $dir 'decisions')) -and
              (Test-Path (Join-Path $dir 'plans'))
        if ($ok) { return $dir }
        $parent = Split-Path $dir -Parent
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

if ([string]::IsNullOrEmpty($Root)) {
    $Root = Find-Root -Start $PSScriptRoot
    if ($null -eq $Root) { $Root = Find-Root -Start (Get-Location).Path }
}
if ($null -eq $Root -or -not (Test-Path (Join-Path $Root 'ideas'))) {
    Write-Error "Could not locate a decision-trail root (a dir containing ideas/ decisions/ plans/). Pass -Root."
    exit 2
}
$Root = (Resolve-Path $Root).ToString()

# --- header parsing -------------------------------------------------------------

$families = @(
    @{ Folder = 'ideas';     Kind = 'idea'; TitleRegex = '^#\s+Idea\s+0*(\d+):\s*(.*\S)\s*$' }
    @{ Folder = 'decisions'; Kind = 'adr';  TitleRegex = '^#\s+ADR-0*(\d+):\s*(.*\S)\s*$' }
    @{ Folder = 'plans';     Kind = 'plan'; TitleRegex = '^#\s+Plan\s+0*(\d+):\s*(.*\S)\s*$' }
)

$problems = New-Object System.Collections.Generic.List[string]

function Parse-Artifact {
    param($File, $TitleRegex, $Folder)

    $lines = Get-Content -LiteralPath $File.FullName
    $rel = "$Folder/$($File.Name)"

    # filename ordinal
    if ($File.Name -notmatch '^0*(\d+)-') {
        $script:problems.Add("[$rel] filename has no leading NNNN- ordinal")
        return $null
    }
    $fileNum = [int]$Matches[1]

    $titleNum = $null; $title = $null
    $date = $null; $status = $null; $tags = $null; $implements = $null
    foreach ($ln in $lines) {
        if ($null -eq $title -and $ln -match $TitleRegex) {
            $titleNum = [int]$Matches[1]; $title = $Matches[2].Trim()
        }
        elseif ($null -eq $date       -and $ln -match '^-\s*Date:\s*(.+?)\s*$')          { $date = $Matches[1].Trim() }
        elseif ($null -eq $status     -and $ln -match '^-\s*Status:\s*(\S+)')            { $status = $Matches[1].Trim() }
        elseif ($null -eq $tags       -and $ln -match '^-\s*Tags:\s*(.+?)\s*$')          { $tags = $Matches[1].Trim() }
        elseif ($null -eq $implements -and $ln -match '^-\s*Implements:.*?ADR-0*(\d+)')  { $implements = [int]$Matches[1] }
    }

    if ($null -eq $title)  { $script:problems.Add("[$rel] no conformant title line (expected '$TitleRegex')") ; return $null }
    if ($titleNum -ne $fileNum) { $script:problems.Add("[$rel] title-line ordinal $titleNum != filename ordinal $fileNum (ADR-0028)") }
    if ($null -eq $date)   { $script:problems.Add("[$rel] missing bulleted '- Date:' header (ADR-0026)") }
    if ($null -eq $status) { $script:problems.Add("[$rel] missing bulleted '- Status:' header (ADR-0026)") }

    [pscustomobject]@{
        Num = $fileNum; Title = $title; Rel = $rel
        Date = $date; Status = $status; Tags = $tags; Implements = $implements
    }
}

$data = @{}
foreach ($fam in $families) {
    $folderPath = Join-Path $Root $fam.Folder
    $items = New-Object System.Collections.Generic.List[object]
    Get-ChildItem -LiteralPath $folderPath -Filter '*.md' -File |
        Sort-Object Name |
        ForEach-Object {
            $a = Parse-Artifact -File $_ -TitleRegex $fam.TitleRegex -Folder $fam.Folder
            if ($null -ne $a) { $items.Add($a) }
        }
    $data[$fam.Kind] = @($items | Sort-Object Num)
}

if ($problems.Count -gt 0) {
    Write-Host "overview regen ABORTED — $($problems.Count) non-conformant header(s) found:" -ForegroundColor Red
    foreach ($p in $problems) { Write-Host "  - $p" -ForegroundColor Red }
    Write-Host "Fix the headers above (see ADR-0026 / ADR-0028), then re-run." -ForegroundColor Red
    exit 1
}

# --- rendering ------------------------------------------------------------------

$today = Get-Date -Format 'yyyy-MM-dd'
$nl = "`n"
$sb = New-Object System.Text.StringBuilder

function Add-Line { param([string]$s = '') [void]$sb.Append($s); [void]$sb.Append($nl) }

Add-Line '# Overview'
Add-Line ''
Add-Line 'A derived status index over all ideas, decisions, and plans — a plain'
Add-Line '*to-do / what''s-done* list. It is **regenerated wholesale from the artifact'
Add-Line 'headers** (never hand-patched) and stamped with the moment it was true. The'
Add-Line 'artifacts themselves are the source of truth; this file is a convenience'
Add-Line 'snapshot. Keeping it current is the agent''s responsibility (see the working'
Add-Line 'method).'
Add-Line ''
Add-Line 'You can ask the agent to **regenerate the overview** at any time.'
Add-Line ''
Add-Line "**As of: $today**"

function Add-FamilyTable {
    param([string]$Heading, $Items)
    Add-Line ''
    Add-Line "## $Heading"
    Add-Line ''
    Add-Line '| Name | Created | State | Tags |'
    Add-Line '|------|---------|-------|------|'
    foreach ($a in $Items) {
        $num = '{0:D4}' -f $a.Num
        $tags = if ($null -eq $a.Tags) { '' } else { $a.Tags }
        Add-Line "| [$num $($a.Title)]($($a.Rel)) | $($a.Date) | $($a.Status) | $tags |"
    }
}

Add-FamilyTable -Heading 'Ideas'     -Items $data['idea']
Add-FamilyTable -Heading 'Decisions' -Items $data['adr']
Add-FamilyTable -Heading 'Plans'     -Items $data['plan']

# ADR -> plans sub-index
$adrByNum = @{}
foreach ($a in $data['adr']) { $adrByNum[$a.Num] = $a }

$plansByAdr = @{}
foreach ($p in $data['plan']) {
    if ($null -ne $p.Implements) {
        if (-not $plansByAdr.ContainsKey($p.Implements)) {
            $plansByAdr[$p.Implements] = New-Object System.Collections.Generic.List[object]
        }
        $plansByAdr[$p.Implements].Add($p)
    }
}

Add-Line ''
Add-Line '## Implements (ADR → plans)'
Add-Line ''
Add-Line '| ADR | Plan | Status |'
Add-Line '|-----|------|--------|'
foreach ($adrNum in ($plansByAdr.Keys | Sort-Object)) {
    $adr = $adrByNum[$adrNum]
    $adrNumStr = '{0:D4}' -f $adrNum
    $adrCell = if ($null -eq $adr) {
        "ADR-$adrNumStr (missing)"
    } else {
        "[ADR-$adrNumStr – $($adr.Title)]($($adr.Rel))"
    }
    foreach ($p in ($plansByAdr[$adrNum] | Sort-Object Num)) {
        $planNumStr = '{0:D4}' -f $p.Num
        Add-Line "| $adrCell | [Plan $planNumStr]($($p.Rel)) | $($p.Status) |"
    }
}

# ADR — stand-alone decision (accepted ADRs no plan implements)
Add-Line ''
Add-Line '## ADR — stand-alone decision'
Add-Line ''
Add-Line 'Accepted ADRs that no plan carries out via `Implements:` — decisions that stand on'
Add-Line 'their own and need no execution. Worth a quick check now and then: if a decision'
Add-Line 'here accidentally has no plan but actually does need one, write its `draft` stub so'
Add-Line 'it is not forgotten.'
Add-Line ''
Add-Line '| ADR | Accepted |'
Add-Line '|-----|----------|'
foreach ($a in $data['adr']) {
    if ($a.Status -eq 'accepted' -and -not $plansByAdr.ContainsKey($a.Num)) {
        $adrNumStr = '{0:D4}' -f $a.Num
        Add-Line "| [ADR-$adrNumStr – $($a.Title)]($($a.Rel)) | $($a.Date) |"
    }
}

# --- write (UTF-8, no BOM, LF) --------------------------------------------------
$outPath = Join-Path $Root 'overview.md'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($outPath, $sb.ToString(), $utf8NoBom)
Write-Host "overview regenerated: $outPath (as of $today)" -ForegroundColor Green
