# Espejo bidireccional GitHub ↔ GitLab

Este repositorio vive en dos plataformas y se sincroniza automáticamente:

| Plataforma | Repositorio | Rama |
|---|---|---|
| GitHub (origen) | `BENDER35/sc_autoinst_win_C20` | `main` |
| GitLab (espejo) | `BENDER_5000/sc_autoinst_win_C20` | `main` |

La sincronización es **bidireccional**: un push en cualquiera de los dos lados
acaba en el otro en pocos segundos.

## Cómo funciona

1. Un push a `main` dispara:
   - GitHub Actions → `.github/workflows/mirror-to-gitlab.yml`
   - GitLab CI/CD → `.gitlab-ci.yml`
2. El trabajo fetcha la rama del otro lado.
3. Si hay cambios por ambas partes, hace `git merge` (nunca fuerza un push).
4. Empuja el resultado al otro repositorio **con un commit de fusión marcado**:
   `chore: sync from GitLab [skip mirror]` / `chore: sync from GitHub [skip mirror]`.
5. El lado receptor ve el marcador `[skip mirror]` y no vuelve a sincronizar.
   Así se evita el bucle infinito.

> Si hay conflictos reales, el trabajo falla con un mensaje claro. No se pierde
> información: hay que resolver el conflicto a mano y volver a hacer push.

## Credenciales

| Secreto | Dónde | Uso |
|---|---|---|
| `GL_DEPLOY_KEY` | GitHub Actions (secret) | Clave SSH de despliegue con permiso de escritura en el proyecto de GitLab. |
| `GH_TOKEN` | GitLab CI/CD (variable enmascarada) | Token de GitHub con ámbitos `repo` y `workflow`. |

La llave privada **nunca** se guarda en el repositorio. GitLab usa la llave pública
como *deploy key*; GitHub usa el token por HTTPS.

### Crear la clave de despliegue (si hay que renovarla)

```bash
ssh-keygen -t ed25519 -C "mirror-bot" -f /tmp/gl_deploy -N ""
# La pública (/tmp/gl_deploy.pub) se añade en GitLab:
#   Project > Settings > Deploy keys > Add deploy key (Allow write access: ON)
# La privada (/tmp/gl_deploy) se guarda como secreto GL_DEPLOY_KEY en GitHub.
```

## Verificación manual

### 1. Probar GitHub → GitLab

```bash
echo "$(date -Is) prueba github -> gitlab" >> docs/MIRROR.md
git add docs/MIRROR.md
git commit -m "test: verificar mirror github -> gitlab"
git push origin main
gh run watch            # esperar a que termine el workflow
glab ci status          # en GitLab no debe aparecer pipeline por el marcador
git ls-remote https://gitlab.com/BENDER_5000/sc_autoinst_win_C20.git refs/heads/main
```

Comprueba que el último commit de GitLab contiene el mensaje `test: ...`.

### 2. Probar GitLab → GitHub

```bash
echo "$(date -Is) prueba gitlab -> github" >> docs/MIRROR.md
git add docs/MIRROR.md
git commit -m "test: verificar mirror gitlab -> github"
git push gitlab main
glab ci status          # esperar a que termine el pipeline
git ls-remote https://github.com/BENDER35/sc_autoinst_win_C20.git refs/heads/main
```

Comprueba que el último commit de GitHub contiene el mensaje `test: ...`.

### 3. Comparar finalmente

```bash
git fetch --all
echo "GitHub : $(git rev-parse origin/main)"
echo "GitLab : $(git rev-parse gitlab/main)"
```

Los dos hashes deben coincidir.

## Estado de la verificación

La verificación se realiza después de configurar los secretos; el resultado se
registra en el historial de commits y en las ejecuciones de los workflows.

- [x] Workflow de GitHub instalado
- [x] Pipeline de GitLab instalado
- [x] Marcador anti-bucles implementado
- [ ] Push de prueba GitHub → GitLab comprobado
- [ ] Push de prueba GitLab → GitHub comprobado
- [ ] Hashes finales iguales

## Recuperación

Si los repositorios divergen y el merge automático falla:

```bash
git fetch origin main && git fetch gitlab main
git checkout -b fix-mirror origin/main
git merge gitlab/main
# resolver conflictos, commit, push a ambos lados
git push origin fix-mirror:main
git push gitlab fix-mirror:main
```

No uses `--force` salvo que hayas confirmado que un lado está corrupto.
