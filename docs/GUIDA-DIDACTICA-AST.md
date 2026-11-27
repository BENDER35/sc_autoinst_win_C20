# Guía didáctica — Autoinstalador de Linux a Windows

Apriende a usar l'instalador pasu a pasu, dende cero y ensin saber PowerShell.

## Oxetivos

Al acabar vas saber:

1. Entender l'inventariu d'aplicaciones de Linux y los sos equivalentes en Windows.
2. Comprobar el tamañu y l'espaciu llibre de cada partición.
3. Executar l'instalador en manera segura (simulación) enantes d'instalar de verdá.
4. Instalar, filtrar y escluyir aplicaciones.
5. Lleer l'informe y arreglar los fallos más comunes.

---

## Pasu 1. Preparar l'equipu

1. Copia esta carpeta al tu equipu Windows, por exemplu a `C:\Autoinstall`.
2. Abre **PowerShell** dende'l menú Entamu (nun fai falta "Como alministrador").
3. Comprueba la versión:

   ```powershell
   $PSVersionTable.PSVersion
   ```

   Precises la 5.1 o superior (la que trae Windows 10/11). Tamién sirve PowerShell 7 (`pwsh`).

4. Comprueba los xestores de paquetes:

   ```powershell
   winget --version
   choco --version
   scoop --version
   ```

   Con que funcione **unu** basta. Si nun ta winget, instala *App Installer* dende
   Microsoft Store.

### Exerciciu 1

Anota qué xestores tienes. L'instalador prueba winget primeru, depués Chocolatey
y a la fin Scoop.

---

## Pasu 2. Entender el catálogu

Abre `app-catalog.json` col Bloc de notes. Verás entraes como esta:

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

| Campu | Qué significa |
|---|---|
| `origin` | Dónde venía en Linux (APT, Snap o Flatpak). |
| `windowsName` | El nome del equivalente en Windows. |
| `action` | `install` s'instala; `native` yá ta en Windows; `skip` nun s'aplica; `manual` precisa les tos manes. |
| `sizeMB` | Espaciu estimao **yá instalao**, en megabytes. |
| `winget`/`choco`/`scoop` | Identificador en cada xestor. `null` = nun hai paquete. |

### ¿Por qué hai aplicaciones que nun s'instalen?

- **Wine / Bottles / Protontricks** sirven pa executar programes de Windows dentro
  de Linux. En Windows esos programes s'instalen directamente.
- **Flatpak, Flatseal, Warehouse** son xestores propios de Linux.
- **GParted, Timeshift, Seahorse** tienen función nativa en Windows: *Alministrar
  discos*, *Restaurar sistema* + *Historial de ficheros* y *Alministrador de
  credenciales*.
- **GNOME Web o Midori** sustitúyense por Edge/Firefox.

### Exerciciu 2

Busca nel catálogu la entrada `kdenlive` y comprueba que tien los tres
identificadores. Depués busca `wine` y llee por qué nun s'instala.

---

## Pasu 3. Mirar el discu enantes d'instalar

Executa:

```powershell
cd C:\Autoinstall
.\Install-Apps.ps1 -ListOnly
```

Verás una tabla con toles aplicaciones. Depués:

```powershell
.\Install-Apps.ps1 -DryRun
```

La primer tabla amuesa les **particiones y unidaes**:

```
Unidad  Etiqueta  Sist.arch  Tamano GB  Libres GB  Usados GB  Partic.
C:      Sistema   NTFS             500        120        380        1
D:      Datos     NTFS            1000        700        300        2
```

- **Tamano GB**: capacidá total de la partición.
- **Libres GB**: espaciu disponible.
- **Partic.**: númberu de particiones d'esa unidá.

Depués apaez:

```
[INFO] Unidad seleccionada: C: (500 GB totales, 120 GB libres)
[INFO] Espacio estimado a instalar: 24,5 GB | Reserva: 10 GB | Utilizable: 110 GB
```

