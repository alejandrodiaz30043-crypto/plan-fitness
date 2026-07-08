# Plan Fitness — Casa & Gym

App de entrenamiento sin equipo, con progresión automática, calendario, temporizador de circuitos, plan de nutrición y cuentas de usuario con datos guardados en la nube (Supabase). Se puede instalar como app (PWA).

## 1. Configurar la base de datos (Supabase)

1. Entra a tu proyecto en [supabase.com](https://supabase.com) → tablero de tu proyecto.
2. En el menú izquierdo: **SQL Editor → New query**.
3. Copia y pega **todo** el contenido de `supabase-schema.sql` (está en esta misma carpeta) y dale **Run**.
   Esto crea la tabla `user_data` y las reglas de seguridad (cada usuario solo puede ver/editar sus propios datos).
4. En **Authentication → Providers**, confirma que **Email** esté activado (lo está por defecto).
5. (Opcional, para probar más rápido) En **Authentication → Settings**, puedes desactivar temporalmente "Confirm email" mientras pruebas — así no tienes que revisar el correo cada vez que crees una cuenta de prueba. Actívalo de nuevo antes de compartir la app con más gente.

La URL del proyecto y la llave pública (`anon key`) ya están puestas dentro de `index.html` — no hay que tocar nada más ahí.

## 2. Publicar en GitHub Pages

1. Sube **todo el contenido de esta carpeta** (`index.html`, `manifest.json`, `sw.js`, `supabase-schema.sql`, `README.md`, la carpeta `icons/`) a la raíz de tu repositorio.
2. **Settings → Pages → Source → Deploy from a branch** → rama `main` → carpeta `/ (root)`. Guarda.
3. En 1-2 minutos tu app queda en `https://tu-usuario.github.io/nombre-del-repo/`.

## 3. Instalar la app en el celular/computador

- **Android / Chrome / Edge:** botón "⬇️ Instalar app" dentro de la página, o menú ⋮ → "Instalar app".
- **iPhone / Safari:** botón compartir → "Agregar a pantalla de inicio".
- **Escritorio (Chrome/Edge):** ícono ⊕ en la barra de direcciones.

## Notas

- Cada usuario crea su propia cuenta (correo + contraseña) y ve solo su información — calendario, racha, check-ins, notas y plan de nutrición quedan ligados a su cuenta, no al dispositivo.
- El botón "Exportar progreso" (pestaña Progreso) sigue disponible como respaldo adicional.
- Si cambias el contenido del sitio en el futuro, sube el número de versión en `sw.js` (`CACHE_NAME = 'plan-fitness-v2'`, etc.) para que los usuarios reciban la actualización en vez de la copia guardada.

