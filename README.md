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

## Panel de entrenador / gimnasios (opcional)

Archivo aparte: `trainer.html` — comparte la misma cuenta y base de datos que `index.html`, pero es un archivo independiente.

**Cómo funciona (self-service, sin tocar nada a mano en Supabase):**
1. Corre `supabase-schema.sql` completo (crea la tabla `gyms`, la columna `role` en `user_data`, y las funciones necesarias — es seguro de re-correr, no borra nada).
2. Cualquier persona entra en `https://tu-usuario.github.io/tu-repo/trainer.html` con su correo y contraseña. Si esa cuenta no pertenece a ningún gimnasio todavía, puede crear el suyo ahí mismo — se vuelve el **dueño** al instante y le aparece un código de invitación de 6 caracteres.
3. Comparte ese código con sus miembros. Cada miembro lo ingresa desde la app principal (`index.html` → ⚙️ Ajustes → Gimnasio) para unirse.
4. Desde `trainer.html`, el dueño ve: total de miembros, activos esta semana, en riesgo de abandono (3+ días sin entrenar), racha y rol de cada uno — y puede ascender a alguien a **entrenador**, regresarlo a miembro, o expulsarlo del gimnasio, todo desde botones en la tabla.
5. Cualquier miembro/entrenador puede salir de su gimnasio por su cuenta desde Ajustes en `index.html`. El dueño no puede salir así (evita dejar un gimnasio sin dueño) — tendría que contactar soporte para transferir la propiedad.

No hay que editar nada a mano en Table Editor — todo el flujo (crear, unirse, ascender, expulsar, salir) pasa por funciones ya validadas en el servidor.


