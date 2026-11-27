# Step-by-step guide — Linux to Windows auto-installer

Learn how to use the installer from scratch, even if you have never used PowerShell.

## Learning goals

By the end you will be able to:

1. Read the Linux application inventory and its Windows equivalents.
2. Check partition size and free space before installing anything.
3. Run a safe simulation (`-DryRun`).
4. Install, filter and exclude applications.
5. Read the report and fix the most common failures.

---

## Step 1. Prepare the machine

1. Copy this folder to your Windows computer, for example to `C:\Autoinstall`.
2. Open **PowerShell** from the Start menu (administrator rights are not required).
3. Check the version:

   ```powershell
   $PSVersionTable.PSVersion
   ```

   You need 5.1 or newer (shipped with Windows 10/11). PowerShell 7 (`pwsh`) works too.

4. Check the package managers:

   ```powershell
   winget --version
   choco --version
   scoop --version
   ```

   Only **one** is required. If winget is missing, install *App Installer* from the
   Microsoft Store.

### Exercise 1

Write down which managers you have. The script tries winget first, then Chocolatey,
then Scoop.

---

## Step 2. Understand the catalog

Open `app-catalog.json` in Notepad. An entry looks like this:

```json
{
  "id": "firefox",
  "name": "Mozilla Firefox",
  "origin": "Snap: firefox",
  "windowsName": "Mozilla Firefox",
  "category": "Navegacion",
  "action": "install",
  "sizeMB": 300,
  "winget": "Mozilla.Firefox",
  "choco": "firefox",
  "scoop": "firefox"
}
```

| Field | Meaning |
|---|---|
| `origin` | Where it came from on Linux (APT, Snap or Flatpak). |
| `windowsName` | Name of the Windows equivalent. |
| `action` | `install`, `native` (already in Windows), `skip` (not applicable) or `manual`. |
| `sizeMB` | Estimated **installed** size in megabytes. |
| `winget`/`choco`/`scoop` | Package ID per manager. `null` means unavailable. |

### Why some applications are not installed

- **Wine, Bottles, Protontricks** run Windows programs inside Linux. On Windows the
  programs install natively.
- **Flatpak, Flatseal, Warehouse** are Linux-only package tools.
- **GParted, Timeshift, Seahorse** have native Windows counterparts: *Disk
  Management*, *System Restore* + *File History*, and *Credential Manager*.
- **GNOME Web / Midori** are replaced by Edge or Firefox.

### Exercise 2

Find `kdenlive` in the catalog and check that it has three package IDs. Then find
`wine` and read why it is skipped.

---

## Step 3. Inspect the disk first

Run:

```powershell
cd C:\Autoinstall
.\Install-Apps.ps1 -ListOnly
```

You get the full catalog. Then run:

```powershell
.\Install-Apps.ps1 -DryRun
```

The first table lists **partitions and volumes**:

```
Unidad  Etiqueta  Sist.arch  Tamano GB  Libres GB  Usados GB  Partic.
C:      Sistema   NTFS             500        120        380        1
D:      Datos     NTFS            1000        700        300        2
```

- **Tamano GB**: total capacity of the volume.
- **Libres GB**: free space.
- **Partic.**: number of partitions on that drive.

Then you will see:

```
[INFO] Unidad seleccionada: C: (500 GB totales, 120 GB libres)
[INFO] Espacio estimado a instalar: 24,5 GB | Reserva: 10 GB | Utilizable: 110 GB
```

`-DryRun` **does not install anything**. Always run it first.

### Exercise 3

Run `.\Install-Apps.ps1 -DryRun -Drive D: -ReserveGB 20` and compare the result.
Replace `D:` with a drive that exists on your PC.

---

## Step 4. Install safely

When the plan looks right:

```powershell
.\Install-Apps.ps1 -Yes -ReportPath .\report.json
```

- `-Yes` disables prompts. If everything does not fit, the **largest** applications
  are skipped with a warning.
- `-ReportPath` creates `report.json` and `report.log`.

Without `-Yes`, if space is insufficient you get:

```
1) Omitir automaticamente las aplicaciones mas grandes
2) Continuar de todos modos
3) Abortar
```

**Recommended:** choose `1`. Choose `2` only if you accept the risk of running out
of space. `-SkipSpaceCheck` is the non-interactive equivalent of option 2.

### Install one group only

```powershell
.\Install-Apps.ps1 -Category Navegacion,Comunicacion -Yes
```

### Exclude applications

```powershell
.\Install-Apps.ps1 -ExcludeId winrar,docker-desktop,powertoys -Yes
```

### Force reinstallation

```powershell
.\Install-Apps.ps1 -Force -ExcludeId edge -Yes
```

---

## Step 5. Read the report

Open `report.json`. The `summary` section counts each status:

```json
"summary": {
  "already-installed": 21,
  "failed": 1,
  "installed": 64,
  "native": 9,
  "skip": 14
}
```

| Status | Meaning |
|---|---|
| `installed` | Installed successfully with the shown manager. |
| `already-installed` | Already present; left untouched. |
| `failed` | Failed with every available manager. Check `report.log`. |
| `skipped-space` | Skipped because of insufficient space. |
| `no-manager` | No package available in the installed managers. |
| `native` / `skip` / `manual` | No automatic installation needed. |

Per-installer stdout/stderr is stored in the folder given by `logDir` in the report.

---

## Step 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `No hay ningun gestor de paquetes` | No manager installed. | Install App Installer from Microsoft Store. |
| `El gestor X no esta instalado` | `-Manager` names a missing manager. | Use `auto` or install that manager. |
| `La unidad Z no existe` | Drive letter changed. | Omit `-Drive` or use a letter from the table. |
| Many `failed` entries | No Internet, firewall or TLS issues. | Check `ping winget.com` and retry. |
| Chocolatey `Fallo al ejecutar` | Elevation needed. | Open PowerShell as administrator. |
| Too many apps skipped | Reserve too high. | Lower `-ReserveGB` or pick another `-Drive`. |

---

## Glossary

- **Partition**: a logical slice of a disk exposed as a drive letter (C:, D:).
- **Volume**: the drive you see in File Explorer.
- **GB**: the script stores catalog sizes in MB and reports in GB (1024 MB = 1 GB).
- **winget**: Microsoft's official package manager.
- **Chocolatey / Scoop**: third-party managers; Scoop installs into your user profile.
- **Dry run**: a simulation that changes nothing.
- **Mirror**: an automatic copy of a repository on another platform.

## Next step

Read [MIRROR.md](MIRROR.md) to understand the GitHub ↔ GitLab synchronization and
how to verify it.