Con `-DryRun` **nun s'instala nada**. Siempres ye bonu executalo enantes.

### Exerciciu 3

Executa `.\Install-Apps.ps1 -DryRun -Drive D: -ReserveGB 20` y compara'l
resultáu. Cambia `D:` por una unidá qu'esista nel to equipu.

---

## Pasu 4. Instalar con seguridá

Cuando'l plan te convenza:

```powershell
.\Install-Apps.ps1 -Yes -ReportPath .\informe.json
```

- `-Yes` evita preguntes. Si nun caben toles aplicaciones, omítense **les más
  grandes** y avisa.
- `-ReportPath` crea `informe.json` y `informe.log`.

Si nun uses `-Yes` y falta espaciu, verás esti menú:

```
1) Omitir automaticamente las aplicaciones mas grandes
2) Continuar de todos modos
3) Abortar
```

**Recomendación:** elixi `1`. Elixi `2` namás si aceptes el riesgu de quedar ensin
espaciu. `-SkipSpaceCheck` ye l'equivalente ensin preguntes de la opción 2.

### Instalar solo un grupu

```powershell
.\Install-Apps.ps1 -Category Navegacion,Comunicacion -Yes
```

### Escluyir aplicaciones

```powershell
.\Install-Apps.ps1 -ExcludeId winrar,docker-desktop,powertoys -Yes
```

### Forzar reinstalación

```powershell
.\Install-Apps.ps1 -Force -ExcludeId edge -Yes
```

---

## Pasu 5. Lleer l'informe

Abre `informe.json`. La seición `summary` cunta cuantes aplicaciones hai en cada
estáu:

```json
"summary": {
  "already-installed": 21,
  "failed": 1,
  "installed": 64,
  "native": 9,
  "skip": 14
}
```

| Estáu | Significáu |
|---|---|
| `installed` | Instalada correutamente col xestor indicáu. |
| `already-installed` | Yá taba; nun se tocó. |
| `failed` | Falló en tolos xestores. Mira `informe.log`. |
| `skipped-space` | Omitióse por falta d'espaciu. |
| `no-manager` | Nun hai paquete nos xestores instalaos. |
| `native` / `skip` / `manual` | Nun rique instalación automática. |

Les salíes de cada instalación tán na carpeta qu'indica `logDir` nel informe.

---

## Pasu 6. Solución de problemes

| Síntoma | Causa | Solución |
|---|---|---|
| `No hay ningun gestor de paquetes` | Nun hai ningún xestor. | Instala App Installer dende Microsoft Store. |
| `El gestor X no esta instalado` | Usaste `-Manager` con un xestor ausente. | Usa `auto` o instala esi xestor. |
| `La unidad Z no existe` | La lletra camudó. | Executa ensin `-Drive` o usa una lletra de la tabla. |
| Munchos `failed` | Nun hai Internet, firewall o TLS. | Comprueba `ping winget.com` y vuelve a probar. |
| `Fallo al ejecutar` en Chocolatey | Falta alministrador. | Abre PowerShell como alministrador. |
| Omítense munches aplicaciones | Reserva demasiáu alta. | Baxa `-ReserveGB` o usa otra unidá con `-Drive`. |

---

## Vocabulariu

- **Partición**: división lóxica d'un discu que se monta como unidá (C:, D:).
- **Volume**: unidá que se ve nel Esplorador de ficheros.
- **GB**: 1024 MB. L'instalador guarda los tamaños en MB y los amuesa en GB.
- **winget**: xestor oficial de Microsoft.
- **Chocolatey / Scoop**: xestores de terceros; Scoop instala nel perfil del usuario.
- **Dry run**: simulación que nun camuda nada.
- **Mirror**: copia automática d'un repositoriu n'otra plataforma.

## Pasu siguiente

Llee [MIRROR.md](MIRROR.md) pa entender la sincronización GitHub ↔ GitLab y cómo
comprobar que funciona.
