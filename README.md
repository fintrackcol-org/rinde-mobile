# Rinde Mobile

App de **Rinde** para Android e iOS, hecha en Flutter. Rinde ayuda a manejar la plata a quienes
tienen ingresos irregulares: universitarios, independientes y trabajadores por días.

La app móvil **no reemplaza a Rinde Web**: las dos conviven y usan el mismo backend.

| | |
|---|---|
| Identificador (Android e iOS) | `online.rindecol.app` |
| Nombre visible | Rinde |
| Paquete Dart | `rinde_mobile` |
| Web y backend | [fintrackcol-org/fintrack](https://github.com/fintrackcol-org/fintrack) (React + Vite y API Node/Express) |

## Requisitos

- Flutter estable 3.50 o superior (Dart 3.14).
- Android Studio con el SDK de Android 36 y licencias aceptadas (`flutter doctor --android-licenses`).
- iOS: un Mac con Xcode. Desde Windows no se puede compilar ni probar iOS.

Comprueba el entorno con:

```bash
flutter doctor -v
```

## Primeros pasos

```bash
flutter pub get
```

### Ambientes y secretos

La app no tiene URLs del servidor escritas en el código. Se pasan al compilar:

```bash
cp config/example.json config/qa.json      # edita la URL de la API de QA
flutter run --dart-define-from-file=config/qa.json
```

| Variable | Para qué |
|---|---|
| `APP_ENV` | `local`, `qa` o `production` |
| `API_BASE_URL` | URL del backend, sin `/api/v1` |
| `WEB_URL` | Sitio web (términos y privacidad). Por defecto `https://www.rindecol.online` |

Reglas:

- `config/*.json` está en `.gitignore`; solo se sube `config/example.json`. **El repositorio es público.**
- Ninguna clave privada va en la app: todo lo que se compila dentro de un APK o IPA se puede extraer.
  Los secretos viven en el backend.
- Si `API_BASE_URL` apunta a producción (`api.rindecol.online`) y `APP_ENV` no es `production`,
  la app se niega a conectarse. Así nadie prueba contra datos reales por error.
- Sin `API_BASE_URL`, la app abre, pero no hace ninguna petición al servidor y lo explica en pantalla.
- Las sesiones se guardan cifradas (Keystore en Android, Keychain en iOS).
- Las llaves de firma (`*.jks`, `*.keystore`, `key.properties`) y los certificados de iOS
  nunca se suben.

## Ejecutar en Android

```bash
flutter emulators --launch Medium_Phone_API_36   # o conecta un teléfono con depuración USB
flutter run --dart-define-from-file=config/qa.json
```

APK de prueba:

```bash
flutter build apk --debug --dart-define-from-file=config/qa.json
```

## Pruebas

```bash
flutter analyze      # debe quedar en cero
flutter test
```

## Estructura

```
lib/
  app/         arranque, rutas y navegación con guardas de sesión (go_router)
  core/        configuración de ambientes, cliente HTTP (dio), errores de la API, sesión segura
  design/      sistema visual de Rinde: tokens (colores, tipografía, espacios, movimiento) y componentes
  features/    una carpeta por módulo, separada en data / domain / application / presentation
    auth/      login, registro, recuperar contraseña y sesión
    welcome/   bienvenida sin sesión
    entry/     arranque, términos y entrada a la app
    rin/       la mascota Rin, dibujada y animada igual que en la web
assets/        fuente Inter Tight (OFL), logo oficial, íconos lucide (ISC)
test/          pruebas unitarias y de widgets, con la misma estructura de lib/
```

Decisiones:

- Estado e inyección de dependencias con **Riverpod**.
- Navegación con **go_router**.
- HTTP con **dio**: renueva la sesión con el mismo contrato que la web.
- **flutter_secure_storage** para los tokens.
- **flutter_svg** para el logo y los íconos.
- **url_launcher** para abrir términos y privacidad.

## Fuentes de verdad

1. El frontend React **más reciente aprobado** (rama `main` de `fintrackcol-org/fintrack`). Es la
   referencia de pantallas, textos, validaciones y diseño.
2. Las auditorías en `docs/levantamiento-frontend/` de ese repositorio: sirven de trazabilidad.
3. El prototipo v5 y el Figma v4 son solo referencias secundarias.

Las fórmulas financieras viven en el backend. La app las muestra, no las recalcula.

## Reglas para no tocar Rinde Web

- Este repositorio es **solo** de la app móvil. Rinde Web se usa como referencia de **solo lectura**:
  desde aquí no se modifica su código, su Git, su backend ni su base de datos.
- Si la app necesita algo del backend que hoy no existe (por ejemplo, aceptar el login de Google
  nativo), se propone como cambio aparte en el repositorio de la web, con su propio PR y su revisión.
- Nunca se prueba contra producción ni con datos financieros reales.

## Licencias de recursos

- Inter Tight: SIL Open Font License 1.1 (`assets/fonts/OFL.txt`).
- Íconos Lucide: ISC (`assets/icons/LICENSE-lucide.txt`).
