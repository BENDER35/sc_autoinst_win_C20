# Autoinstalador de aplicaciones (Linux → Windows)

Instalador automático para **Windows 10/11** que reproduce, con equivalentes nativos,
el software instalado en un equipo Ubuntu 26.04.1. Antes de instalar, inspecciona las
particiones, calcula cuántos GB caben y descarta lo que no cabe.

**Idiomas:** [Español](docs/GUIA-DIDACTICA-ES.md) · [English](docs/GUIDE-EN.md) · [Asturianu](docs/GUIDA-DIDACTICA-AST.md)

---

## Qué hace

1. **Inventario.** Lee `app-catalog.json` (113 entradas: 89 instalables, 9 funciones
   nativas de Windows, 14 sin equivalente, 1 instalación manual).
2. **Disco.** Enumera volúmenes fijos con `Win32_LogicalDisk`, muestra tamaño, libre,
   usado y número de particiones (`Get-Partition`), y selecciona la unidad indicada
   con `-Drive` (o la de más espacio si no existe).
3. **Comprobación de espacio.** Suma el tamaño instalado estimado de lo que falta por
   instalar, descuenta la reserva (`-ReserveGB`, 10 por defecto) y avisa/omite lo que
   no cabe.
4. **Detección de ya instalados.** Cruza `winget export`, el registro de
   `Desinstalar` y ejecutables conocidos para no reinstalar.
5. **Instalación.** Prueba `winget` → `choco` → `scoop` por este orden y pasa al
   siguiente gestor si falla. Todo queda registrado en un informe JSON y un log.

## Requisitos

- Windows 10/11 con PowerShell 5.1 o superior (funciona también en PowerShell 7).
- Conexión a Internet.
- Al menos uno de: **winget** (App Installer), **Chocolatey** o **Scoop**.
- No se necesitan permisos de administrador para el modo usuario de winget/Scoop;
  Chocolatey y algunos paquetes sí los piden.

## Uso rápido

PowerShell como usuario normal:

```powershell
# 1. Ver el catálogo completo
.\Install-Apps.ps1 -ListOnly

# 2. Ver el plan y el cálculo de disco sin instalar nada
.\Install-Apps.ps1 -DryRun

# 3. Instalar en C: con reserva de 10 GB y guardar informe
.\Install-Apps.ps1 -Yes -ReportPath .\informe.json
```

Otras opciones útiles:

```powershell
# Instalar solo navegadores y multimedia en D:
.\Install-Apps.ps1 -Drive D: -Category Navegacion,Multimedia -Yes

# Forzar reinstalación, excluir dos aplicaciones y usar solo Scoop
.\Install-Apps.ps1 -Force -ExcludeId winrar,edge -Manager scoop

# No comprobar espacio (peligroso) y simular
.\Install-Apps.ps1 -DryRun -SkipSpaceCheck
```

### Parámetros

| Parámetro | Descripción |
|---|---|
| `-CatalogPath` | Ruta al JSON. Por defecto `app-catalog.json` junto al script. |
| `-Drive` | Unidad a verificar, p. ej. `C:`. Si no existe, se elige la de más espacio libre. |
| `-Manager` | `auto` (por defecto), `winget`, `choco` o `scoop`. |
| `-Category` | Filtro por categoría, se puede repetir. |
| `-ExcludeId` | IDs que se omiten. |
| `-ListOnly` | Muestra el catálogo y termina. |
| `-DryRun` | Muestra particiones, plan y espacio; no instala. |
| `-Force` | Vuelve a instalar lo detectado como instalado. |
| `-Yes` | Responde automáticamente; si no caben todas, omite las más grandes. |
| `-SkipSpaceCheck` | Ignora la comprobación de espacio. |
| `-ReserveGB` | GB reservados para el sistema (por defecto 10). |
| `-ReportPath` | Escribe `<nombre>.json` (informe) y `<nombre>.log` (traza). |

## Formato del catálogo

Cada entrada tiene:

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
  "scoop": "firefox",
  "notes": "Equivalente directo."
}
```

- `action`: `install` (se instala), `native` (Windows ya lo incluye), `manual`
  (requiere intervención), `skip` (no tiene sentido en Windows o se sustituye).
- `sizeMB`: espacio **instalado** estimado, no tamaño del descargable.
- Los IDs de gestores pueden ser `null`; el script prueba los disponibles en orden.

### Equivalencias destacadas

| Linux | Windows | Observación |
|---|---|---|
| Wine, Bottles, Protontricks | No necesario | Los programas se instalan de forma nativa. |
| Flatpak, Flatseal, Warehouse | No necesario | Gestores propios de Linux. |
| GParted, `fdisk`, `parted` | Administrar discos / Diskpart | Nativo. |
| Timeshift | Restaurar sistema + Historial de archivos | Nativo. |
| Kdenlive, Shotcut, OpenShot | Iguales | Existen en winget/choco/scoop. |
| Kazam, vokoscreenNG | OBS Studio | Mismo propósito. |
| Okular, xpdf, PDF Mix Tool | Sumatra PDF / PDF24 | Equivalentes funcionales. |
| QEMU, Virt-Manager, GNOME Boxes | Oracle VirtualBox | Virtualización de escritorio. |
| RetroArch, Dolphin, PPSSPP | Iguales | Disponibles en Windows. |
| GNOME Web, Midori | Microsoft Edge / Firefox | Sustitución funcional. |

## Informe y código de salida

Con `-ReportPath informe.json` se generan `informe.json` y `informe.log`. El JSON
incluye disco, reserva, gestores, resumen por estado y detalle por aplicación.
El script devuelve `0` si no hay fallos y `2` si alguna instalación falló.

## Limitaciones

- Los tamaños son estimaciones: el consumo real depende de versiones y cachés.
- Algunos IDs de gestores cambian con el tiempo; si falla uno, el script prueba el
  siguiente y deja constancia en el log.
- Packet Tracer necesita cuenta de Cisco; no se puede automatizar.
- No se instalan controladores ni actualizaciones de Windows.
- El mirror bidireccional se documenta en [docs/MIRROR.md](docs/MIRROR.md).

## Espejos y release

- GitHub: `https://github.com/BENDER35/sc_autoinst_win_C20`
- GitLab: `https://gitlab.com/BENDER_5000/sc_autoinst_win_C20`
- Sincronización automática bidireccional (`main`) con marcador `[skip mirror]`
  para evitar bucles. Detalles y comprobación: [docs/MIRROR.md](docs/MIRROR.md).
- Release `v1.0.0`: zip con script, catálogo y documentación.

## Licencia

MIT. Ver [LICENSE](LICENSE).
