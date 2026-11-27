# Guía didáctica — Autoinstalador Linux → Windows

Aprende a usar el instalador paso a paso, desde cero y sin conocimientos previos de
PowerShell.

## Objetivos

Al terminar sabrás:

1. Interpretar el inventario de aplicaciones de Linux y sus equivalencias en Windows.
2. Comprobar el tamaño y el espacio libre de cada partición.
3. Ejecutar el instalador en modo seguro (simulación) antes de instalar de verdad.
4. Instalar, filtrar y excluir aplicaciones.
5. Leer el informe y solucionar fallos habituales.

---

## Paso 1. Preparar el equipo

1. Copia esta carpeta a tu equipo Windows (por ejemplo a `C:\Autoinstall`).
2. Abre **PowerShell** desde el menú Inicio (no hace falta "Como administrador").
3. Comprueba la versión:

   ```powershell
   $PSVersionTable.PSVersion
   ```

   Necesitas 5.1 o superior (la que trae Windows 10/11). Si tienes PowerShell 7 (`pwsh`), también sirve.

4. Comprueba los gestores de paquetes:

   ```powershell
   winget --version
   choco --version
   scoop --version
   ```

   Con que funcione **uno** es suficiente. Si no está winget, instala
   *App Installer* desde Microsoft Store.

### Ejercicio 1

Anota qué gestores tienes disponibles. El instalador usará winget primero, luego
Chocolatey y por último Scoop.

---

## Paso 2. Entender el catálogo

Abre `app-catalog.json` con el Bloc de notas. Verás entradas como:

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

| Campo | Qué significa |
|---|---|
| `origin` | De dónde venía en Linux (APT, Snap o Flatpak). |
| `windowsName` | Nombre del equivalente en Windows. |
| `action` | `install` se instala; `native` ya está en Windows; `skip` no aplica; `manual` necesita tus manos. |
| `sizeMB` | Espacio estimado **una vez instalado**, en megabytes. |
| `winget`/`choco`/`scoop` | Identificador en cada gestor. `null` significa que no hay paquete. |

### ¿Por qué hay aplicaciones que no se instalan?

Porque en Windows no existen o no tienen sentido:

- **Wine / Bottles / Protontricks** sirven para ejecutar programas de Windows dentro
  de Linux. En Windows esos programas se instalan directamente.
- **Flatpak, Flatseal, Warehouse** son gestores de Linux.
- **GParted, Timeshift, Seahorse** tienen función nativa en Windows: *Administrar
  discos*, *Restaurar sistema* e *Historial de archivos*, y *Administrador de
  credenciales*.
- **GNOME Web o Midori** se sustituyen por Edge/Firefox.

### Ejercicio 2

Busca en el catálogo la entrada `kdenlive` y comprueba que sus tres identificadores
existen. Después busca `wine` y lee por qué no se instala.

---

## Paso 3. Ver el disco antes de instalar

Ejecuta:

```powershell
cd C:\Autoinstall
.\Install-Apps.ps1 -ListOnly
```

Verás una tabla con todas las aplicaciones. Después:

```powershell
.\Install-Apps.ps1 -DryRun
```

La primera tabla muestra las **particiones y unidades**:

```
Unidad  Etiqueta  Sist.arch  Tamano GB  Libres GB  Usados GB  Partic.
C:      Sistema   NTFS             500        120        380        1
D:      Datos     NTFS            1000        700        300        2
```

- **Tamano GB**: capacidad total de la partición.
- **Libres GB**: espacio disponible.
- **Partic.**: número de particiones de esa unidad.

A continuación aparece:

```
[INFO] Unidad seleccionada: C: (500 GB totales, 120 GB libres)
[INFO] Espacio estimado a instalar: 24,5 GB | Reserva: 10 GB | Utilizable: 110 GB
```

El instalador **no instalará nada** en `-DryRun`. Es obligatorio recomendarlo antes
de la instalación real.

### Ejercicio 3

Ejecuta `.\Install-Apps.ps1 -DryRun -Drive D: -ReserveGB 20` y compara el resultado.
Cambia `D:` por una unidad que exista en tu equipo.

---

## Paso 4. Instalar de forma segura

Cuando el plan te convenza:

```powershell
.\Install-Apps.ps1 -Yes -ReportPath .\informe.json
```

- `-Yes` evita preguntas. Si no caben todas las aplicaciones, omite **las más
  grandes** y lo avisa.
- `-ReportPath` crea `informe.json` y `informe.log`.

Si no usas `-Yes` y falta espacio, verás este menú:

```
1) Omitir automaticamente las aplicaciones mas grandes
2) Continuar de todos modos
3) Abortar
```

**Recomendación:** elige `1`. Elegir `2` solo si aceptas el riesgo de quedarte sin
espacio. `--SkipSpaceCheck` equivale a elegir `2` sin preguntar.

### Instalar solo un grupo

```powershell
.\Install-Apps.ps1 -Category Navegacion,Comunicacion -Yes
```

### Excluir aplicaciones

```powershell
.\Install-Apps.ps1 -ExcludeId winrar,docker-desktop,powertoys -Yes
```

### Forzar reinstalación

```powershell
.\Install-Apps.ps1 -Force -ExcludeId edge -Yes
```

---

## Paso 5. Leer el informe

Abre `informe.json`. La sección `summary` dice cuántas aplicaciones están en cada
estado:

```json
"summary": {
  "already-installed": 21,
  "failed": 1,
  "installed": 64,
  "native": 9,
  "no-manager": 0,
  "skip": 14
}
```

Estados posibles:

| Estado | Significado |
|---|---|
| `installed` | Instalada correctamente con el gestor indicado. |
| `already-installed` | Ya estaba; no se tocó. |
| `failed` | Falló en todos los gestores disponibles. Mira `informe.log`. |
| `skipped-space` | Se omitió por falta de espacio. |
| `no-manager` | No hay paquete en los gestores instalados. |
| `native` / `skip` / `manual` | No requiere instalación automática. |

Los registros de salida de cada instalación están en la carpeta que indica
`logDir` dentro del informe.

---

## Paso 6. Solución de problemas

| Síntoma | Causa | Solución |
|---|---|---|
| `No hay ningun gestor de paquetes` | No hay winget/choco/scoop. | Instala App Installer desde Microsoft Store. |
| `El gestor X no esta instalado` | Usaste `-Manager` con un gestor ausente. | Usa `auto` o instala ese gestor. |
| `La unidad Z no existe` | La letra cambió. | Ejecuta sin `-Drive` o usa una letra de la tabla. |
| Muchos `failed` | Sin Internet, firewall o cabeceras TLS. | Comprueba `ping winget.com` y vuelve a ejecutar. |
| `Fallo al ejecutar` en Chocolatey | Falta administrador. | Abre PowerShell como administrador. |
| Se omiten demasiadas apps | Reserva muy alta. | Baja `-ReserveGB` o usa otra unidad con `-Drive`. |

---

## Glosario

- **Partición**: división lógica de un disco que se monta como una unidad (C:, D:).
- **Volumen**: unidad visible desde el Explorador de archivos.
- **GB**: 1024 MB. El script usa decimal para los informes (`1 GB = 1024 MB` de catálogo).
- **winget**: gestor oficial de Microsoft (`winget install --id ...`).
- **Chocolatey / Scoop**: gestores de terceros; Scoop instala en el perfil de usuario.
- **Dry run**: simulación que no modifica el equipo.
- **Mirror**: copia automática de un repositorio en otra plataforma.

## Siguiente paso

Lee [MIRROR.md](MIRROR.md) para entender la sincronización GitHub ↔ GitLab y cómo
comprobar que funciona.
