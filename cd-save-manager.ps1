# ============================================================
#   Crimson Desert - Save Manager
#   Usage: irm "https://raw.githubusercontent.com/szicx/crimson-desert-save-manager/main/cd-save-manager.ps1" | iex
# ============================================================

$SavePath = "$env:LOCALAPPDATA\Pearl Abyss\CD\save"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Crimson Desert - Save Manager" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $SavePath)) {
    Write-Host "[ERREUR] Dossier introuvable : $SavePath" -ForegroundColor Red
    Read-Host "Appuie sur Entrée pour quitter"
    exit 1
}

# --- Scan des dossiers numeriques ---
$folders = Get-ChildItem -Path $SavePath -Directory |
           Where-Object { $_.Name -match '^\d+$' } |
           Sort-Object LastWriteTime

if ($folders.Count -eq 0) {
    Write-Host "Aucun dossier de sauvegarde trouve dans : $SavePath" -ForegroundColor Yellow
    Read-Host "Appuie sur Entree pour quitter"
    exit
}

# --- Analyse de chaque dossier ---
$folderInfo = @()
$idx = 1

foreach ($folder in $folders) {
    $slots   = Get-ChildItem -Path $folder.FullName -Directory -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -match '^slot\d+$' }
    $saves   = 0
    foreach ($slot in $slots) {
        $saves += (Get-ChildItem -Path $slot.FullName -Filter "*.save" -File -ErrorAction SilentlyContinue).Count
    }
    $hasVdf  = Test-Path (Join-Path $folder.FullName "steam_autocloud.vdf")
    $hasData = ($saves -gt 0)

    $folderInfo += [PSCustomObject]@{
        Index    = $idx
        Name     = $folder.Name
        Path     = $folder.FullName
        LastWrite= $folder.LastWriteTime
        HasSaves = $hasData
        SaveCount= $saves
        SlotCount= $slots.Count
        HasVdf   = $hasVdf
    }
    $idx++
}

# --- Affichage ---
Write-Host "Dossiers trouves dans : $SavePath" -ForegroundColor White
Write-Host ""
Write-Host ("{0,-4} {1,-15} {2,-22} {3,-10} {4}" -f "#", "Dossier", "Derniere modif.", "Sauvegardes", "Statut")
Write-Host ("-" * 70)

foreach ($fi in $folderInfo) {
    $status = if ($fi.HasSaves) { "$($fi.SaveCount) fichiers .save" } else { "VIDE" }
    $color  = if ($fi.HasSaves) { "Green" } else { "DarkYellow" }
    Write-Host ("{0,-4} {1,-15} {2,-22} {3,-10}" -f $fi.Index, $fi.Name, $fi.LastWrite.ToString("dd/MM/yyyy HH:mm"), $status) -ForegroundColor $color
}

Write-Host ""

# --- Auto-detection ---
$sources = $folderInfo | Where-Object { $_.HasSaves }
$empties = $folderInfo | Where-Object { -not $_.HasSaves } | Sort-Object LastWrite -Descending

$autoMode = ($sources.Count -eq 1 -and $empties.Count -ge 1)

if ($autoMode) {
    $source = $sources[0]
    $dest   = $empties[0]

    Write-Host "Detection automatique :" -ForegroundColor Cyan
    Write-Host "  Source      : $($source.Name)  ($($source.SaveCount) fichiers .save, modifie le $($source.LastWrite.ToString('dd/MM/yyyy HH:mm')))" -ForegroundColor Green
    Write-Host "  Destination : $($dest.Name)  (vide, cree le $($dest.LastWrite.ToString('dd/MM/yyyy HH:mm')))" -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Copier les sauvegardes de '$($source.Name)' vers '$($dest.Name)' ? (O/N)"
    if ($confirm -notmatch '^[OoYy]') {
        Write-Host "Annule." -ForegroundColor Yellow
        Read-Host "Appuie sur Entree pour quitter"
        exit
    }

} else {
    # Mode manuel si plusieurs sources ou situation ambigue
    Write-Host "Selectionne le dossier SOURCE (celui qui contient tes sauvegardes) :" -ForegroundColor Cyan
    $srcInput = Read-Host "Numero"
    $source   = $folderInfo | Where-Object { $_.Index -eq [int]$srcInput }

    Write-Host "Selectionne le dossier DESTINATION (le nouveau dossier vide) :" -ForegroundColor Cyan
    $dstInput = Read-Host "Numero"
    $dest     = $folderInfo | Where-Object { $_.Index -eq [int]$dstInput }

    if (-not $source -or -not $dest) {
        Write-Host "[ERREUR] Selection invalide." -ForegroundColor Red
        Read-Host "Appuie sur Entree pour quitter"
        exit 1
    }
    if ($source.Name -eq $dest.Name) {
        Write-Host "[ERREUR] Source et destination identiques." -ForegroundColor Red
        Read-Host "Appuie sur Entree pour quitter"
        exit 1
    }

    Write-Host ""
    $confirm = Read-Host "Copier les sauvegardes de '$($source.Name)' vers '$($dest.Name)' ? (O/N)"
    if ($confirm -notmatch '^[OoYy]') {
        Write-Host "Annule." -ForegroundColor Yellow
        Read-Host "Appuie sur Entree pour quitter"
        exit
    }
}

# --- Copie ---
Write-Host ""
Write-Host "Copie en cours..." -ForegroundColor Cyan

$items   = @("slot0", "slot1", "slot2", "steam_autocloud.vdf")
$copied  = 0
$skipped = 0
$errors  = 0

foreach ($item in $items) {
    $src = Join-Path $source.Path $item
    $dst = Join-Path $dest.Path $item

    if (-not (Test-Path $src)) {
        Write-Host "  [SKIP]   $item  (introuvable dans la source)" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    try {
        if ((Get-Item $src) -is [System.IO.DirectoryInfo]) {
            Copy-Item -Path $src -Destination $dst -Recurse -Force -ErrorAction Stop
        } else {
            Copy-Item -Path $src -Destination $dst -Force -ErrorAction Stop
        }
        Write-Host "  [OK]     $item" -ForegroundColor Green
        $copied++
    } catch {
        Write-Host "  [ERREUR] $item : $_" -ForegroundColor Red
        $errors++
    }
}

Write-Host ""
if ($errors -eq 0) {
    Write-Host "Termine ! $copied element(s) copie(s) avec succes." -ForegroundColor Green
} else {
    Write-Host "Termine avec $errors erreur(s). $copied element(s) copie(s)." -ForegroundColor Yellow
}
Write-Host ""
Read-Host "Appuie sur Entree pour quitter"
