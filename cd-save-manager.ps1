# ============================================================
#   Crimson Desert - Save Manager
#   Usage: irm "https://raw.githubusercontent.com/szicx/crimson-desert-save-manager/main/cd-save-manager.ps1" | iex
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$SavePath = "$env:LOCALAPPDATA\Pearl Abyss\CD\save"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Crimson Desert - Save Manager" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ─── ÉTAPE 1 : Vérification ────────────────────────────────
Write-Host "[INIT] Vérification du dossier de sauvegardes..." -ForegroundColor DarkGray

if (-not (Test-Path $SavePath)) {
    Write-Host "[INIT] Erreur : dossier introuvable : $SavePath" -ForegroundColor Red
    Write-Host "[INIT] Vous pouvez fermer cette fenêtre." -ForegroundColor DarkGray
    exit 1
}

Write-Host "[INIT] Chemin : $SavePath" -ForegroundColor DarkGray
Write-Host ""

# ─── ÉTAPE 2 : Scan ────────────────────────────────────────
Write-Host "[SCAN] Analyse des dossiers de sauvegarde..." -ForegroundColor Yellow

$folders = Get-ChildItem -Path $SavePath -Directory |
           Where-Object { $_.Name -match '^\d+$' } |
           Sort-Object LastWriteTime

if ($folders.Count -eq 0) {
    Write-Host "[SCAN] Aucun dossier de sauvegarde trouvé." -ForegroundColor Red
    Write-Host "[SCAN] Vous pouvez fermer cette fenêtre." -ForegroundColor DarkGray
    exit
}

$folderInfo = @()
$idx = 1

foreach ($folder in $folders) {
    $slots = Get-ChildItem -Path $folder.FullName -Directory -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match '^slot\d+$' }
    $saves = 0
    foreach ($slot in $slots) {
        $saves += (Get-ChildItem -Path $slot.FullName -Filter "*.save" -File -ErrorAction SilentlyContinue).Count
    }
    $folderInfo += [PSCustomObject]@{
        Index     = $idx
        Name      = $folder.Name
        Path      = $folder.FullName
        LastWrite = $folder.LastWriteTime
        HasSaves  = ($saves -gt 0)
        SaveCount = $saves
    }
    $idx++
}

Write-Host "[SCAN] $($folderInfo.Count) dossier(s) détecté(s)." -ForegroundColor Yellow
Write-Host ""

# ─── ÉTAPE 3 : Affichage ───────────────────────────────────
Write-Host "[INFO] Liste des sauvegardes disponibles :" -ForegroundColor Cyan
Write-Host ""
Write-Host ("{0,-4} {1,-15} {2,-22} {3}" -f "#", "Dossier", "Dernière modification", "Contenu")
Write-Host ("-" * 65)

foreach ($fi in $folderInfo) {
    $statut = if ($fi.HasSaves) { "$($fi.SaveCount) fichiers .save" } else { "VIDE" }
    $color  = if ($fi.HasSaves) { "Green" } else { "DarkYellow" }
    Write-Host ("{0,-4} {1,-15} {2,-22} {3}" -f $fi.Index, $fi.Name, $fi.LastWrite.ToString("dd/MM/yyyy HH:mm"), $statut) -ForegroundColor $color
}

Write-Host ""

# ─── ÉTAPE 4 : Sélection ───────────────────────────────────
$sources = $folderInfo | Where-Object { $_.HasSaves }
$empties = $folderInfo | Where-Object { -not $_.HasSaves } | Sort-Object LastWrite -Descending
$autoMode = ($sources.Count -eq 1 -and $empties.Count -ge 1)

if ($autoMode) {
    $source = $sources[0]
    $dest   = $empties[0]

    Write-Host "[SELECT] Détection automatique :" -ForegroundColor Green
    Write-Host "         Source      : $($source.Name)  ($($source.SaveCount) fichiers .save — $($source.LastWrite.ToString('dd/MM/yyyy HH:mm')))" -ForegroundColor Green
    Write-Host "         Destination : $($dest.Name)  (vide — $($dest.LastWrite.ToString('dd/MM/yyyy HH:mm')))" -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "[SELECT] Copier vers '$($dest.Name)' ? (O/N)"
    if ($confirm -notmatch '^[OoYy]') {
        Write-Host "[SELECT] Opération annulée." -ForegroundColor Yellow
        Write-Host "[SELECT] Vous pouvez fermer cette fenêtre." -ForegroundColor DarkGray
        exit
    }

} else {
    $srcInput = Read-Host "[SELECT] Sélectionnez la SOURCE (numéro)"
    $source   = $folderInfo | Where-Object { $_.Index -eq [int]$srcInput }

    $dstInput = Read-Host "[SELECT] Sélectionnez la DESTINATION (numéro)"
    $dest     = $folderInfo | Where-Object { $_.Index -eq [int]$dstInput }

    if (-not $source -or -not $dest) {
        Write-Host "[SELECT] Erreur : sélection invalide." -ForegroundColor Red
        Write-Host "[SELECT] Vous pouvez fermer cette fenêtre." -ForegroundColor DarkGray
        exit 1
    }
    if ($source.Name -eq $dest.Name) {
        Write-Host "[SELECT] Erreur : la source et la destination sont identiques." -ForegroundColor Red
        Write-Host "[SELECT] Vous pouvez fermer cette fenêtre." -ForegroundColor DarkGray
        exit 1
    }

    Write-Host ""
    $confirm = Read-Host "[SELECT] Copier '$($source.Name)' vers '$($dest.Name)' ? (O/N)"
    if ($confirm -notmatch '^[OoYy]') {
        Write-Host "[SELECT] Opération annulée." -ForegroundColor Yellow
        Write-Host "[SELECT] Vous pouvez fermer cette fenêtre." -ForegroundColor DarkGray
        exit
    }
}

Write-Host ""

# ─── ÉTAPE 5 : Copie ───────────────────────────────────────
Write-Host "[COPIE] Copie des sauvegardes en cours..." -ForegroundColor Yellow
Write-Host ""

$items   = @("slot0", "slot1", "slot2", "steam_autocloud.vdf")
$copied  = 0
$skipped = 0
$errors  = 0

foreach ($item in $items) {
    $src = Join-Path $source.Path $item
    $dst = Join-Path $dest.Path $item

    if (-not (Test-Path $src)) {
        Write-Host "[COPIE]   [SKIP]    $item  (absent dans la source)" -ForegroundColor DarkGray
        $skipped++
        continue
    }
    try {
        if ((Get-Item $src) -is [System.IO.DirectoryInfo]) {
            Copy-Item -Path $src -Destination $dst -Recurse -Force -ErrorAction Stop
        } else {
            Copy-Item -Path $src -Destination $dst -Force -ErrorAction Stop
        }
        Write-Host "[COPIE]   [OK]      $item" -ForegroundColor Green
        $copied++
    } catch {
        Write-Host "[COPIE]   [ERREUR]  $item : $_" -ForegroundColor Red
        $errors++
    }
}

Write-Host ""

# ─── ÉTAPE 6 : Résultat ────────────────────────────────────
if ($errors -eq 0) {
    Write-Host "[DONE] Terminé avec succès ! $copied élément(s) copié(s)." -ForegroundColor Green
} else {
    Write-Host "[DONE] Terminé avec $errors erreur(s). $copied élément(s) copié(s)." -ForegroundColor Yellow
}

Write-Host "[DONE] Vous pouvez fermer cette fenêtre." -ForegroundColor DarkGray
Write-Host ""
